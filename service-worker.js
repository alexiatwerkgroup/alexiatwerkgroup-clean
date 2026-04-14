const CACHE_NAME = 'alexia-pwa-v2.4.0';
const RUNTIME_CACHE = 'alexia-runtime-v2.4.0';
const OFFLINE_URL = '/';

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll([
      '/',
      '/index.html',
      '/manifest.json',
      '/icon-192.png',
      '/icon-512.png',
      '/apple-touch-icon.png',
      '/screenshot-mobile.png',
      '/screenshot-desktop.png'
    ])).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(
      keys.filter(key => ![CACHE_NAME, RUNTIME_CACHE].includes(key))
        .map(key => caches.delete(key))
    )).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const isPage = request.mode === 'navigate' || (request.headers.get('accept') || '').includes('text/html');
  if (isPage) {
    const isVideoPage = url.pathname.startsWith('/playlist/') && url.pathname.replace('/playlist/', '').length > 3;
    event.respondWith(
      fetch(request)
        .then(async response => {
          if (response.status === 404) {
            return isVideoPage ? Response.redirect('/playlist/', 302) : response;
          }
          if (response.status === 200 && isVideoPage) {
            // Detectar página genérica (Cloudflare fallback = ~9675 bytes con "Official Entry")
            const clone = response.clone();
            const text = await clone.text();
            if (text.length < 15000 && text.includes('Official Entry')) {
              // Es la página genérica — redirigir a playlist
              return Response.redirect('/playlist/', 302);
            }
            // Es una página real — cachear
            const copy = new Response(text, { status: response.status, headers: response.headers });
            const cacheClone = new Response(text, { status: response.status, headers: response.headers });
            caches.open(RUNTIME_CACHE).then(cache => cache.put(request, cacheClone));
            return copy;
          }
          // No video page — cachear normalmente
          const copy = response.clone();
          caches.open(RUNTIME_CACHE).then(cache => cache.put(request, copy));
          return response;
        })
        .catch(() => caches.match(request).then(r => r || caches.match('/playlist/') || caches.match(OFFLINE_URL)))
    );
    return;
  }

  event.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;
      return fetch(request).then(response => {
        if (!response || response.status !== 200 || response.type === 'opaque') return response;
        const copy = response.clone();
        caches.open(RUNTIME_CACHE).then(cache => cache.put(request, copy));
        return response;
      });
    })
  );
});
