/// <reference lib="webworker" />

/**
 * Service worker for Markdown PWA — caches the app shell for offline use.
 *
 * Strategy: network-first for navigations/HTML (so deployed updates are picked
 * up, falling back to the cached shell offline), cache-first for content-hashed
 * assets (immutable). `activate` evicts caches whose key != CACHE_NAME.
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

function cachePut(request: Request, response: Response): Response {
  if (response.status === 200) {
    const clone = response.clone();
    caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
  }
  return response;
}

self.addEventListener("fetch", (event: FetchEvent) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== location.origin) return;

  const isNavigation =
    request.mode === "navigate" ||
    (request.headers.get("accept") || "").includes("text/html");

  if (isNavigation) {
    // Network-first for the HTML shell: a cache-first shell would pin the old
    // index.html (and its old hashed asset references) forever, so deploys are
    // never seen. Fall back to the cached shell only when offline.
    event.respondWith(
      fetch(request)
        .then((response) => cachePut(request, response))
        .catch(async () => {
          const cached = await caches.match(request);
          return cached ?? (await caches.match("/index.html")) ?? Response.error();
        })
    );
    return;
  }

  // Cache-first for other assets — content-hashed bundles are immutable, so a
  // new deploy produces new filenames rather than stale hits.
  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request).then((response) => cachePut(request, response));
    })
  );
});
