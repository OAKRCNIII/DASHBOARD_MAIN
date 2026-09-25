-- ============================================================
-- กันเงินที่ต้นทาง (Supabase RLS) — BOW/TARN/PLA และ manager ทุกคน
-- รันใน Supabase → SQL Editor (ครั้งเดียว, idempotent รันซ้ำได้)
-- ต้นทาง: admin(OAK,SUPAN)=เห็นเงินหมด · transport(YAI)=เห็นแค่ transport_bills · ที่เหลือ=ไม่เห็นเงิน
-- ============================================================

-- 1) ตาราง ACL: ใครเห็นเงินได้ (user แก้เองไม่ได้ — ไม่มี policy ให้ authenticated เขียน/อ่านตรง)
create table if not exists public.dash_money_acl(
  uid       uuid primary key references auth.users(id) on delete cascade,
  money     boolean not null default false,   -- เห็นเงินทุกอย่าง (admin)
  transport boolean not null default false    -- เห็นเฉพาะค่าขนส่ง (transport)
);
alter table public.dash_money_acl enable row level security;
-- ตั้งใจไม่สร้าง policy → authenticated เข้าตรงไม่ได้เลย; อ่านผ่านฟังก์ชัน SECURITY DEFINER ด้านล่างเท่านั้น

-- 2) ฟังก์ชันเช็คสิทธิ์ (SECURITY DEFINER = อ่าน acl ทะลุ RLS ได้)
create or replace function public.is_money() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.dash_money_acl a where a.uid = auth.uid() and a.money);
$$;
create or replace function public.is_transport() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.dash_money_acl a where a.uid = auth.uid() and (a.money or a.transport));
$$;
revoke all on function public.is_money() from public;
revoke all on function public.is_transport() from public;
grant execute on function public.is_money() to authenticated;
grant execute on function public.is_transport() to authenticated;

-- 3) ใส่รายชื่อคนที่เห็นเงินได้
insert into public.dash_money_acl(uid, money, transport) values
  ('9bf567e9-ad12-48cb-8a27-50b2da90fde4', true,  false),  -- OAK_THIRA  (admin)
  ('1fd35509-ac72-4d0b-bb13-f21296dcb801', true,  false),  -- SUPAN_ANTS (admin)
  ('397cedbc-fe60-4a8f-a44c-383adb4d0252', false, true)    -- YAI_THIRA  (transport)
on conflict (uid) do update set money = excluded.money, transport = excluded.transport;

-- 4) ย้ายค่ารถไฟออกจาก invoices → ตาราง invoice_train (admin เท่านั้น)
create table if not exists public.invoice_train(
  invoice_no      text primary key,
  train_thb       numeric,
  train_paid_date date,
  updated_at      timestamptz default now()
);
-- คัดลอกข้อมูลเดิมก่อนลบคอลัมน์
insert into public.invoice_train(invoice_no, train_thb, train_paid_date)
  select invoice_no, train_thb, train_paid_date
  from public.invoices
  where train_thb is not null or train_paid_date is not null
on conflict (invoice_no) do update
  set train_thb = excluded.train_thb, train_paid_date = excluded.train_paid_date;

grant select, insert, update, delete on public.invoice_train to authenticated;
alter table public.invoice_train enable row level security;
drop policy if exists train_admin on public.invoice_train;
create policy train_admin on public.invoice_train for all
  using (public.is_money()) with check (public.is_money());

-- ลบคอลัมน์เงินออกจาก invoices (ข้อมูลอยู่ใน invoice_train แล้ว) → invoices เหลือแต่ข้อมูล operation ใครอ่านก็ได้
alter table public.invoices drop column if exists train_thb;
alter table public.invoices drop column if exists train_paid_date;

-- 5) ล็อกตารางเงินล้วน → admin เท่านั้น (แทน policy auth_all เดิม)
do $$
declare t text;
begin
  foreach t in array array['su_statement','billing_ants','payments_ants','ogm_prices','price_update','bank_balance']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists auth_all on public.%I', t);
    execute format('drop policy if exists money_admin on public.%I', t);
    execute format('create policy money_admin on public.%I for all using (public.is_money()) with check (public.is_money())', t);
  end loop;
end $$;

-- transport_bills → admin + transport
alter table public.transport_bills enable row level security;
drop policy if exists auth_all on public.transport_bills;
drop policy if exists tr_gate on public.transport_bills;
create policy tr_gate on public.transport_bills for all
  using (public.is_transport()) with check (public.is_transport());

-- (invoices ไม่แตะ policy — ไม่มีเงินแล้ว ใครอ่านก็ได้ตามเดิม)

-- ============================================================
-- เช็คผล
-- ============================================================
select tablename, policyname, cmd, qual
from pg_policies
where schemaname='public'
  and tablename in ('invoices','transport_bills','su_statement','billing_ants',
                    'payments_ants','ogm_prices','price_update','bank_balance','invoice_train')
order by tablename, cmd;

select * from public.dash_money_acl;
select count(*) as train_rows_moved from public.invoice_train;
