/* Miyako family trip service worker. No offline cache of private data. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));

/* Web Push must be opt-in and is not a guaranteed silent/background badge channel on iOS.
   Only the future authenticated server sender may send these payloads. */
self.addEventListener('push', event => {
  let data={};
  try { data=event.data ? event.data.json() : {}; } catch (_) {}
  const rawCount=data.unread_count;
  const count=Number(rawCount);
  const badgeCount=rawCount!==undefined && rawCount!==null && rawCount!=='' && Number.isFinite(count) ? Math.max(0,Math.floor(count)) : null;
  event.waitUntil((async()=>{
    // Schedule both operations immediately; a rejected badge promise must not block the visible push.
    let badgePromise=Promise.resolve();
    if(badgeCount!==null){
      try {
        const nav=self.navigator;
        if(badgeCount===0 && typeof nav?.clearAppBadge==='function'){
          badgePromise=Promise.resolve(nav.clearAppBadge());
        }else if(badgeCount>0 && typeof nav?.setAppBadge==='function'){
          badgePromise=Promise.resolve(nav.setAppBadge(badgeCount));
        }else{
          console.warn('Background badging API unavailable', {badgeCount});
        }
      }catch(error){
        console.error('Background badge call failed', String(error));
      }
    }
    const notificationPromise=self.registration.showNotification('宮古島家人有新動態', {
      body:badgeCount===null?'診斷：推播未包含有效未讀數字':`診斷：未讀通知 ${badgeCount} 則`,
      icon:'./icon-192.png',
      badge:'./icon-192.png',
      tag:'miyako-family-update',
      renotify:false,
      data:{url:self.registration.scope}
    });
    const results=await Promise.allSettled([badgePromise,notificationPromise]);
    if(results[0].status==='rejected')console.error('Background badge rejected',String(results[0].reason));
    if(results[1].status==='rejected')console.error('Push notification rejected',String(results[1].reason));
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
