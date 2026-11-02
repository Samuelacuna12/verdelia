import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import webpush from 'npm:web-push@3.6.7';

const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}').default;
const supabase = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey, {auth: {persistSession: false, autoRefreshToken: false}});
const bucket = 'verdelia-backups';
const cors = {'Access-Control-Allow-Origin':'https://samuelacuna12.github.io','Access-Control-Allow-Headers':'content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'};
const reply = (body: unknown, status=200) => new Response(JSON.stringify(body), {status,headers:{...cors,'Content-Type':'application/json'}});
async function rpc(action: string, data: Record<string,unknown>={}) {
  const r = await supabase.rpc('verdelia_background',{action,data});
  if(r.error) {console.error('verdelia_rpc_error',action,r.error.code,r.error.message);throw new Error('Database operation failed: '+action);}
  return r.data;
}
function allowedEndpoint(endpoint: string) {
  try {
    const u=new URL(endpoint);
    return u.protocol==='https:' && !u.port && !u.username && !u.password && !u.hash &&
      (u.hostname==='fcm.googleapis.com' || /(^|\.)push\.apple\.com$/.test(u.hostname) || /(^|\.)push\.services\.mozilla\.com$/.test(u.hostname));
  } catch {return false;}
}
const digest = async (bytes: Uint8Array) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');
async function ensureBucket() {
  const r=await supabase.storage.getBucket(bucket);
  if(r.error) {
    const created=await supabase.storage.createBucket(bucket,{public:false,fileSizeLimit:52428800,allowedMimeTypes:['application/gzip']});
    if(created.error && !/exist/i.test(created.error.message)) throw new Error('Could not create private backup storage');
  } else if(r.data.public) throw new Error('Backup bucket must be private');
}
async function run() {
  let config=await rpc('config');
  if(!config.public_key) {
    const keys=webpush.generateVAPIDKeys();
    await rpc('init_keys',{public_key:keys.publicKey,private_key:keys.privateKey});
    config=await rpc('config');
  }
  webpush.setVapidDetails(config.subject,config.public_key,config.private_key);
  const deliveries=await rpc('claim_push');
  // Small concurrency keeps provider connections and runtime within bounds.
  for(let start=0;start<deliveries.length;start+=5) {
    await Promise.all(deliveries.slice(start,start+5).map(async (d: any)=>{
      let ok=false,gone=false,error='';
      try {
        if(!allowedEndpoint(d.endpoint)) throw new Error('Unsupported push endpoint');
        await webpush.sendNotification({endpoint:d.endpoint,keys:d.keys},JSON.stringify(d.payload),{TTL:Math.max(0,Math.min(86400,Math.floor((new Date(d.expires_at).getTime()-Date.now())/1000))),urgency:'high',timeout:10000});
        ok=true;
      } catch(e) {gone=[404,410].includes(e.statusCode);error=e.statusCode?'Push HTTP '+e.statusCode:'Push delivery unavailable';}
      await rpc('ack_push',{event_id:d.event_id,subscription_id:d.subscription_id,lease:d.lease,ok,gone,error});
    }));
  }
  const backup=await rpc('claim_backup');
  if(backup) {
    try {
      await ensureBucket();
      const json=JSON.stringify(backup.payload);
      const compressed=new Uint8Array(await new Response(new Blob([json]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer());
      if(compressed.byteLength>52428800) throw new Error('Backup exceeds the configured size limit');
      const checksum=await digest(compressed);
      const uploaded=await supabase.storage.from(bucket).upload(backup.path,compressed,{contentType:'application/gzip',upsert:true,cacheControl:'0'});
      if(uploaded.error) throw new Error('Backup upload failed');
      const downloaded=await supabase.storage.from(bucket).download(backup.path);
      if(downloaded.error) throw new Error('Backup verification download failed');
      const verify=new Uint8Array(await downloaded.data.arrayBuffer());
      if(await digest(verify)!==checksum) throw new Error('Backup checksum mismatch');
      const restored=JSON.parse(await new Response(new Blob([verify]).stream().pipeThrough(new DecompressionStream('gzip'))).text());
      for(const [table,count] of Object.entries(backup.payload.row_counts)) {
        if(restored.tables[table]?.length!==count) throw new Error('Backup row verification failed');
      }
      await rpc('ack_backup',{id:backup.id,ok:true,sha256:checksum,bytes:compressed.byteLength,row_counts:backup.payload.row_counts});
      // Only prune old copies after successfully verifying a new one.
      for(const old of await rpc('expired_backups')) {
        const removed=await supabase.storage.from(bucket).remove([old.path]);
        if(!removed.error) await rpc('pruned_backup',{id:old.id});
      }
    } catch(e) {
      await rpc('ack_backup',{id:backup.id,ok:false,error:String(e.message).slice(0,200)});
    }
  }
  return {ok:true,processed:deliveries.length,backup:!!backup};
}
Deno.serve(async req=>{
  if(req.method==='OPTIONS') return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST') return reply({error:'Method not allowed'},405);
  try {
    const text=await req.text();
    if(text.length>10000) return reply({error:'Request too large'},413);
    const body=JSON.parse(text);
    if(body.action==='download') {
      const check=await supabase.rpc('verdelia_automation',{action:'download',data:{session:body.session,id:body.id}});
      if(check.error) return reply({error:'Inicia sesión para descargar el respaldo.'},401);
      const signed=await supabase.storage.from(bucket).createSignedUrl(check.data.path,60,{download:'Verdelia-respaldo-'+body.id+'.json.gz'});
      if(signed.error) return reply({error:'No se pudo preparar la descarga.'},503);
      return reply({url:signed.data.signedUrl});
    }
    if(body.action!=='run' || !await rpc('verify',{secret:req.headers.get('x-verdelia-job')})) return reply({error:'Unauthorized'},401);
    return reply(await run());
  } catch(e) {console.error('verdelia_worker_error',e.name,e.message);return reply({error:'Automation unavailable'},503);}
});
