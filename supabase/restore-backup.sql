-- Recovery aid for the database owner. Never callable from the public application.
-- Loads a copy into a NEW isolated schema for inspection, without overwriting live data.
create or replace function verdelia_private.restore_backup_to_schema(payload jsonb,target_schema text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare t text; fk record; definition text; counts jsonb:='{}'; n bigint; table_list text[]:=array['settings','alert_preferences','products','recipes','sales','orders','stock_moves','purchases','lots','cash_moves','closings','audit','requests'];
begin
 if target_schema!~'^verdelia_restore_[a-z0-9_]{1,40}$' or exists(select 1 from pg_namespace where nspname=target_schema) then raise exception 'Use a new verdelia_restore_ schema name';end if;
 if payload->>'format'<>'verdelia-business-backup' or (payload->>'version')::integer<>1 or payload->'tables' is null then raise exception 'Invalid backup format';end if;
 execute format('create schema %I',target_schema);
 execute format('revoke all on schema %I from public,anon,authenticated,service_role',target_schema);
 foreach t in array table_list loop
  if jsonb_typeof(payload->'tables'->t)<>'array' or payload->'tables'->t is null then raise exception 'Missing backup table %',t;end if;
  execute format('create table %I.%I (like verdelia_private.%I including all)',target_schema,t,t);
  execute format('alter table %I.%I enable row level security',target_schema,t);
  execute format('revoke all on %I.%I from public,anon,authenticated,service_role',target_schema,t);
  execute format('insert into %I.%I overriding system value select * from jsonb_populate_recordset(null::verdelia_private.%I,$1)',target_schema,t,t) using payload->'tables'->t;
  get diagnostics n=row_count;
  if n<>(payload->'row_counts'->>t)::bigint then raise exception 'Row count mismatch for %',t;end if;
  counts:=counts||jsonb_build_object(t,n);
 end loop;
 -- LIKE copies checks/uniqueness, but PostgreSQL requires foreign keys separately.
 for fk in select c.conname,c.conrelid::regclass::text as relation,cl.relname,pg_get_constraintdef(c.oid) definition from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace ns on ns.oid=cl.relnamespace where ns.nspname='verdelia_private' and c.contype='f' and cl.relname=any(table_list) loop
  definition:=replace(fk.definition,'verdelia_private.',quote_ident(target_schema)||'.');
  execute format('alter table %I.%I add constraint %I %s',target_schema,fk.relname,fk.conname,definition);
 end loop;
 -- Identity counters resume beyond the restored identifiers.
 foreach t in array array['sales','orders','audit'] loop
  execute format('select coalesce(max(%I),0) from %I.%I',case when t='audit' then 'id' else 'number' end,target_schema,t) into n;
  perform setval(pg_get_serial_sequence(format('%I.%I',target_schema,t),case when t='audit' then 'id' else 'number' end),greatest(n,1),n>0);
 end loop;
 return counts;
end $$;
revoke all on function verdelia_private.restore_backup_to_schema(jsonb,text) from public,anon,authenticated,service_role;
