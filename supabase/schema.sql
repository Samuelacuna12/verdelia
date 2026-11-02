-- Verdélia: isolated schema. No existing application objects are modified.
begin;
create schema if not exists verdelia_private;
revoke all on schema verdelia_private from public;
alter default privileges in schema verdelia_private revoke execute on functions from public;
create table if not exists verdelia_private.admins (email text primary key check(email=lower(email)), created_at timestamptz not null default now());
create table if not exists verdelia_private.settings (
 id boolean primary key default true check(id), name text not null default 'Verdélia', whatsapp text not null default '573115565525',
 address text not null default '', pound_grams numeric not null default 500 check(pound_grams between 400 and 600),
 delivery_enabled boolean not null default true, pickup_enabled boolean not null default true, delivery_fee numeric(14,2) not null default 0 check(delivery_fee>=0),
 catalog_enabled boolean not null default true, closing_time time not null default '20:00', notes text not null default '', updated_at timestamptz not null default now()
);
insert into verdelia_private.settings(id) values(true) on conflict do nothing;
create table if not exists verdelia_private.products (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 100), sku text not null default '',
 category text not null default 'Frutas', kind text not null default 'product' check(kind in('product','combo')), unit text not null default 'kg' check(unit in('kg','und','paquete','botella','bandeja','litro')),
 price numeric(14,2) not null check(price>=0 and price<1000000000), avg_cost numeric(14,4) not null default 0 check(avg_cost>=0 and avg_cost<1000000000),
 stock numeric(16,4) not null default 0 check(stock>=0 and stock<1000000000), reserved numeric(16,4) not null default 0 check(reserved>=0 and reserved<=stock),
 minimum numeric(16,4) not null default 0 check(minimum>=0 and minimum<1000000000), target numeric(16,4) not null default 0 check(target>=minimum and target<1000000000),
 description text not null default '', image_url text not null default '', active boolean not null default true, published boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists verdelia_sku_unique on verdelia_private.products(lower(sku)) where sku<>'';
create table if not exists verdelia_private.recipes (
 combo_id uuid not null references verdelia_private.products(id), product_id uuid not null references verdelia_private.products(id),
 quantity numeric(16,4) not null check(quantity>0 and quantity<1000000000), primary key(combo_id,product_id), check(combo_id<>product_id)
);
create index if not exists verdelia_recipe_product on verdelia_private.recipes(product_id);
create table if not exists verdelia_private.sales (
 id uuid primary key default gen_random_uuid(), number bigint generated always as identity unique,
 type text not null default 'sale' check(type in('sale','refund')), original_id uuid references verdelia_private.sales(id),
 created_at timestamptz not null default now(), channel text not null check(channel in('local','internet')), customer text not null default '',
 lines jsonb not null, needs jsonb not null, subtotal numeric(14,2) not null, discount numeric(14,2) not null default 0,
 delivery numeric(14,2) not null default 0, total numeric(14,2) not null, cost numeric(14,2) not null,
 method text not null check(method in('efectivo','transferencia','tarjeta')), cash_received numeric(14,2),
 status text not null default 'paid' check(status in('paid','refunded')), note text not null default '', actor uuid
);
create unique index if not exists verdelia_one_refund on verdelia_private.sales(original_id) where type='refund';
create index if not exists verdelia_sales_date on verdelia_private.sales(created_at desc);
create table if not exists verdelia_private.orders (
 id uuid primary key default gen_random_uuid(), number bigint generated always as identity unique,
 request_id uuid not null unique, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 customer text not null, phone text not null, address text not null default '', delivery_type text not null check(delivery_type in('pickup','delivery')),
 status text not null default 'pending' check(status in('pending','confirmed','completed','cancelled')),
 quote jsonb not null, note text not null default '', sale_id uuid references verdelia_private.sales(id), confirmed_at timestamptz, completed_at timestamptz
);
create index if not exists verdelia_orders_date on verdelia_private.orders(created_at desc);
create index if not exists verdelia_orders_phone_date on verdelia_private.orders(phone,created_at desc);
create table if not exists verdelia_private.stock_moves (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), product_id uuid not null references verdelia_private.products(id),
 quantity numeric(16,4) not null, unit_cost numeric(14,4) not null check(unit_cost>=0),
 reason text not null check(reason in('opening','purchase','sale','refund','loss','adjustment')), note text not null default '', reference_id uuid, actor uuid
);
create index if not exists verdelia_moves_product_date on verdelia_private.stock_moves(product_id,created_at desc);
create table if not exists verdelia_private.purchases (
 id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),supplier text not null default '',
 lines jsonb not null,total numeric(14,2) not null check(total>0),method text not null check(method in('efectivo','transferencia','tarjeta')),note text not null default '',actor uuid
);
create table if not exists verdelia_private.lots (
 id uuid primary key default gen_random_uuid(),product_id uuid not null references verdelia_private.products(id),purchase_id uuid references verdelia_private.purchases(id),
 received_at timestamptz not null default now(),expiry date,quantity numeric(16,4) not null check(quantity>0 and quantity<1000000000),remaining numeric(16,4) not null check(remaining>=0 and remaining<=quantity)
);
create index if not exists verdelia_lots_expiry on verdelia_private.lots(expiry) where remaining>0;
create table if not exists verdelia_private.cash_moves (
 id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),kind text not null check(kind in('sale','refund','purchase','expense','deposit','withdrawal')),
 amount numeric(14,2) not null check(amount<>0),method text not null check(method in('efectivo','transferencia','tarjeta')),category text not null default '',
 note text not null default '',reference_id uuid,actor uuid
);
create index if not exists verdelia_cash_date on verdelia_private.cash_moves(created_at desc);
create table if not exists verdelia_private.closings (
 id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),business_date date not null unique,
 expected numeric(14,2) not null,counted numeric(14,2) not null check(counted>=0 and counted<1000000000000),difference numeric(14,2) not null,note text not null default '',actor uuid
);
create table if not exists verdelia_private.audit (
 id bigint generated always as identity primary key,created_at timestamptz not null default now(),action text not null,reference_id uuid,detail jsonb not null default '{}',actor uuid
);
create table if not exists verdelia_private.requests (id uuid primary key,action text not null,payload jsonb not null,result jsonb not null,actor uuid,created_at timestamptz not null default now());
create table if not exists verdelia_private.alert_preferences (id boolean primary key default true check(id),stock boolean not null default true,expiry boolean not null default true,pending_orders boolean not null default true,expiry_days integer not null default 3 check(expiry_days between 0 and 30));
insert into verdelia_private.alert_preferences(id) values(true) on conflict do nothing;
-- RLS on private tables as defense in depth; no table privileges to API roles.
do $$ declare t text; begin for t in select tablename from pg_tables where schemaname='verdelia_private' loop execute format('alter table verdelia_private.%I enable row level security',t); end loop; end $$;
revoke all on all tables in schema verdelia_private from public,anon,authenticated;
revoke all on all sequences in schema verdelia_private from public,anon,authenticated;

