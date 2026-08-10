const CACHE = 'dashboard-v3';
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
  // Network-first: ดึงข้อมูลสดเสมอ ถ้าออฟไลน์ค่อย fallback cache
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
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
