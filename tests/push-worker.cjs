const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const handlers={},shown=[],opened=[];
vm.runInNewContext(fs.readFileSync(__dirname+'/../dist/sw.js','utf8'),{URL,self:{registration:{scope:'https://samuelacuna12.github.io/verdelia/',showNotification:async(t,o)=>shown.push({t,o})},location:{origin:'https://samuelacuna12.github.io',href:'https://samuelacuna12.github.io/verdelia/sw.js'},addEventListener:(n,f)=>handlers[n]=f,clients:{matchAll:async()=>[],openWindow:async u=>opened.push(u)}}});
(async()=>{let work;handlers.push({data:{json:()=>({title:'Nuevo pedido',body:'Revisar pedido',route:'pedidos',tag:'event-1'})},waitUntil:p=>work=p});await work;assert.equal(shown[0].o.data.url,'https://samuelacuna12.github.io/verdelia/#pedidos');assert(shown[0].o.icon.includes('/verdelia/assets/'));
handlers.notificationclick({notification:{close(){},data:shown[0].o.data},waitUntil:p=>work=p});await work;assert.equal(opened.length,1);
handlers.notificationclick({notification:{close(){},data:{url:'https://attacker.invalid/'}},waitUntil:p=>work=p});await work;assert.equal(opened.length,1,'Must not open an external notification target');
handlers.push({data:{json:()=>({route:'https://attacker.invalid/'})},waitUntil:p=>work=p});await work;assert(shown[1].o.data.url.endsWith('#resumen'));
console.log('PASS: push displays notification, opens app route, rejects external URL');})().catch(e=>{console.error(e);process.exitCode=1});