create or replace function verdelia_private.catalog() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('settings',(select jsonb_build_object('name',s.name,'whatsapp',s.whatsapp,'address',s.address,'pound_grams',s.pound_grams,'delivery_enabled',s.delivery_enabled,'pickup_enabled',s.pickup_enabled,'delivery_fee',s.delivery_fee,'notes',s.notes,'catalog_enabled',s.catalog_enabled) from verdelia_private.settings s),
 'products',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',p.category,'kind',p.kind,'unit',p.unit,'price',p.price,'description',p.description,'image_url',p.image_url,'available',case when p.kind='product' then p.stock-p.reserved else coalesce((select min(case when i.active then floor((i.stock-i.reserved)/r.quantity) else 0 end) from verdelia_private.recipes r join verdelia_private.products i on i.id=r.product_id where r.combo_id=p.id),0) end) order by p.name) from verdelia_private.products p where p.active and p.published and (select catalog_enabled from verdelia_private.settings)), '[]'::jsonb),
 'server_time',now());
$$;

-- Canonical units, prices and ingredient snapshots are computed on the server.
create or replace function verdelia_private.quote(input jsonb,public_only boolean default false) returns jsonb language plpgsql set search_path='' as $$
declare item jsonb; p verdelia_private.products; r record; q numeric; factor numeric; qty numeric; price numeric; cost numeric; sub numeric:=0; totalcost numeric:=0;
 lines jsonb:='[]'; needs jsonb:='{}'; pound numeric; un text; lineingredients jsonb; oldq numeric;
begin
 if input is null or jsonb_typeof(input)<>'array' or jsonb_array_length(input)<1 or jsonb_array_length(input)>100 then raise exception 'Añade entre 1 y 100 productos.';end if;
 select pound_grams/1000 into pound from verdelia_private.settings;
 for item in select value from jsonb_array_elements(input) loop
  select * into p from verdelia_private.products where id=(item->>'id')::uuid;
  if not found or not p.active or(public_only and not p.published) then raise exception 'Un producto ya no está disponible.'; end if;
  q:=(item->>'quantity')::numeric; un:=coalesce(item->>'unit',p.unit);factor:=1;
  if q is null or q<=0 or q>10000 or q::text in('NaN','Infinity','-Infinity') then raise exception 'Cantidad inválida.';end if;
  if p.unit='kg' then factor:=case un when 'kg' then 1 when 'lb' then pound when 'g' then 0.001 else null end;
  elsif un<>p.unit then raise exception 'Unidad incompatible con %.',p.name;
  elsif p.unit not in('litro') and q<>trunc(q) then raise exception '% debe venderse en unidades completas.',p.name;end if;
  if factor is null then raise exception 'Medida no válida.';end if;
  qty:=round(q*factor,4);if qty<=0 then raise exception 'Cantidad demasiado pequeña.';end if;
  price:=round(p.price*factor,4);cost:=0;lineingredients:='[]';
  if p.kind='combo' then
   cost:=p.avg_cost*qty;
   if not exists(select 1 from verdelia_private.recipes where combo_id=p.id) then raise exception 'El combo no tiene ingredientes.';end if;
   for r in select z.product_id,z.quantity,i.avg_cost,i.active from verdelia_private.recipes z join verdelia_private.products i on i.id=z.product_id where z.combo_id=p.id loop
    if not r.active then raise exception 'Un ingrediente del combo está inactivo.';end if;
    oldq:=coalesce((needs->>r.product_id::text)::numeric,0);
    needs:=jsonb_set(needs,array[r.product_id::text],to_jsonb(oldq+r.quantity*qty));
    cost:=cost+r.quantity*qty*r.avg_cost;
    lineingredients:=lineingredients||jsonb_build_object('id',r.product_id,'quantity',r.quantity*qty);
   end loop;
  else
   needs:=jsonb_set(needs,array[p.id::text],to_jsonb(coalesce((needs->>p.id::text)::numeric,0)+qty));cost:=p.avg_cost*qty;
   lineingredients:=jsonb_build_array(jsonb_build_object('id',p.id,'quantity',qty));
  end if;
  lines:=lines||jsonb_build_object('id',p.id,'name',p.name,'kind',p.kind,'quantity',q,'unit',un,'base_quantity',qty,'base_unit',p.unit,'unit_price',price,'subtotal',round(p.price*qty,2),'cost',round(cost,2),'ingredients',lineingredients,'packaging_cost',case when p.kind='combo' then round(p.avg_cost*qty,2) else 0 end);
  sub:=sub+round(p.price*qty,2);totalcost:=totalcost+round(cost,2);
 end loop;
 return jsonb_build_object('lines',lines,'needs',needs,'subtotal',sub,'cost',totalcost);
