-- Apply to an existing installation without changing grants or accounts.
begin;
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


notify pgrst,'reload schema';
commit;
