-- Apply after schema.sql and auth.sql. Only Verdélia objects are changed.
begin;
create table if not exists verdelia_private.automation_config (
 id boolean primary key default true check(id), public_key text,
 private_key_id uuid, job_secret_id uuid, worker_url text not null,
 last_scan_at timestamptz
);
insert into verdelia_private.automation_config(id,worker_url)
values(true,'https://ntafomzqtjdfslanggak.supabase.co/functions/v1/verdelia-automation') on conflict do nothing;
do $$ begin
 if (select job_secret_id is null from verdelia_private.automation_config) then
  update verdelia_private.automation_config set job_secret_id=vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'verdelia_job_secret') where id=true;
 end if;
end $$;
create table if not exists verdelia_private.push_subscriptions (
 id uuid primary key default gen_random_uuid(), endpoint text not null unique,
 p256dh text not null, auth text not null, label text not null default 'Mi dispositivo',
 active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists verdelia_private.push_events (
 id uuid primary key default gen_random_uuid(), kind text not null, title text not null, body text not null,
 route text not null, dedupe text not null unique, created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '24 hours'
);
create table if not exists verdelia_private.push_deliveries (
 event_id uuid references verdelia_private.push_events(id) on delete cascade,
 subscription_id uuid references verdelia_private.push_subscriptions(id) on delete cascade,
 status text not null default 'pending' check(status in('pending','sending','sent','failed','expired')),
 attempts integer not null default 0, next_attempt timestamptz not null default now(),
 lease uuid, leased_until timestamptz, sent_at timestamptz, last_error text,
 primary key(event_id,subscription_id)
);
create index if not exists verdelia_push_pending on verdelia_private.push_deliveries(next_attempt) where status in('pending','sending');
create table if not exists verdelia_private.stock_alert_state (
 product_id uuid primary key references verdelia_private.products(id) on delete cascade,
 level text not null, updated_at timestamptz not null default now()
);
create table if not exists verdelia_private.backup_runs (
 id uuid primary key default gen_random_uuid(), job_key text not null unique,
 status text not null default 'pending' check(status in('pending','running','completed','failed','deleted')),
 created_at timestamptz not null default now(), completed_at timestamptz, leased_until timestamptz,
 attempts integer not null default 0, next_attempt timestamptz not null default now(),
 object_path text, sha256 text, bytes bigint, row_counts jsonb, error text
);
do $$ declare t text; begin
 foreach t in array array['automation_config','push_subscriptions','push_events','push_deliveries','stock_alert_state','backup_runs'] loop
  execute format('alter table verdelia_private.%I enable row level security',t);
  execute format('revoke all on verdelia_private.%I from public,anon,authenticated',t);
 end loop;
end $$;

create or replace function verdelia_private.wake_worker() returns void language plpgsql security definer set search_path='' as $$
declare c verdelia_private.automation_config; secret text;
begin
 select * into c from verdelia_private.automation_config;
 select decrypted_secret into secret from vault.decrypted_secrets where id=c.job_secret_id;
 perform net.http_post(url:=c.worker_url,headers:=jsonb_build_object('Content-Type','application/json','x-verdelia-job',secret),body:='{"action":"run"}'::jsonb,timeout_milliseconds:=10000);
end $$;

create or replace function verdelia_private.enqueue_push(k text,t text,b text,r text,d text,device uuid default null) returns uuid language plpgsql set search_path='' as $$
declare eid uuid;
begin
 insert into verdelia_private.push_events(kind,title,body,route,dedupe) values(k,t,b,r,d) on conflict(dedupe) do nothing returning id into eid;
 if eid is not null then
  insert into verdelia_private.push_deliveries(event_id,subscription_id)
  select eid,id from verdelia_private.push_subscriptions where active and (device is null or id=device);
 end if;
 return eid;
end $$;

create or replace function verdelia_private.order_notification() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (select pending_orders from verdelia_private.alert_preferences) then
  perform verdelia_private.enqueue_push('order','Nuevo pedido P-'||new.number,'Abre Verdélia para revisar y confirmar el pedido.','pedidos','order:'||new.id);
  if exists(select 1 from verdelia_private.push_subscriptions where active) then perform verdelia_private.wake_worker();end if;
 end if;
 return new;
end $$;
drop trigger if exists verdelia_order_push on verdelia_private.orders;
create trigger verdelia_order_push after insert on verdelia_private.orders for each row execute function verdelia_private.order_notification();

create or replace function verdelia_private.automation_tick() returns void language plpgsql security definer set search_path='' as $$
declare p record; previous text; level_now text;
begin
 perform pg_advisory_xact_lock(742839128);
 for p in select id,name,stock-reserved available,minimum,unit,active from verdelia_private.products where kind='product' loop
  level_now:=case when not p.active then 'ok' when p.available<=0 then 'out' when p.available<=p.minimum then 'low' else 'ok' end;
  select level into previous from verdelia_private.stock_alert_state where product_id=p.id;
  if level_now<>'ok' and level_now is distinct from previous and (select stock from verdelia_private.alert_preferences) then
   perform verdelia_private.enqueue_push('stock',case when level_now='out' then 'Producto agotado' else 'Inventario por reponer' end,p.name||': '||round(p.available,3)||' '||p.unit||' disponibles.','inventario?accion=reposicion','stock:'||p.id||':'||gen_random_uuid());
  end if;
  insert into verdelia_private.stock_alert_state(product_id,level) values(p.id,level_now) on conflict(product_id) do update set level=excluded.level,updated_at=now();
 end loop;
 update verdelia_private.automation_config set last_scan_at=now() where id=true;
 update verdelia_private.push_deliveries d set status='expired' from verdelia_private.push_events e where d.event_id=e.id and e.expires_at<now() and d.status in('pending','sending');
 update verdelia_private.push_deliveries set status='failed',last_error='Delivery attempts exhausted' where status in('pending','sending') and attempts>=5 and (leased_until is null or leased_until<now());
 update verdelia_private.backup_runs set status='failed',error='Backup attempts exhausted' where status in('pending','running') and attempts>=3 and (leased_until is null or leased_until<now());
 delete from verdelia_private.push_events where created_at<now()-interval '30 days';
 if exists(select 1 from verdelia_private.push_deliveries where status in('pending','sending') and next_attempt<=now() and (leased_until is null or leased_until<now()))
 or exists(select 1 from verdelia_private.backup_runs where status in('pending','running') and next_attempt<=now() and (leased_until is null or leased_until<now())) then perform verdelia_private.wake_worker();end if;
end $$;

create or replace function verdelia_private.queue_daily_backup() returns void language plpgsql security definer set search_path='' as $$
begin
 insert into verdelia_private.backup_runs(job_key) values('daily:'||(now() at time zone 'America/Bogota')::date) on conflict do nothing;
 perform verdelia_private.wake_worker();
end $$;

-- Complete business data, no passwords, sessions, recovery codes or push keys.
create or replace function verdelia_private.backup_payload() returns jsonb language plpgsql set search_path='' as $$
declare t text; rows jsonb; result jsonb:='{}'; counts jsonb:='{}'; seqs jsonb;
begin
 perform pg_advisory_xact_lock(742839127);
 foreach t in array array['settings','alert_preferences','products','recipes','sales','orders','stock_moves','purchases','lots','cash_moves','closings','audit','requests'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from verdelia_private.%I x',t) into rows;
  result:=result||jsonb_build_object(t,rows);counts:=counts||jsonb_build_object(t,jsonb_array_length(rows));
 end loop;
 select jsonb_object_agg(sequencename,last_value) into seqs from pg_sequences where schemaname='verdelia_private';
 return jsonb_build_object('format','verdelia-business-backup','version',1,'created_at',now(),'timezone','America/Bogota','tables',result,'row_counts',counts,'sequences',seqs);
end $$;

create or replace function verdelia_private.automation_admin(action text,data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb; sid uuid; ep text; b verdelia_private.backup_runs;
begin
 perform verdelia_private.require_admin(data->>'session');
 if action='status' then
  return jsonb_build_object('public_key',(select public_key from verdelia_private.automation_config),'last_scan_at',(select last_scan_at from verdelia_private.automation_config),
  'devices',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',label,'active',active,'created_at',created_at)) from verdelia_private.push_subscriptions where active),'[]'::jsonb),
  'backups',coalesce((select jsonb_agg(to_jsonb(x)-'job_key'-'object_path'-'sha256'-'lease') from (select * from verdelia_private.backup_runs where status<>'deleted' order by created_at desc limit 35)x),'[]'::jsonb),
  'delivery',jsonb_build_object('sent',(select count(*) from verdelia_private.push_deliveries where status='sent' and sent_at>now()-interval '24 hours'),'failed',(select count(*) from verdelia_private.push_deliveries where status='failed' and next_attempt>now()-interval '24 hours')));
 elsif action='subscribe' then
  s:=data->'subscription';ep:=s->>'endpoint';
  if ep is null or length(ep)>2048 or ep!~'^https://([a-z0-9-]+\.)*push\.apple\.com/' and ep!~'^https://fcm\.googleapis\.com/' and ep!~'^https://([a-z0-9-]+\.)*push\.services\.mozilla\.com/' then raise exception 'Este servicio de notificaciones no es compatible.';end if;
  if coalesce(s->'keys'->>'p256dh','')!~'^[A-Za-z0-9_-]{87}=?$' or coalesce(s->'keys'->>'auth','')!~'^[A-Za-z0-9_-]{22}={0,2}$' then raise exception 'Suscripción inválida. Vuelve a activar las notificaciones.';end if;
  if (select count(*) from verdelia_private.push_subscriptions where active and endpoint<>ep)>=10 then raise exception 'Ya hay diez dispositivos. Desactiva uno para continuar.';end if;
  insert into verdelia_private.push_subscriptions(endpoint,p256dh,auth,label) values(ep,s->'keys'->>'p256dh',s->'keys'->>'auth',left(coalesce(data->>'label','Mi dispositivo'),60)) on conflict(endpoint) do update set p256dh=excluded.p256dh,auth=excluded.auth,label=excluded.label,active=true,updated_at=now() returning id into sid;
  perform verdelia_private.enqueue_push('test','Notificaciones activadas','Recibirás avisos de pedidos e inventario de Verdélia.','ajustes','subscribe:'||sid||':'||gen_random_uuid(),sid);
  perform verdelia_private.wake_worker();return jsonb_build_object('id',sid);
 elsif action='unsubscribe' then
  update verdelia_private.push_subscriptions set active=false,updated_at=now() where id=(data->>'id')::uuid;
  return '{"ok":true}';
 elsif action='test' then
  sid:=(data->>'id')::uuid;
  if not exists(select 1 from verdelia_private.push_subscriptions where id=sid and active) then raise exception 'Primero activa las notificaciones en este dispositivo.';end if;
  if exists(select 1 from verdelia_private.push_events e join verdelia_private.push_deliveries d on d.event_id=e.id where d.subscription_id=sid and e.kind='test' and e.created_at>now()-interval '30 seconds') then raise exception 'Espera 30 segundos antes de repetir la prueba.';end if;
  perform verdelia_private.enqueue_push('test','Prueba de Verdélia','Los avisos pueden llegar aunque la app esté cerrada.','ajustes','test:'||gen_random_uuid(),sid);perform verdelia_private.wake_worker();return '{"ok":true}';
 elsif action='backup' then
  if exists(select 1 from verdelia_private.backup_runs where created_at>now()-interval '5 minutes' and status in('pending','running','completed')) then raise exception 'Ya hay un respaldo reciente o en proceso. Espera cinco minutos.';end if;
  insert into verdelia_private.backup_runs(job_key) values('manual:'||gen_random_uuid()) returning * into b;perform verdelia_private.wake_worker();return jsonb_build_object('id',b.id);
 elsif action='download' then
  select * into b from verdelia_private.backup_runs where id=(data->>'id')::uuid and status='completed';
  if not found then raise exception 'El respaldo no está disponible.';end if;
  return jsonb_build_object('path',b.object_path);
 end if;
 raise exception 'Acción desconocida.';
end $$;

-- Only the Edge Function's server credential can call this worker API.
create or replace function verdelia_private.background(action text,data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare b verdelia_private.backup_runs; result jsonb; c verdelia_private.automation_config; v jsonb;
begin
 if action='verify' then
  return to_jsonb(exists(select 1 from verdelia_private.automation_config c join vault.decrypted_secrets v on v.id=c.job_secret_id where extensions.digest(coalesce(data->>'secret',''),'sha256')=extensions.digest(v.decrypted_secret,'sha256')));
 elsif action='config' then
  select * into c from verdelia_private.automation_config;
  return jsonb_build_object('public_key',c.public_key,'private_key',(select decrypted_secret from vault.decrypted_secrets where id=c.private_key_id),'subject',(select 'mailto:'||email from verdelia_private.account));
 elsif action='init_keys' then
  perform pg_advisory_xact_lock(742839129);
  if (select public_key is null from verdelia_private.automation_config) then
   update verdelia_private.automation_config set public_key=data->>'public_key',private_key_id=vault.create_secret(data->>'private_key','verdelia_vapid_private') where id=true;
  end if;return '{"ok":true}';
 elsif action='claim_push' then
  with chosen as (select d.event_id,d.subscription_id from verdelia_private.push_deliveries d join verdelia_private.push_subscriptions s on s.id=d.subscription_id join verdelia_private.push_events e on e.id=d.event_id where s.active and e.expires_at>now() and d.status in('pending','sending') and d.attempts<5 and d.next_attempt<=now() and (d.leased_until is null or d.leased_until<now()) order by d.next_attempt limit 30 for update of d skip locked), claimed as (
   update verdelia_private.push_deliveries d set status='sending',attempts=attempts+1,lease=gen_random_uuid(),leased_until=now()+interval '2 minutes' from chosen c where d.event_id=c.event_id and d.subscription_id=c.subscription_id returning d.*)
  select coalesce(jsonb_agg(jsonb_build_object('event_id',d.event_id,'subscription_id',d.subscription_id,'lease',d.lease,'endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth),'payload',jsonb_build_object('title',e.title,'body',e.body,'route',e.route,'tag',e.id),'expires_at',e.expires_at)),'[]'::jsonb) into result from claimed d join verdelia_private.push_subscriptions s on s.id=d.subscription_id join verdelia_private.push_events e on e.id=d.event_id;
  return result;
 elsif action='ack_push' then
  update verdelia_private.push_deliveries set status=case when (data->>'ok')::boolean then 'sent' when attempts>=5 or coalesce((data->>'gone')::boolean,false) then 'failed' else 'pending' end,sent_at=case when (data->>'ok')::boolean then now() end,last_error=left(data->>'error',120),leased_until=null,next_attempt=now()+make_interval(mins=>least(60,(power(2,attempts))::integer)) where event_id=(data->>'event_id')::uuid and subscription_id=(data->>'subscription_id')::uuid and lease=(data->>'lease')::uuid;
  if found and coalesce((data->>'gone')::boolean,false) then update verdelia_private.push_subscriptions set active=false,updated_at=now() where id=(data->>'subscription_id')::uuid;end if;
  return '{"ok":true}';
 elsif action='claim_backup' then
  select * into b from verdelia_private.backup_runs where status in('pending','running') and attempts<3 and next_attempt<=now() and (leased_until is null or leased_until<now()) order by created_at limit 1 for update skip locked;
  if not found then return 'null'::jsonb;end if;
  update verdelia_private.backup_runs set status='running',attempts=attempts+1,leased_until=now()+interval '10 minutes',object_path='daily/'||b.id||'.json.gz' where id=b.id;
  v:=verdelia_private.backup_payload();
  return jsonb_build_object('id',b.id,'path','daily/'||b.id||'.json.gz','payload',v);
 elsif action='ack_backup' then
  update verdelia_private.backup_runs set status=case when (data->>'ok')::boolean then 'completed' when attempts>=3 then 'failed' else 'pending' end,completed_at=case when (data->>'ok')::boolean then now() end,leased_until=null,next_attempt=now()+interval '5 minutes',sha256=data->>'sha256',bytes=(data->>'bytes')::bigint,row_counts=data->'row_counts',error=left(data->>'error',200) where id=(data->>'id')::uuid and status='running';return '{"ok":true}';
 elsif action='expired_backups' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'path',object_path)) from verdelia_private.backup_runs where created_at<now()-interval '30 days' and status in('completed','failed') and object_path is not null),'[]'::jsonb);
 elsif action='pruned_backup' then
  update verdelia_private.backup_runs set status='deleted' where id=(data->>'id')::uuid and created_at<now()-interval '30 days';return '{"ok":true}';
 end if;raise exception 'Unknown worker action';
end $$;
create or replace function public.verdelia_automation(action text,data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select verdelia_private.automation_admin(action,data)$$;
create or replace function public.verdelia_background(action text,data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select verdelia_private.background(action,data)$$;
revoke all on function verdelia_private.wake_worker(),verdelia_private.enqueue_push(text,text,text,text,text,uuid),verdelia_private.order_notification(),verdelia_private.automation_tick(),verdelia_private.queue_daily_backup(),verdelia_private.backup_payload(),verdelia_private.automation_admin(text,jsonb),verdelia_private.background(text,jsonb),public.verdelia_automation(text,jsonb),public.verdelia_background(text,jsonb) from public,anon,authenticated;
grant execute on function public.verdelia_automation(text,jsonb),verdelia_private.automation_admin(text,jsonb) to anon,authenticated,service_role;
grant usage on schema verdelia_private to service_role;
grant execute on function public.verdelia_background(text,jsonb),verdelia_private.background(text,jsonb) to service_role;
-- Scheduled in UTC: 07:00 UTC is 02:00 in Colombia. Names are exclusive to Verdélia.
select cron.schedule('verdelia-notifications','* * * * *','select verdelia_private.automation_tick()');
select cron.schedule('verdelia-daily-backup','0 7 * * *','select verdelia_private.queue_daily_backup()');
notify pgrst,'reload schema';
commit;
