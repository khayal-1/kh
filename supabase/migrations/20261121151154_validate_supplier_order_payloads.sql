-- The base supplier migration was followed by stricter payload validation.
create or replace function public.create_supplier_purchase_order(p_supplier_id uuid,p_items jsonb,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_item jsonb;v_bike public.motorcycles%rowtype;v_order_id uuid;v_order_number text;v_motorcycle_id uuid;v_qty integer;v_cost numeric(12,2);
begin
 if (select auth.uid()) is null or not public.can_manage_purchasing() then raise exception using errcode='42501',message='ليس لديك صلاحية إنشاء أمر توريد'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and is_active) then raise exception using errcode='23503',message='المورد غير موجود أو غير نشط'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' then raise exception using errcode='22023',message='صيغة أصناف التوريد غير صحيحة'; end if;
 if jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>20 then raise exception using errcode='22023',message='أضف من صنف واحد إلى 20 صنفًا'; end if;
 if (select count(*) from jsonb_array_elements(p_items))<>(select count(distinct value->>'motorcycle_id') from jsonb_array_elements(p_items)) then raise exception using errcode='22023',message='لا تكرر الدراجة في أكثر من سطر'; end if;
 v_order_number:='PO-'||to_char(now(),'YYYYMMDD')||'-'||lpad(nextval('public.supplier_order_number_seq')::text,6,'0');
 insert into public.purchase_orders(order_number,supplier_id,status,notes,created_by) values(v_order_number,p_supplier_id,'ordered',nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning id into v_order_id;
 for v_item in select value from jsonb_array_elements(p_items) as x(value) order by value->>'motorcycle_id' loop
  begin v_motorcycle_id:=(v_item->>'motorcycle_id')::uuid;v_qty:=(v_item->>'quantity')::integer;v_cost:=(v_item->>'unit_cost')::numeric(12,2);
  exception when others then raise exception using errcode='22023',message='بيانات صنف التوريد غير صحيحة'; end;
  if v_qty not between 1 and 10000 or v_cost is null or v_cost<0 then raise exception using errcode='22023',message='الكمية أو تكلفة الوحدة غير صحيحة'; end if;
  select * into v_bike from public.motorcycles where id=v_motorcycle_id for share;
  if not found then raise exception using errcode='P0002',message='الدراجة المحددة غير موجودة'; end if;
  insert into public.purchase_order_items(purchase_order_id,motorcycle_id,motorcycle_name,model_year,quantity_ordered,unit_cost) values(v_order_id,v_bike.id,v_bike.name,v_bike.model_year,v_qty,v_cost);
 end loop;
 return jsonb_build_object('id',v_order_id,'order_number',v_order_number);
end; $$;

create or replace function public.receive_supplier_purchase_order(p_order_id uuid,p_items jsonb,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_order public.purchase_orders%rowtype;v_item jsonb;v_po_item public.purchase_order_items%rowtype;v_receipt_id uuid;v_receipt_number text;v_item_id uuid;v_qty integer;v_total integer:=0;v_all_received boolean;
begin
 if (select auth.uid()) is null or not public.can_manage_purchasing() then raise exception using errcode='42501',message='ليس لديك صلاحية استلام التوريد'; end if;
 select * into v_order from public.purchase_orders where id=p_order_id for update;
 if not found or v_order.status='cancelled' then raise exception using errcode='P0002',message='أمر التوريد غير موجود أو ملغى'; end if;
 if v_order.status='received' then raise exception using errcode='23514',message='تم استلام أمر التوريد بالكامل'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' then raise exception using errcode='22023',message='صيغة كميات الاستلام غير صحيحة'; end if;
 if jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>20 then raise exception using errcode='22023',message='حدد من بند واحد إلى 20 بندًا للاستلام'; end if;
 if (select count(*) from jsonb_array_elements(p_items))<>(select count(distinct value->>'purchase_order_item_id') from jsonb_array_elements(p_items)) then raise exception using errcode='22023',message='لا تكرر بند أمر التوريد'; end if;
 v_receipt_number:='GR-'||to_char(now(),'YYYYMMDD')||'-'||lpad(nextval('public.supplier_receipt_number_seq')::text,6,'0');
 insert into public.purchase_receipts(receipt_number,purchase_order_id,received_by,notes) values(v_receipt_number,p_order_id,(select auth.uid()),nullif(btrim(coalesce(p_notes,'')),'')) returning id into v_receipt_id;
 perform set_config('ekm.stock_movement_source','purchase_receipt',true);
 perform set_config('ekm.stock_movement_reference',v_receipt_id::text,true);
 for v_item in select value from jsonb_array_elements(p_items) as x(value) order by value->>'purchase_order_item_id' loop
  begin v_item_id:=(v_item->>'purchase_order_item_id')::uuid;v_qty:=(v_item->>'quantity')::integer;
  exception when others then raise exception using errcode='22023',message='بند أو كمية الاستلام غير صحيحة'; end;
  if v_qty is null or v_qty<=0 then raise exception using errcode='22023',message='الكمية المستلمة يجب أن تكون أكبر من صفر'; end if;
  select * into v_po_item from public.purchase_order_items where id=v_item_id and purchase_order_id=p_order_id for update;
  if not found then raise exception using errcode='P0002',message='بند التوريد غير تابع لأمر التوريد'; end if;
  if v_qty>v_po_item.quantity_ordered-v_po_item.quantity_received then raise exception using errcode='23514',message='الكمية المستلمة أكبر من الكمية المتبقية للصنف: '||v_po_item.motorcycle_name; end if;
  insert into public.purchase_receipt_items(receipt_id,purchase_order_item_id,motorcycle_id,quantity,unit_cost) values(v_receipt_id,v_item_id,v_po_item.motorcycle_id,v_qty,v_po_item.unit_cost);
  update public.purchase_order_items set quantity_received=quantity_received+v_qty where id=v_item_id;
  update public.motorcycles set stock=stock+v_qty where id=v_po_item.motorcycle_id;
  v_total:=v_total+v_qty;
 end loop;
 select bool_and(quantity_received=quantity_ordered) into v_all_received from public.purchase_order_items where purchase_order_id=p_order_id;
 update public.purchase_orders set status=case when v_all_received then 'received' else 'partially_received' end,updated_at=now() where id=p_order_id;
 return jsonb_build_object('receipt_id',v_receipt_id,'receipt_number',v_receipt_number,'quantity_received',v_total,'status',case when v_all_received then 'received' else 'partially_received' end);
end; $$;