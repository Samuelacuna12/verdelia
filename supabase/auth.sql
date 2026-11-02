begin;
create table if not exists verdelia_private.account (
 id uuid primary key default gen_random_uuid(), singleton boolean not null unique default true check(singleton),username text not null unique default 'verdelia',email text not null,
 password_hash text,activation_hash text,activation_expires timestamptz,recovery_hash text,failed integer not null default 0,locked_until timestamptz,updated_at timestamptz not null default now()
);
create table if not exists verdelia_private.sessions (
 token_hash text primary key,account_id uuid not null references verdelia_private.account(id),created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '7 days'
);
alter table verdelia_private.account enable row level security;
alter table verdelia_private.sessions enable row level security;
revoke all on verdelia_private.account,verdelia_private.sessions from public,anon,authenticated;
create or replace function verdelia_private.require_admin(session_token text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 if session_token is null or length(session_token)<>64 then raise exception using errcode='42501',message='Inicia sesión para continuar.';end if;
 select account_id into uid from verdelia_private.sessions where token_hash=encode(extensions.digest(session_token,'sha256'),'hex') and expires_at>now();
 if uid is null then raise exception using errcode='42501',message='La sesión terminó. Vuelve a entrar.';end if;
 perform set_config('verdelia.actor',uid::text,true);
end $$;
create or replace function verdelia_private.login(action text,data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a verdelia_private.account;token text;recovery text;pass text;valid boolean:=false;
begin
 perform pg_advisory_xact_lock(742839128);
 select * into a from verdelia_private.account where singleton for update;
 if not found then return jsonb_build_object('error','El acceso aún no está configurado.');end if;
 if action='logout' then
  delete from verdelia_private.sessions where token_hash=encode(extensions.digest(coalesce(data->>'session',''),'sha256'),'hex');return jsonb_build_object('ok',true);
 end if;
 if action not in('activate','login','recover','change_password') then return jsonb_build_object('error','Acción inválida.');end if;
 if a.locked_until>now() and action='login' then return jsonb_build_object('error','Demasiados intentos. Espera 15 minutos antes de volver a entrar.');end if;
 if action='login' then
  valid:=lower(trim(coalesce(data->>'username','')))=a.username and a.password_hash is not null and octet_length(coalesce(data->>'password',''))<=72 and extensions.crypt(coalesce(data->>'password',''),a.password_hash)=a.password_hash;
 elsif action='activate' then
  valid:=a.password_hash is null and a.activation_expires>now() and a.activation_hash=encode(extensions.digest(coalesce(data->>'token',''),'sha256'),'hex');
 elsif action='recover' then
  valid:=a.recovery_hash is not null and a.recovery_hash=encode(extensions.digest(coalesce(data->>'token',''),'sha256'),'hex');
 elsif action='change_password' then
  perform verdelia_private.require_admin(data->>'session');
  valid:=extensions.crypt(coalesce(data->>'old_password',''),a.password_hash)=a.password_hash;
 end if;
 if not coalesce(valid,false) then
  if action='login' then update verdelia_private.account set failed=failed+1,locked_until=case when failed+1>=5 then now()+interval '15 minutes' else null end where id=a.id;end if;
  return jsonb_build_object('error',case when action='login' then 'Usuario o contraseña incorrectos.' else 'El código no es válido o ya fue utilizado.' end);
 end if;
 if action<>'login' then
  pass:=data->>'password';
  if pass is null or length(pass)<10 or octet_length(pass)>72 then return jsonb_build_object('error','Usa una contraseña de al menos 10 caracteres y hasta 72 bytes.');end if;
  recovery:=encode(extensions.gen_random_bytes(32),'hex');
  update verdelia_private.account set password_hash=extensions.crypt(pass,extensions.gen_salt('bf',12)),activation_hash=null,activation_expires=null,recovery_hash=encode(extensions.digest(recovery,'sha256'),'hex'),failed=0,locked_until=null,updated_at=now() where id=a.id;
  delete from verdelia_private.sessions where account_id=a.id;
 else update verdelia_private.account set failed=0,locked_until=null where id=a.id;
 end if;
 delete from verdelia_private.sessions where expires_at<=now();
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into verdelia_private.sessions(token_hash,account_id) values(encode(extensions.digest(token,'sha256'),'hex'),a.id);
 insert into verdelia_private.audit(action,actor,detail) values('auth_'||action,a.id,jsonb_build_object('username',a.username));
 return jsonb_build_object('session',token,'username',a.username,'email',a.email,'expires_at',now()+interval '7 days','recovery_code',recovery);
end $$;
create or replace function public.verdelia_login(action text,data jsonb) returns jsonb language sql security invoker set search_path='' as $$ select verdelia_private.login(action,data) $$;
revoke all on function public.verdelia_login(text,jsonb),verdelia_private.login(text,jsonb),verdelia_private.require_admin(text) from public,anon,authenticated;
grant execute on function public.verdelia_login(text,jsonb),verdelia_private.login(text,jsonb) to anon,authenticated;
commit;