end $$;

create or replace function verdelia_private.move_stock(pid uuid,delta numeric,why text,memo text,ref uuid) returns void language plpgsql set search_path='' as $$
declare p verdelia_private.products; remaining_qty numeric; l record; take_qty numeric;
begin
 select * into p from verdelia_private.products where id=pid for update;
 if not found or p.kind<>'product' then raise exception 'Producto de inventario no válido.';end if;
 if p.stock+delta<p.reserved then raise exception 'Existencias insuficientes de %. Disponible: % %.',p.name,p.stock-p.reserved,p.unit;end if;
 update verdelia_private.products set stock=round(stock+delta,4),updated_at=now() where id=pid;
 insert into verdelia_private.stock_moves(product_id,quantity,unit_cost,reason,note,reference_id,actor) values(pid,delta,p.avg_cost,why,memo,ref,nullif(current_setting('verdelia.actor',true),'')::uuid);
 if delta<0 then
  remaining_qty:=-delta;
  for l in select id,remaining from verdelia_private.lots where product_id=pid and remaining>0 order by expiry nulls last,received_at for update loop
   take_qty:=least(l.remaining,remaining_qty);update verdelia_private.lots set remaining=remaining-take_qty where id=l.id;remaining_qty:=remaining_qty-take_qty;exit when remaining_qty<=0;
  end loop;
 elsif delta>0 and why<>'purchase' then
  insert into verdelia_private.lots(product_id,quantity,remaining) values(pid,delta,delta);
 end if;
end $$;

create or replace function verdelia_private.commit_sale(quote_data jsonb,details jsonb) returns jsonb language plpgsql set search_path='' as $$
declare n record; s verdelia_private.sales; cost numeric:=0; disc numeric:=coalesce((details->>'discount')::numeric,0);fee numeric:=coalesce((details->>'delivery')::numeric,0);sub numeric:=(quote_data->>'subtotal')::numeric;method text:=details->>'method';line jsonb;lines jsonb:='[]';lc numeric;ing jsonb;received numeric;ingredients jsonb;uc numeric;
begin
 if method not in('efectivo','transferencia','tarjeta') or method is null then raise exception 'Selecciona cómo recibiste el pago.';end if;
 if disc<0 or disc>sub or fee<0 or fee>1000000 then raise exception 'Descuento o domicilio inválido.';end if;
 for line in select value from jsonb_array_elements(quote_data->'lines') loop
  lc:=coalesce((line->>'packaging_cost')::numeric,0);ingredients:='[]';
  for ing in select value from jsonb_array_elements(line->'ingredients') loop
   uc:=coalesce((select avg_cost from verdelia_private.products where id=(ing->>'id')::uuid),0);lc:=lc+uc*(ing->>'quantity')::numeric;ingredients:=ingredients||(ing||jsonb_build_object('unit_cost',uc));
  end loop;
  lines:=lines||(line||jsonb_build_object('cost',round(lc,2),'ingredients',ingredients));cost:=cost+round(lc,2);
 end loop;
 received:=nullif(details->>'cash_received','')::numeric;
 if method='efectivo' and received is not null and received<sub-disc+fee then raise exception 'El dinero recibido no cubre el total.';end if;
 insert into verdelia_private.sales(channel,customer,lines,needs,subtotal,discount,delivery,total,cost,method,cash_received,note,actor)
 values(coalesce(details->>'channel','local'),left(coalesce(details->>'customer',''),100),lines,quote_data->'needs',sub,disc,fee,sub-disc+fee,cost,method,received,left(coalesce(details->>'note',''),500),nullif(current_setting('verdelia.actor',true),'')::uuid) returning * into s;
 for n in select key,value from jsonb_each_text(quote_data->'needs') order by key loop
  perform verdelia_private.move_stock(n.key::uuid,-n.value::numeric,'sale','Venta VD-'||s.number,s.id);
 end loop;
 if s.total>0 then insert into verdelia_private.cash_moves(kind,amount,method,category,note,reference_id,actor) values('sale',s.total,s.method,'Venta','VD-'||s.number,s.id,nullif(current_setting('verdelia.actor',true),'')::uuid);end if;
 return to_jsonb(s);
