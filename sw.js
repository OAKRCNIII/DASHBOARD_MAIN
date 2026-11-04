const CACHE = 'dashboard-v4';
const ASSETS = ['./', './index.html'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const req = e.request;
  // หน้า HTML (index.html / navigate) → ดึงสดเสมอ bypass แคชเบราว์เซอร์ (กันเห็นของเก่าหลัง deploy)
  const isHTML = req.mode === 'navigate' || req.destination === 'document';
  if (isHTML) {
    e.respondWith(
      fetch(new Request(req, { cache: 'reload' }))
        .then(res => {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put('./index.html', copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(req).then(r => r || caches.match('./index.html')))
    );
    return;
  }
  // อื่นๆ: network-first ดึงสด ถ้าออฟไลน์ค่อย fallback cache
  e.respondWith(
    fetch(req).catch(() => caches.match(req))
  );
});

/* ── Web Push: รับข้อความแล้วเด้ง notification ── */
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data.json(); } catch (_) { d = { title: 'ANTS', body: (e.data && e.data.text()) || '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'ANTS', {
    body: d.body || '',
    data: { url: d.url || './' },
    tag: d.tag || 'ants-alert',
    renotify: true,
    requireInteraction: true,
    vibrate: [200, 100, 200],
  }));
});

/* กด notification → โฟกัสแอปที่เปิดอยู่ ไม่งั้นเปิดใหม่ที่ scope ของแอป (path ที่ถูก) */
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const base = self.registration.scope;   // เช่น https://xxx.github.io/DASHBOARD_MAIN/
  e.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const c of list) { if (c.url.startsWith(base) && 'focus' in c) return c.focus(); }
    if (clients.openWindow) return clients.openWindow(base);
  }));
});
