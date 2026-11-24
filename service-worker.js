const JABZY_ICON="./jabzy-app-icon.svg";
self.addEventListener("install",event=>{self.skipWaiting();});
self.addEventListener("activate",event=>{event.waitUntil(self.clients.claim());});
self.addEventListener("notificationclick",event=>{
  event.notification.close();
  event.waitUntil((async()=>{
    const windows=await self.clients.matchAll({type:"window",includeUncontrolled:true});
    for(const client of windows){
      if("focus" in client){await client.focus();return;}
    }
    if(self.clients.openWindow)await self.clients.openWindow("./");
  })());
});
self.addEventListener("push",event=>{
  let data={title:"JABZY",body:"You have a new notification."};
  try{if(event.data)data={...data,...event.data.json()};}catch(e){}
  event.waitUntil(self.registration.showNotification(data.title||"JABZY",{
    body:data.body||"You have a new update.",
    icon:data.icon||JABZY_ICON,
    badge:data.badge||JABZY_ICON,
    tag:data.tag||"jabzy-push",
    data:{url:data.url||"./"}
  }));
});