end $$;

create or replace function verdelia_private.public_quote(q jsonb) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('lines',coalesce((select jsonb_agg(x-'cost'-'ingredients'-'packaging_cost') from jsonb_array_elements(q->'lines') x),'[]'::jsonb),'subtotal',q->'subtotal','delivery',q->'delivery','total',q->'total');
$$;

create or replace function verdelia_private.public_order(data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o verdelia_private.orders; q jsonb; cfg verdelia_private.settings; n record; ph text; rid uuid; fee numeric;
begin
 perform pg_advisory_xact_lock(742839127);
 rid:=(data->>'request_id')::uuid;if rid is null then raise exception 'Falta el identificador del pedido.';end if;
 select * into o from verdelia_private.orders where request_id=rid;
 if found then return jsonb_build_object('id',o.id,'number',o.number,'quote',verdelia_private.public_quote(o.quote),'created_at',o.created_at);end if;
 select * into cfg from verdelia_private.settings;
 if not cfg.catalog_enabled then raise exception 'El catálogo está temporalmente cerrado.';end if;
 ph:=regexp_replace(coalesce(data->>'phone',''),'[^0-9]','','g');
 if length(ph)<7 or length(ph)>15 or length(trim(coalesce(data->>'customer','')))<2 or length(data->>'customer')>100 then raise exception 'Revisa tu nombre y teléfono.';end if;
 if coalesce(data->>'website','')<>'' then raise exception 'No se pudo enviar el pedido.';end if;
 if(data->>'delivery_type') not in('pickup','delivery') or (data->>'delivery_type') is null then raise exception 'Selecciona la entrega.';end if;
 if(data->>'delivery_type')='delivery' and(not cfg.delivery_enabled or length(trim(coalesce(data->>'address','')))<5) then raise exception 'Revisa la dirección o elige recogida.';end if;
 if(data->>'delivery_type')='pickup' and not cfg.pickup_enabled then raise exception 'La recogida no está disponible.';end if;
 if(select count(*) from verdelia_private.orders where phone=ph and created_at>now()-interval '1 hour')>=5 or(select count(*) from verdelia_private.orders where created_at>now()-interval '1 hour')>=100 then raise exception 'Se alcanzó el límite temporal de pedidos. Contacta a Verdélia por WhatsApp.';end if;
 q:=verdelia_private.quote(data->'lines',true);
 for n in select key,value from jsonb_each_text(q->'needs') loop
  if(select stock-reserved from verdelia_private.products where id=n.key::uuid)<n.value::numeric then raise exception 'Una cantidad supera la disponibilidad. Actualiza tu carrito.';end if;
 end loop;
 fee:=case when(data->>'delivery_type')='delivery' then cfg.delivery_fee else 0 end;
 q:=q||jsonb_build_object('delivery',fee,'total',(q->>'subtotal')::numeric+fee);
 insert into verdelia_private.orders(request_id,customer,phone,address,delivery_type,quote,note) values(rid,trim(data->>'customer'),ph,left(coalesce(data->>'address',''),250),data->>'delivery_type',q,left(coalesce(data->>'note',''),500)) returning * into o;
 insert into verdelia_private.audit(action,reference_id,detail) values('order_created',o.id,jsonb_build_object('number',o.number));
 return jsonb_build_object('id',o.id,'number',o.number,'quote',verdelia_private.public_quote(o.quote),'created_at',o.created_at);
end $$;

create or replace function verdelia_private.admin(action text,data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare p verdelia_private.products; o verdelia_private.orders; s verdelia_private.sales; orig verdelia_private.sales; req verdelia_private.requests;
 result jsonb; rid uuid; q jsonb; n record; item jsonb; lines jsonb; id uuid; qty numeric; total numeric; cost numeric; expected numeric; counted numeric; start_at timestamptz; end_at timestamptz; memo text; available numeric; received_cost numeric; old_stock numeric; linecost numeric; old_product jsonb; base_unit text; measure text; scale numeric; new_cost numeric; new_price numeric;
begin
 perform verdelia_private.require_admin(data->>'session');data:=data-'session';
 if action in('snapshot','report') then
  start_at:=coalesce(nullif(data->>'from','')::date,((now() at time zone 'America/Bogota')::date-30))::timestamp at time zone 'America/Bogota';
  end_at:=(coalesce(nullif(data->>'to','')::date,(now() at time zone 'America/Bogota')::date)+1)::timestamp at time zone 'America/Bogota';
  if end_at<=start_at or end_at-start_at>interval '367 days' then raise exception 'Selecciona un rango de hasta un año.';end if;
  result:=jsonb_build_object('account',(select jsonb_build_object('username',a.username,'email',a.email) from verdelia_private.account a),'settings',(select to_jsonb(x) from verdelia_private.settings x),'preferences',(select to_jsonb(x) from verdelia_private.alert_preferences x),
   'products',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('available',case when x.kind='product' then x.stock-x.reserved else coalesce((select min(case when z.active then floor((z.stock-z.reserved)/r.quantity) else 0 end) from verdelia_private.recipes r join verdelia_private.products z on z.id=r.product_id where r.combo_id=x.id),0) end,'recipe',coalesce((select jsonb_agg(to_jsonb(r)) from verdelia_private.recipes r where r.combo_id=x.id),'[]'::jsonb)) order by x.name) from verdelia_private.products x),'[]'::jsonb),
   'sales',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from verdelia_private.sales x where x.created_at>=start_at and x.created_at<end_at),'[]'::jsonb),
   'cash',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from verdelia_private.cash_moves x where x.created_at>=start_at and x.created_at<end_at),'[]'::jsonb),
   'balances',coalesce((select jsonb_object_agg(method,amount) from(select method,sum(amount) amount from verdelia_private.cash_moves group by method)t),'{}'::jsonb),
   'orders',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from verdelia_private.orders where status in('pending','confirmed') or (created_at>=start_at and created_at<end_at) order by created_at desc)x),'[]'::jsonb),
   'stock_moves',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from verdelia_private.stock_moves where created_at>=start_at and created_at<end_at order by created_at desc)x),'[]'::jsonb),
   'lots',coalesce((select jsonb_agg(to_jsonb(x)) from verdelia_private.lots x where remaining>0 and expiry is not null),'[]'::jsonb),
   'purchases',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from verdelia_private.purchases x where created_at>=start_at and created_at<end_at),'[]'::jsonb),
   'closings',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from verdelia_private.closings order by created_at desc limit 366)x),'[]'::jsonb),
   'audit',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from verdelia_private.audit order by created_at desc limit 200)x),'[]'::jsonb),'server_time',now(),'range',jsonb_build_object('from',start_at,'to',end_at));
  return result;
 end if;
 perform pg_advisory_xact_lock(742839127);
 rid:=(data->>'request_id')::uuid;if rid is null then raise exception 'Falta el identificador de la operación.';end if;
 select * into req from verdelia_private.requests r where r.id=rid;
 if found then if req.action<>action or req.payload<>data or req.actor is distinct from nullif(current_setting('verdelia.actor',true),'')::uuid then raise exception 'Identificador de operación repetido.';end if;return req.result;end if;
 memo:=left(coalesce(data->>'note',''),500);
 if action='save_product' then
  id:=nullif(data->>'id','')::uuid;
  if id is not null then select * into p from verdelia_private.products where products.id=id for update;if not found then raise exception 'Producto no encontrado.';end if;end if;
  if id is not null and data ? 'expected_updated_at' and (data->>'expected_updated_at')::timestamptz is distinct from p.updated_at then raise exception 'Este producto cambió mientras lo editabas. Cierra el formulario, actualiza la página y vuelve a abrirlo.';end if;
  old_product:=case when id is not null then to_jsonb(p) else null end;
  base_unit:=coalesce(nullif(data->>'unit',''),case when id is not null then p.unit else 'kg' end);
  if id is not null and coalesce(data->>'kind',p.kind)<>p.kind then raise exception 'Crea otra presentación para convertir un producto en receta.';end if;
  if id is not null and base_unit<>p.unit and (p.kind='combo' or exists(select 1 from verdelia_private.stock_moves where product_id=id and reason<>'opening') or exists(select 1 from verdelia_private.recipes where product_id=id) or exists(select 1 from verdelia_private.orders where quote->'needs' ? id::text)) then
   raise exception 'Este producto ya tiene movimientos o recetas. Conserva su medida base; puedes cambiar la medida del costo y precio, o crear otra presentación.';
  end if;
  measure:=coalesce(data->>'cost_unit',base_unit);
  scale:=case when base_unit='kg' and measure='lb' then (select pound_grams/1000 from verdelia_private.settings) when base_unit='kg' and measure='g' then 0.001 when measure=base_unit then 1 else null end;
  if scale is null then raise exception 'Medida de costo inválida.';end if;
  new_cost:=coalesce((data->>'cost')::numeric,case when id is not null then p.avg_cost else 0 end)/scale;
  measure:=coalesce(data->>'price_unit',base_unit);
  scale:=case when base_unit='kg' and measure='lb' then (select pound_grams/1000 from verdelia_private.settings) when base_unit='kg' and measure='g' then 0.001 when measure=base_unit then 1 else null end;
  if scale is null then raise exception 'Medida de precio inválida.';end if;
  new_price:=(data->>'price')::numeric/scale;
  if new_cost::text='NaN' or new_price::text='NaN' then raise exception 'Costo o precio inválido.';end if;
  if id is not null and p.kind='product' and (round(new_cost,4)<>p.avg_cost or base_unit<>p.unit or (data ? 'stock_count' and (data->>'stock_count')::numeric<>p.stock)) and length(trim(memo))<3 then raise exception 'Escribe el motivo de la corrección de costo, medida o existencias.';end if;
  if length(coalesce(data->>'description',''))>1000 or length(coalesce(data->>'image_url',''))>1000 then raise exception 'Descripción o imagen demasiado larga.';end if;
  if coalesce(data->>'image_url','')<>'' and(data->>'image_url')!~'^https://' then raise exception 'La imagen debe usar un enlace HTTPS.';end if;
  if id is null then
   insert into verdelia_private.products(name,sku,category,kind,unit,price,avg_cost,minimum,target,description,image_url,active,published)
   values(trim(data->>'name'),trim(coalesce(data->>'sku','')),coalesce(data->>'category','Frutas'),coalesce(data->>'kind','product'),case when(data->>'kind')='combo' then 'und' else coalesce(data->>'unit','kg') end,new_price,new_cost,coalesce((data->>'minimum')::numeric,0),coalesce((data->>'target')::numeric,0),coalesce(data->>'description',''),coalesce(data->>'image_url',''),true,coalesce((data->>'published')::boolean,false)) returning * into p;id:=p.id;
   qty:=coalesce((data->>'opening_stock')::numeric,0);if qty<0 or qty>1000000 then raise exception 'Existencias iniciales inválidas.';end if;
   if qty>0 and p.kind='product' then perform verdelia_private.move_stock(p.id,qty,'opening','Inventario inicial',null);end if;
  else
   update verdelia_private.products set name=trim(data->>'name'),sku=trim(coalesce(data->>'sku','')),category=coalesce(data->>'category',p.category),price=new_price,unit=base_unit,
   avg_cost=new_cost,minimum=coalesce((data->>'minimum')::numeric,p.minimum),target=coalesce((data->>'target')::numeric,p.target),description=coalesce(data->>'description',p.description),image_url=coalesce(data->>'image_url',p.image_url),published=coalesce((data->>'published')::boolean,p.published),active=coalesce((data->>'active')::boolean,p.active),updated_at=now() where products.id=id returning * into p;
  end if;
  if old_product is not null and p.kind='product' then
   if data ? 'stock_count' then
    qty:=(data->>'stock_count')::numeric;
    if qty is null or qty<0 or qty>1000000 or qty::text='NaN' then raise exception 'Existencias inválidas.';end if;
    if qty<>p.stock then perform verdelia_private.move_stock(p.id,qty-p.stock,'adjustment',memo,null);end if;
   end if;
   if p.avg_cost<>(old_product->>'avg_cost')::numeric or p.unit<>old_product->>'unit' then
    insert into verdelia_private.audit(action,reference_id,detail,actor) values('product_correction',p.id,jsonb_build_object('note',memo,'old_cost',old_product->'avg_cost','new_cost',p.avg_cost,'old_unit',old_product->'unit','new_unit',p.unit,'stock_value_delta',round(p.stock*(p.avg_cost-(old_product->>'avg_cost')::numeric),2)),nullif(current_setting('verdelia.actor',true),'')::uuid);
   end if;
  end if;
  if p.kind='combo' then
   if (data->'recipe') is null or jsonb_typeof(data->'recipe')<>'array' or jsonb_array_length(data->'recipe')<1 then raise exception 'Añade ingredientes al combo.';end if;
   delete from verdelia_private.recipes where combo_id=p.id;
   for item in select value from jsonb_array_elements(data->'recipe') loop
    if not exists(select 1 from verdelia_private.products where products.id=(item->>'id')::uuid and kind='product' and active) then raise exception 'Ingrediente no válido.';end if;
    insert into verdelia_private.recipes(combo_id,product_id,quantity) values(p.id,(item->>'id')::uuid,(item->>'quantity')::numeric);
   end loop;
  end if;
  result:=to_jsonb(p);
 elsif action='sale' then
  q:=verdelia_private.quote(data->'lines');result:=verdelia_private.commit_sale(q,data);
 elsif action='receive' then
  if (data->'lines') is null or jsonb_typeof(data->'lines')<>'array' or jsonb_array_length(data->'lines')<1 then raise exception 'Añade productos a la compra.';end if;
  total:=0;lines:='[]';id:=gen_random_uuid();
  for item in select value from jsonb_array_elements(data->'lines') loop
   select * into p from verdelia_private.products where products.id=(item->>'id')::uuid for update;
   if not found or p.kind<>'product' then raise exception 'Producto no válido para compra.';end if;
   qty:=(item->>'quantity')::numeric;received_cost:=(item->>'unit_cost')::numeric;
   if qty is null or qty<=0 or qty>1000000 or received_cost is null or received_cost<0 or received_cost>100000000 or qty::text='NaN' or received_cost::text='NaN' then raise exception 'Revisa cantidad y costo de compra.';end if;
   update verdelia_private.products set avg_cost=round((stock*avg_cost+qty*received_cost)/(stock+qty),4) where products.id=p.id;
   perform verdelia_private.move_stock(p.id,qty,'purchase',left(coalesce(data->>'supplier',''),100),id);
   -- Record the actual inbound cost; valuation remains weighted average.
   update verdelia_private.stock_moves set unit_cost=received_cost where reference_id=id and product_id=p.id and reason='purchase';
   lines:=lines||jsonb_build_object('id',p.id,'name',p.name,'quantity',qty,'unit',p.unit,'unit_cost',received_cost,'expiry',item->>'expiry');total:=total+round(qty*received_cost,2);
  end loop;
  if total<=0 then raise exception 'La compra debe tener un costo mayor a cero.';end if;
  insert into verdelia_private.purchases(id,supplier,lines,total,method,note,actor) values(id,left(coalesce(data->>'supplier',''),150),lines,total,data->>'method',memo,nullif(current_setting('verdelia.actor',true),'')::uuid);
  for item in select value from jsonb_array_elements(lines) loop insert into verdelia_private.lots(product_id,purchase_id,expiry,quantity,remaining) values((item->>'id')::uuid,id,nullif(item->>'expiry','')::date,(item->>'quantity')::numeric,(item->>'quantity')::numeric);end loop;
  insert into verdelia_private.cash_moves(kind,amount,method,category,note,reference_id,actor) values('purchase',-total,data->>'method','Compra',coalesce(data->>'supplier',''),id,nullif(current_setting('verdelia.actor',true),'')::uuid);
  result:=jsonb_build_object('id',id,'total',total);
 elsif action='adjust_stock' then
  if length(trim(memo))<3 then raise exception 'Escribe el motivo del ajuste.';end if;
  qty:=(data->>'quantity')::numeric;if qty is null or qty=0 or abs(qty)>1000000 or qty::text='NaN' then raise exception 'Cantidad inválida.';end if;
  if(data->>'reason')='loss' and qty>0 then raise exception 'La pérdida debe descontar existencias.';end if;
  perform verdelia_private.move_stock((data->>'id')::uuid,qty,case when(data->>'reason')='loss' then 'loss' else 'adjustment' end,memo,null);result:=jsonb_build_object('ok',true);
 elsif action='cash' then
  total:=(data->>'amount')::numeric;
  if total is null or total<=0 or total>1000000000 or total::text='NaN' or length(trim(memo))<3 then raise exception 'Escribe un valor positivo y el concepto.';end if;
  if(data->>'kind') not in('expense','deposit','withdrawal') or(data->>'kind') is null then raise exception 'Tipo de movimiento inválido.';end if;
  insert into verdelia_private.cash_moves(kind,amount,method,category,note,actor) values(data->>'kind',case when(data->>'kind')='deposit' then total else -total end,data->>'method',left(coalesce(data->>'category','Otros'),100),memo,nullif(current_setting('verdelia.actor',true),'')::uuid) returning jsonb_build_object('id',cash_moves.id) into result;
 elsif action='close_cash' then
  counted:=(data->>'counted')::numeric;if counted is null or counted<0 or counted::text='NaN' then raise exception 'Escribe el efectivo contado.';end if;
  select coalesce(sum(amount),0) into expected from verdelia_private.cash_moves where method='efectivo';
  insert into verdelia_private.closings(business_date,expected,counted,difference,note,actor) values((now() at time zone 'America/Bogota')::date,expected,counted,counted-expected,memo,nullif(current_setting('verdelia.actor',true),'')::uuid) returning to_jsonb(closings.*) into result;
 elsif action='confirm_order' then
  select * into o from verdelia_private.orders where orders.id=(data->>'id')::uuid for update;
  if not found or o.status<>'pending' then raise exception 'El pedido ya cambió de estado. Actualiza la lista.';end if;
  for n in select key,value from jsonb_each_text(o.quote->'needs') order by key loop
   update verdelia_private.products set reserved=reserved+n.value::numeric where products.id=n.key::uuid and stock-reserved>=n.value::numeric and active;
   if not found then raise exception 'No hay existencias suficientes para confirmar este pedido.';end if;
  end loop;
  update verdelia_private.orders set status='confirmed',confirmed_at=now(),updated_at=now() where orders.id=o.id returning to_jsonb(orders.*) into result;
 elsif action='cancel_order' then
  select * into o from verdelia_private.orders where orders.id=(data->>'id')::uuid for update;
  if not found or o.status not in('pending','confirmed') then raise exception 'Solo se cancelan pedidos pendientes o confirmados.';end if;
  if length(trim(memo))<3 then raise exception 'Indica el motivo de cancelación.';end if;
  if o.status='confirmed' then for n in select key,value from jsonb_each_text(o.quote->'needs') loop update verdelia_private.products set reserved=reserved-n.value::numeric where products.id=n.key::uuid;end loop;end if;
  update verdelia_private.orders set status='cancelled',note=note||E'\nCancelación: '||memo,updated_at=now() where orders.id=o.id returning to_jsonb(orders.*) into result;
 elsif action='complete_order' then
  select * into o from verdelia_private.orders where orders.id=(data->>'id')::uuid for update;
  if not found or o.status<>'confirmed' then raise exception 'Primero confirma el pedido y sus existencias.';end if;
  for n in select key,value from jsonb_each_text(o.quote->'needs') loop update verdelia_private.products set reserved=reserved-n.value::numeric where products.id=n.key::uuid;end loop;
  result:=verdelia_private.commit_sale(o.quote,data||jsonb_build_object('channel','internet','customer',o.customer,'delivery',o.quote->'delivery','discount',0,'note','Pedido #P-'||o.number));
  update verdelia_private.orders set status='completed',sale_id=(result->>'id')::uuid,completed_at=now(),updated_at=now() where orders.id=o.id;
 elsif action='refund' then
  select * into orig from verdelia_private.sales where sales.id=(data->>'id')::uuid for update;
  if not found or orig.type<>'sale' or orig.status<>'paid' then raise exception 'La venta no admite otra devolución.';end if;
  if length(trim(memo))<3 then raise exception 'Escribe el motivo de la devolución.';end if;
  cost:=0;
  if coalesce((data->>'restock')::boolean,false) then
   for n in select x->>'id' pid,sum((x->>'quantity')::numeric) qty,sum((x->>'quantity')::numeric*(x->>'unit_cost')::numeric) value from jsonb_array_elements(orig.lines) l cross join lateral jsonb_array_elements(l->'ingredients') x group by x->>'id' loop
    update verdelia_private.products set avg_cost=round((stock*avg_cost+n.value)/(stock+n.qty),4) where products.id=n.pid::uuid;
    perform verdelia_private.move_stock(n.pid::uuid,n.qty,'refund','Devolución VD-'||orig.number,orig.id);cost:=cost-round(n.value,2);
   end loop;
  end if;
  insert into verdelia_private.sales(type,original_id,channel,customer,lines,needs,subtotal,discount,delivery,total,cost,method,status,note,actor)
  values('refund',orig.id,orig.channel,orig.customer,orig.lines,orig.needs,-orig.subtotal,-orig.discount,-orig.delivery,-orig.total,cost,orig.method,'paid',memo,nullif(current_setting('verdelia.actor',true),'')::uuid) returning * into s;
  update verdelia_private.sales set status='refunded' where sales.id=orig.id;
  if orig.total>0 then insert into verdelia_private.cash_moves(kind,amount,method,category,note,reference_id,actor) values('refund',-orig.total,orig.method,'Devolución',memo,s.id,nullif(current_setting('verdelia.actor',true),'')::uuid);end if;
  result:=to_jsonb(s);
 elsif action='settings' then
  update verdelia_private.settings set name=left(coalesce(data->>'name',name),100),whatsapp=regexp_replace(coalesce(data->>'whatsapp',whatsapp),'[^0-9]','','g'),address=left(coalesce(data->>'address',address),250),pound_grams=coalesce((data->>'pound_grams')::numeric,pound_grams),delivery_enabled=coalesce((data->>'delivery_enabled')::boolean,delivery_enabled),pickup_enabled=coalesce((data->>'pickup_enabled')::boolean,pickup_enabled),delivery_fee=coalesce((data->>'delivery_fee')::numeric,delivery_fee),catalog_enabled=coalesce((data->>'catalog_enabled')::boolean,catalog_enabled),closing_time=coalesce((data->>'closing_time')::time,closing_time),notes=left(coalesce(data->>'notes',notes),1000),updated_at=now() where settings.id=true returning to_jsonb(settings.*) into result;
 elsif action='preferences' then
  update verdelia_private.alert_preferences set stock=coalesce((data->>'stock')::boolean,stock),expiry=coalesce((data->>'expiry')::boolean,expiry),pending_orders=coalesce((data->>'pending_orders')::boolean,pending_orders),expiry_days=coalesce((data->>'expiry_days')::integer,expiry_days) where alert_preferences.id=true returning to_jsonb(alert_preferences.*) into result;
 else raise exception 'Acción no reconocida.';end if;
 insert into verdelia_private.audit(action,reference_id,detail,actor) values(action,coalesce(case when coalesce(result->>'id','')~'^[0-9a-f-]{36}$' then (result->>'id')::uuid end,case when coalesce(data->>'id','')~'^[0-9a-f-]{36}$' then (data->>'id')::uuid end),jsonb_build_object('request_id',rid,'note',memo),nullif(current_setting('verdelia.actor',true),'')::uuid);
 insert into verdelia_private.requests(id,action,payload,result,actor) values(rid,action,data,result,nullif(current_setting('verdelia.actor',true),'')::uuid);
 return result;
end $$;

-- Only these narrow entrypoints are exposed. Private functions check identity where required.
create or replace function public.verdelia_catalog() returns jsonb language sql security invoker set search_path='' as $$select verdelia_private.catalog()$$;
create or replace function public.verdelia_order(data jsonb) returns jsonb language sql security invoker set search_path='' as $$select verdelia_private.public_order(data)$$;
create or replace function public.verdelia_admin(action text,data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select verdelia_private.admin(action,data)$$;
revoke execute on all functions in schema verdelia_private from public,anon,authenticated;
grant usage on schema verdelia_private to anon,authenticated;
grant execute on function verdelia_private.catalog(),verdelia_private.public_order(jsonb) to anon,authenticated;
grant execute on function verdelia_private.admin(text,jsonb) to anon,authenticated;
revoke all on function public.verdelia_catalog(),public.verdelia_order(jsonb),public.verdelia_admin(text,jsonb) from public,anon,authenticated;
grant execute on function public.verdelia_catalog(),public.verdelia_order(jsonb) to anon,authenticated;
grant execute on function public.verdelia_admin(text,jsonb) to anon,authenticated;
notify pgrst,'reload schema';
commit;
