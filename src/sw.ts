/// <reference lib="webworker" />

/**
 * Service worker for Markdown PWA — caches the app shell for offline use.
 *
 * Strategy: cache-first for app shell assets, network-first for everything else.
 * On install a new cache version replaces the old one so users get updates.
 */

declare const self: ServiceWorkerGlobalScope;

const CACHE_NAME = "markdown-v1";

const APP_SHELL: string[] = [
  "/",
  "/index.html",
  "/manifest.json",
];

self.addEventListener("install", (event: ExtendableEvent) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL))
  );
  // Activate immediately without waiting for old tabs to close
  self.skipWaiting();
});

self.addEventListener("activate", (event: ExtendableEvent) => {
  // Evict any caches from older versions
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event: FetchEvent) => {
  const url = new URL(event.request.url);

  // Only cache same-origin requests
  if (url.origin !== location.origin) return;

  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached;

      return fetch(event.request).then((response) => {
        // Cache successful GET responses for offline use
        if (
          event.request.method === "GET" &&
          response.status === 200
        ) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, clone);
          });
        }
        return response;
      });
    })
  );
});
