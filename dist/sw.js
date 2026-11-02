const CACHE_PREFIX='verdelia-shell-'+new URL(self.registration.scope).pathname+'-';
const CACHE=CACHE_PREFIX+'v4';
const FILES=['./','./index.html','./styles.css','./app.css?v=20261102-3','./app.js?v=20261102-3','./config.js','./manifest.webmanifest','./assets/favicon.svg','./assets/icon-192.png','./assets/icon-512.png','./assets/apple-touch-icon.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES)));self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith(CACHE_PREFIX)&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
// Never cache financial API requests, credentials or personal data.
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==self.location.origin)return;if(!FILES.some(f=>new URL(f,self.location.href).pathname===u.pathname))return;e.respondWith(fetch(e.request).then(r=>{if(r.ok){const copy=r.clone();caches.open(CACHE).then(c=>c.put(e.request,copy))}return r}).catch(()=>caches.open(CACHE).then(c=>c.match(e.request))))});
self.addEventListener('push',event=>{
 let data={};try{data=event.data?.json()||{}}catch{}
 const route=/^(pedidos|inventario(?:\?accion=reposicion)?|ajustes)$/.test(data.route||'')?data.route:'resumen';
 event.waitUntil(self.registration.showNotification(String(data.title||'Verdélia'),{
  body:String(data.body||'Tienes novedades en tu negocio.'),tag:String(data.tag||'verdelia'),
  icon:new URL('./assets/icon-192.png',self.registration.scope).href,
  badge:new URL('./assets/icon-192.png',self.registration.scope).href,
  data:{url:self.registration.scope+'#'+route}
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  const url=new URL(event.notification.data?.url||self.registration.scope);
  if(url.origin!==self.location.origin||url.pathname!==new URL(self.registration.scope).pathname)return;
  const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  const app=windows.find(c=>new URL(c.url).pathname===url.pathname);
  if(app){await app.navigate(url.href);await app.focus()}else await self.clients.openWindow(url.href);
 })());
});
