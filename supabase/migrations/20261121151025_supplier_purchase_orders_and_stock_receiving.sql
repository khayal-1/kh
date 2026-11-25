begin;
create sequence if not exists public.supplier_order_number_seq;
create sequence if not exists public.supplier_receipt_number_seq;
create table if not exists public.suppliers (
 id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 2 and 160),
 phone text,email text,address text,notes text,is_active boolean not null default true,
 created_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.purchase_orders (
 id uuid primary key default gen_random_uuid(),order_number text not null unique,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 status text not null default 'ordered' check(status in ('ordered','partially_received','received','cancelled')),
 notes text,created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.purchase_order_items (
 id uuid primary key default gen_random_uuid(),purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
 motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,motorcycle_name text not null,model_year smallint,
 quantity_ordered integer not null check(quantity_ordered between 1 and 10000),
 quantity_received integer not null default 0 check(quantity_received>=0 and quantity_received<=quantity_ordered),
 unit_cost numeric(12,2) not null check(unit_cost>=0),created_at timestamptz not null default now(),unique(purchase_order_id,motorcycle_id)
);
create table if not exists public.purchase_receipts (
 id uuid primary key default gen_random_uuid(),receipt_number text not null unique,
 purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
 received_by uuid not null references auth.users(id) on delete restrict,notes text,received_at timestamptz not null default now()
);
create table if not exists public.purchase_receipt_items (
 id uuid primary key default gen_random_uuid(),receipt_id uuid not null references public.purchase_receipts(id) on delete restrict,
 purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete restrict,
 motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,quantity integer not null check(quantity>0),
 unit_cost numeric(12,2) not null check(unit_cost>=0),created_at timestamptz not null default now(),unique(receipt_id,purchase_order_item_id)
);
create index if not exists purchase_orders_supplier_created_idx on public.purchase_orders(supplier_id,created_at desc);
create index if not exists purchase_order_items_order_idx on public.purchase_order_items(purchase_order_id);
create index if not exists purchase_receipts_order_idx on public.purchase_receipts(purchase_order_id,received_at desc);
create index if not exists purchase_receipt_items_order_item_idx on public.purchase_receipt_items(purchase_order_item_id);
create index if not exists purchase_receipt_items_motorcycle_idx on public.purchase_receipt_items(motorcycle_id);

create or replace function public.can_manage_purchasing()
returns boolean language sql stable security invoker set search_path=''
as $$ select public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('purchasing_manage'); $$;

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

create or replace function public.record_motorcycle_stock_movement()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_source text:=coalesce(current_setting('ekm.stock_movement_source',true),'');v_reference text:=nullif(current_setting('ekm.stock_movement_reference',true),'');
begin
 if tg_op='INSERT' then
  if new.stock>0 then insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,notes,created_by) values(new.id,'opening',new.stock,'رصيد افتتاحي عند إضافة الدراجة',(select auth.uid())); end if;
 elsif new.stock is distinct from old.stock and v_source<>'sale' then
  insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by)
  values(new.id,case when v_source='purchase_receipt' then 'purchase_receipt' else 'adjustment' end,new.stock-old.stock,
   case when v_source='purchase_receipt' and v_reference is not null then v_reference::uuid else null end,
   case when v_source='purchase_receipt' then 'استلام توريد' else 'تسوية مخزون من تعديل بيانات الدراجة' end,(select auth.uid()));
 end if;
 return new;
end; $$;

alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.purchase_receipts enable row level security;
alter table public.purchase_receipt_items enable row level security;
revoke all on public.suppliers,public.purchase_orders,public.purchase_order_items,public.purchase_receipts,public.purchase_receipt_items from anon,authenticated;
grant select,insert,update on public.suppliers to authenticated;
grant select on public.purchase_orders,public.purchase_order_items,public.purchase_receipts,public.purchase_receipt_items to authenticated;
grant usage,select on sequence public.supplier_order_number_seq,public.supplier_receipt_number_seq to authenticated;
create policy suppliers_manage on public.suppliers for all to authenticated using(public.can_manage_purchasing()) with check(public.can_manage_purchasing());
create policy purchase_orders_read on public.purchase_orders for select to authenticated using(public.can_manage_purchasing());
create policy purchase_order_items_read on public.purchase_order_items for select to authenticated using(public.can_manage_purchasing());
create policy purchase_receipts_read on public.purchase_receipts for select to authenticated using(public.can_manage_purchasing());
create policy purchase_receipt_items_read on public.purchase_receipt_items for select to authenticated using(public.can_manage_purchasing());
revoke all on function public.create_supplier_purchase_order(uuid,jsonb,text) from public,anon;
grant execute on function public.create_supplier_purchase_order(uuid,jsonb,text) to authenticated;
revoke all on function public.receive_supplier_purchase_order(uuid,jsonb,text) from public,anon;
grant execute on function public.receive_supplier_purchase_order(uuid,jsonb,text) to authenticated;
create index if not exists contact_message_replies_sent_by_idx on public.contact_message_replies(sent_by);
create index if not exists customer_request_replies_sent_by_idx on public.customer_request_replies(sent_by);
create index if not exists payments_received_by_idx on public.payments(received_by);
create index if not exists sales_customer_id_idx on public.sales(customer_id);
create index if not exists stock_movements_created_by_idx on public.stock_movements(created_by);
drop policy if exists contact_staff on public.contact_messages;
commit;