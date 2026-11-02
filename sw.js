/* Miyako family trip service worker. No offline cache of private data. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));

/* Web Push must be opt-in and is not a guaranteed silent/background badge channel on iOS.
   Only the future authenticated server sender may send these payloads. */
self.addEventListener('push', event => {
  let data={};
  try { data=event.data ? event.data.json() : {}; } catch (_) {}
  const count=Number(data.unread_count);
  const badgeCount=Number.isFinite(count) ? Math.max(0,Math.floor(count)) : null;
  event.waitUntil((async()=>{
    if(badgeCount!==null){
      try {
        if(badgeCount===0 && self.registration.clearAppBadge) await self.registration.clearAppBadge();
        else if(badgeCount>0 && self.registration.setAppBadge) await self.registration.setAppBadge(badgeCount);
      } catch (_) {}
    }
    /* iOS Web Push is not a supported silent push mechanism.
       A real push must display a user-visible notification. */
    await self.registration.showNotification('宮古島家人有新動態', {
      body:'開啟 App 查看家人共用更新',
      icon:'./icon-192.png',
      badge:'./icon-192.png',
      tag:'miyako-family-update',
      renotify:false,
      data:{url:self.registration.scope}
    });
  })());
});
self.addEventListener('notificationclick',event=>{
  event.notification.close();
  event.waitUntil((async()=>{
    const url=event.notification.data?.url||self.registration.scope;
    const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
    for(const client of windows){
      if(client.url.startsWith(self.registration.scope)){
        await client.focus();
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
