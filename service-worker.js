const CACHE_NAME = 'samara-care-v8-no-edge';
const PATCH_SCRIPT = './employee-fix.js?v=8';

self.addEventListener('install', event => {
  self.skipWaiting();
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll([
    './', './config.js?v=7', './manifest.webmanifest', PATCH_SCRIPT
  ]).catch(() => undefined)));
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);

  if (request.mode === 'navigate' && url.origin === self.location.origin) {
    event.respondWith((async () => {
      try {
        const response = await fetch(request, { cache: 'no-store' });
        let html = await response.text();
        if (!html.includes('employee-fix.js')) {
          html = html.replace('</body>', `<script src="${PATCH_SCRIPT}"></script></body>`);
        }
        return new Response(html, {
          status: response.status,
          statusText: response.statusText,
          headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }
        });
      } catch (error) {
        const cached = await caches.match('./');
        if (!cached) throw error;
        let html = await cached.text();
        if (!html.includes('employee-fix.js')) {
          html = html.replace('</body>', `<script src="${PATCH_SCRIPT}"></script></body>`);
        }
        return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
      }
    })());
    return;
  }

  event.respondWith(
    fetch(request).then(response => {
      if (request.method === 'GET' && url.origin === self.location.origin) {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
      }
      return response;
    }).catch(() => caches.match(request))
  );
});
