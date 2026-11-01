/* Miyako family trip: minimal service worker.
   Intentionally does not cache requests, to avoid stale pages or user data. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
