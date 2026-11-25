-- Source recovered from the applied production migration ledger.
create table if not exists public.motorcycle_inventory_costs(
 motorcycle_id uuid primary key references public.motorcycles(id) on delete restrict,
 unit_cost numeric(14,2) check(unit_cost is null or unit_cost>=0),
 reorder_level integer not null default 0 check(reorder_level>=0),
 updated_by uuid references auth.users(id) on delete restrict,updated_at timestamptz not null default now()
);
insert into public.motorcycle_inventory_costs(motorcycle_id,unit_cost,reorder_level)
select pri.motorcycle_id,round(sum(pri.quantity*pri.unit_cost)/nullif(sum(pri.quantity),0),2),0
from public.purchase_receipt_items pri group by pri.motorcycle_id having sum(pri.quantity)>0
on conflict(motorcycle_id) do nothing;

create table if not exists public.motorcycle_units(
 id uuid primary key default gen_random_uuid(),motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,
 vin text not null unique,barcode text unique,
 unit_status text not null default 'available' check(unit_status in ('available','reserved','sold','service','retired')),
 sale_item_id uuid references public.sale_items(id) on delete restrict,warranty_start date,warranty_end date,notes text,
 registered_by uuid not null references auth.users(id) on delete restrict,registered_at timestamptz not null default now(),
 check(warranty_end is null or warranty_start is null or warranty_end>=warranty_start)
);
create index if not exists motorcycle_units_model_status_idx on public.motorcycle_units(motorcycle_id,unit_status);

create table if not exists public.stocktake_batches(
 id uuid primary key default gen_random_uuid(),stocktake_number bigint generated always as identity unique,
 stocktake_date date not null,notes text,status text not null default 'posted' check(status='posted'),
 total_increase numeric(14,2) not null default 0,total_decrease numeric(14,2) not null default 0,
 journal_entry_id uuid unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now()
);
create table if not exists public.stocktake_lines(
 id uuid primary key default gen_random_uuid(),stocktake_id uuid not null references public.stocktake_batches(id) on delete restrict,
 motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,
 expected_quantity integer not null,counted_quantity integer not null,quantity_delta integer not null,
 unit_cost numeric(14,2),value_delta numeric(14,2) not null default 0,
 unique(stocktake_id,motorcycle_id),
 check(expected_quantity>=0 and counted_quantity>=0 and quantity_delta=counted_quantity-expected_quantity),
 check(unit_cost is null or unit_cost>=0)
);
create table if not exists public.warranties(
 id uuid primary key default gen_random_uuid(),warranty_number bigint generated always as identity unique,
 motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,sale_id uuid references public.sales(id) on delete restrict,
 customer_id uuid references public.clients(id) on delete restrict,customer_name text not null,customer_phone text,
 start_date date not null,end_date date not null,terms text,status text not null default 'active' check(status in ('active','expired','void')),
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),check(end_date>=start_date)
);
create index if not exists warranties_customer_phone_idx on public.warranties(customer_phone);
create table if not exists public.service_orders(
 id uuid primary key default gen_random_uuid(),service_number bigint generated always as identity unique,
 motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,motorcycle_unit_id uuid references public.motorcycle_units(id) on delete restrict,
 warranty_id uuid references public.warranties(id) on delete restrict,customer_id uuid references public.clients(id) on delete restrict,
 customer_name text not null,customer_phone text not null,assigned_employee_id uuid references public.employees(id) on delete restrict,
 issue_description text not null,diagnosis text,estimated_cost numeric(14,2) not null default 0 check(estimated_cost>=0),
 actual_cost numeric(14,2) check(actual_cost is null or actual_cost>=0),
 status text not null default 'open' check(status in ('open','in_progress','waiting_parts','completed','cancelled')),
 opened_at timestamptz not null default now(),completed_at timestamptz,notes text,
 created_by uuid not null references auth.users(id) on delete restrict,
 check((status='completed' and completed_at is not null) or (status<>'completed' and completed_at is null))
);
create index if not exists service_orders_status_idx on public.service_orders(status,opened_at desc);

alter table public.motorcycle_inventory_costs enable row level security;
alter table public.motorcycle_units enable row level security;
alter table public.stocktake_batches enable row level security;
alter table public.stocktake_lines enable row level security;
alter table public.warranties enable row level security;
alter table public.service_orders enable row level security;
revoke all on public.motorcycle_inventory_costs,public.motorcycle_units,public.stocktake_batches,public.stocktake_lines,public.warranties,public.service_orders from anon,authenticated;
grant select on public.motorcycle_inventory_costs,public.motorcycle_units,public.stocktake_batches,public.stocktake_lines,public.warranties,public.service_orders to authenticated;
create policy motorcycle_inventory_costs_read on public.motorcycle_inventory_costs for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage') or public.has_employee_permission('catalog_manage'));
create policy motorcycle_units_read on public.motorcycle_units for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('catalog_manage') or public.has_employee_permission('finance_manage'));
create policy stocktake_batches_read on public.stocktake_batches for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));
create policy stocktake_lines_read on public.stocktake_lines for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));
create policy warranties_read on public.warranties for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('catalog_manage') or public.has_employee_permission('finance_manage'));
create policy service_orders_read on public.service_orders for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('catalog_manage') or public.has_employee_permission('finance_manage'));

create or replace function private.set_motorcycle_inventory_controls(p_motorcycle_id uuid,p_unit_cost numeric,p_reorder_level integer)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.can_manage_finance() and not public.has_employee_permission('catalog_manage') then raise exception 'غير مصرح بتحديث تكلفة أو حد إعادة الطلب' using errcode='42501'; end if;
 if p_motorcycle_id is null or p_reorder_level is null or p_reorder_level<0 or (p_unit_cost is not null and p_unit_cost<0) then raise exception 'بيانات تكلفة المخزون غير صحيحة' using errcode='22023'; end if;
 if not exists(select 1 from public.motorcycles where id=p_motorcycle_id) then raise exception 'الدراجة غير موجودة' using errcode='P0002'; end if;
 insert into public.motorcycle_inventory_costs(motorcycle_id,unit_cost,reorder_level,updated_by,updated_at) values(p_motorcycle_id,p_unit_cost,p_reorder_level,(select auth.uid()),now())
 on conflict(motorcycle_id) do update set unit_cost=excluded.unit_cost,reorder_level=excluded.reorder_level,updated_by=excluded.updated_by,updated_at=now();
end $$;

create or replace function private.register_motorcycle_unit(p_motorcycle_id uuid,p_vin text,p_barcode text default null,p_warranty_start date default null,p_warranty_end date default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_stock integer;v_registered integer;
begin
 if not private.can_manage_finance() and not public.has_employee_permission('catalog_manage') then raise exception 'غير مصرح بتسجيل رقم الهيكل' using errcode='42501'; end if;
 if nullif(btrim(coalesce(p_vin,'')),'') is null or p_motorcycle_id is null or (p_warranty_end is not null and p_warranty_start is not null and p_warranty_end<p_warranty_start) then raise exception 'بيانات رقم الهيكل غير صحيحة' using errcode='22023'; end if;
 select stock into v_stock from public.motorcycles where id=p_motorcycle_id for update;if not found then raise exception 'الدراجة غير موجودة' using errcode='P0002';end if;
 select count(*) into v_registered from public.motorcycle_units where motorcycle_id=p_motorcycle_id and unit_status in ('available','reserved','service');
 if v_registered>=v_stock then raise exception 'عدد أرقام الهياكل المسجلة وصل إلى كمية المخزون؛ راجع الجرد أولاً' using errcode='23514';end if;
 insert into public.motorcycle_units(motorcycle_id,vin,barcode,warranty_start,warranty_end,notes,registered_by)
 values(p_motorcycle_id,btrim(p_vin),nullif(btrim(coalesce(p_barcode,'')),''),p_warranty_start,p_warranty_end,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning id into v_id;return v_id;
end $$;

create or replace function private.create_stocktake(p_date date,p_notes text,p_lines jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid();v_entry uuid:=gen_random_uuid();v_item jsonb;v_bike public.motorcycles%rowtype;v_cost numeric(14,2);v_count integer;v_delta integer;
 v_inventory uuid;v_gain uuid;v_loss uuid;v_increase numeric(14,2):=0;v_decrease numeric(14,2):=0;v_line_value numeric(14,2);v_count_lines integer:=0;v_stocktake_number bigint;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإجراء الجرد' using errcode='42501';end if;
 if p_date is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>200 then raise exception 'بيانات الجرد غير صحيحة' using errcode='22023';end if;
 select id into v_inventory from public.accounting_accounts where code='1200' and is_active;select id into v_gain from public.accounting_accounts where code='4090' and is_active;select id into v_loss from public.accounting_accounts where code='5000' and is_active;
 if v_inventory is null or v_gain is null or v_loss is null then raise exception 'حسابات المخزون وفروق الجرد غير مهيأة' using errcode='22023';end if;
 insert into public.stocktake_batches(id,stocktake_date,notes,created_by) values(v_id,p_date,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning stocktake_number into v_stocktake_number;
 for v_item in select value from jsonb_array_elements(p_lines) loop
  select * into v_bike from public.motorcycles where id=(v_item->>'motorcycle_id')::uuid for update;if not found then raise exception 'دراجة غير موجودة ضمن الجرد' using errcode='P0002';end if;
  v_count:=(v_item->>'counted_quantity')::integer;if v_count<0 then raise exception 'الكمية المعدودة لا يمكن أن تكون سالبة' using errcode='22023';end if;
  v_delta:=v_count-v_bike.stock;select unit_cost into v_cost from public.motorcycle_inventory_costs where motorcycle_id=v_bike.id;
  if v_delta<>0 and (v_cost is null or v_cost<=0) then raise exception 'يجب إدخال تكلفة شراء فعلية للدراجة % قبل ترحيل فرق الجرد',v_bike.name using errcode='23514';end if;
  v_line_value:=abs(v_delta)*coalesce(v_cost,0);
  insert into public.stocktake_lines(stocktake_id,motorcycle_id,expected_quantity,counted_quantity,quantity_delta,unit_cost,value_delta) values(v_id,v_bike.id,v_bike.stock,v_count,v_delta,v_cost,v_delta*coalesce(v_cost,0));
  if v_delta<>0 then
   insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by) values(v_bike.id,'adjustment',v_delta,v_id,'تسوية جرد رقم '||v_stocktake_number,(select auth.uid()));
   update public.motorcycles set stock=v_count where id=v_bike.id;
   if v_delta>0 then v_increase:=v_increase+v_line_value;else v_decrease:=v_decrease+v_line_value;end if;
  end if;
  v_count_lines:=v_count_lines+1;
 end loop;
 if v_increase+v_decrease>0 then
  insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_date,'تسوية جرد المخزون #'||v_stocktake_number,'stocktake',v_id,(select auth.uid()));
  if v_increase>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_inventory,v_increase,0,'زيادة مخزون حسب الجرد'),(v_entry,v_gain,0,v_increase,'فائض جرد');end if;
  if v_decrease>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_loss,v_decrease,0,'عجز مخزون حسب الجرد'),(v_entry,v_inventory,0,v_decrease,'تخفيض مخزون حسب الجرد');end if;
  update public.stocktake_batches set journal_entry_id=v_entry,total_increase=v_increase,total_decrease=v_decrease where id=v_id;
 end if;
 return jsonb_build_object('stocktake_id',v_id,'stocktake_number',v_stocktake_number,'lines_count',v_count_lines,'increase_value',v_increase,'decrease_value',v_decrease,'journal_entry_id',case when v_increase+v_decrease>0 then v_entry else null end);
end $$;

create or replace function private.create_warranty(p_motorcycle_id uuid,p_sale_id uuid,p_customer_id uuid,p_customer_name text,p_phone text,p_start date,p_end date,p_terms text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not private.can_manage_finance() and not public.has_employee_permission('catalog_manage') then raise exception 'غير مصرح بإدارة الضمان' using errcode='42501';end if;
 if p_motorcycle_id is null or nullif(btrim(coalesce(p_customer_name,'')),'') is null or nullif(btrim(coalesce(p_phone,'')),'') is null or p_start is null or p_end is null or p_end<p_start then raise exception 'بيانات الضمان غير صحيحة' using errcode='22023';end if;
 if p_sale_id is not null and not exists(select 1 from public.sales where id=p_sale_id and status='posted') then raise exception 'فاتورة البيع غير موجودة أو غير مرحلة' using errcode='22023';end if;
 insert into public.warranties(motorcycle_id,sale_id,customer_id,customer_name,customer_phone,start_date,end_date,terms,created_by) values(p_motorcycle_id,p_sale_id,p_customer_id,btrim(p_customer_name),btrim(p_phone),p_start,p_end,nullif(btrim(coalesce(p_terms,'')),''),(select auth.uid())) returning id into v_id;return v_id;
end $$;

create or replace function private.create_service_order(p_motorcycle_id uuid,p_unit_id uuid,p_warranty_id uuid,p_customer_id uuid,p_customer_name text,p_phone text,p_employee_id uuid,p_issue text,p_estimated numeric,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not private.can_manage_finance() and not public.has_employee_permission('catalog_manage') then raise exception 'غير مصرح بفتح أمر صيانة' using errcode='42501';end if;
 if p_motorcycle_id is null or nullif(btrim(coalesce(p_customer_name,'')),'') is null or nullif(btrim(coalesce(p_phone,'')),'') is null or nullif(btrim(coalesce(p_issue,'')),'') is null or p_estimated is null or p_estimated<0 then raise exception 'بيانات أمر الصيانة غير صحيحة' using errcode='22023';end if;
 if p_unit_id is not null and not exists(select 1 from public.motorcycle_units where id=p_unit_id and motorcycle_id=p_motorcycle_id) then raise exception 'رقم الهيكل لا يطابق طراز الدراجة' using errcode='23514';end if;
 if p_warranty_id is not null and not exists(select 1 from public.warranties where id=p_warranty_id and motorcycle_id=p_motorcycle_id and status='active' and end_date>=current_date) then raise exception 'الضمان غير صالح لهذه الدراجة' using errcode='23514';end if;
 insert into public.service_orders(motorcycle_id,motorcycle_unit_id,warranty_id,customer_id,customer_name,customer_phone,assigned_employee_id,issue_description,estimated_cost,notes,created_by)
 values(p_motorcycle_id,p_unit_id,p_warranty_id,p_customer_id,btrim(p_customer_name),btrim(p_phone),p_employee_id,btrim(p_issue),p_estimated,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning id into v_id;return v_id;
end $$;

create or replace function private.update_service_order(p_order_id uuid,p_status text,p_diagnosis text,p_actual_cost numeric)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.can_manage_finance() and not public.has_employee_permission('catalog_manage') then raise exception 'غير مصرح بتحديث أمر الصيانة' using errcode='42501';end if;
 if p_status not in ('open','in_progress','waiting_parts','completed','cancelled') or (p_actual_cost is not null and p_actual_cost<0) then raise exception 'بيانات حالة الصيانة غير صحيحة' using errcode='22023';end if;
 update public.service_orders set status=p_status,diagnosis=nullif(btrim(coalesce(p_diagnosis,'')),''),actual_cost=p_actual_cost,completed_at=case when p_status='completed' then now() else null end where id=p_order_id and status not in ('completed','cancelled');
 if not found then raise exception 'أمر الصيانة غير موجود أو مغلق نهائيًا' using errcode='P0002';end if;
end $$;

create or replace view public.inventory_reorder_alerts with (security_invoker=true) as
select m.id as motorcycle_id,m.name,m.category,m.model_year,m.stock,coalesce(ic.reorder_level,0) as reorder_level,ic.unit_cost,
 case when ic.unit_cost is null then null else (m.stock*ic.unit_cost)::numeric(14,2) end as stock_value
from public.motorcycles m left join public.motorcycle_inventory_costs ic on ic.motorcycle_id=m.id
where coalesce(ic.reorder_level,0)>0 and m.stock<=ic.reorder_level;
grant select on public.inventory_reorder_alerts to authenticated;

create or replace function public.set_motorcycle_inventory_controls(uuid,numeric,integer) returns void language sql security invoker set search_path='' as $$ select private.set_motorcycle_inventory_controls($1,$2,$3) $$;
create or replace function public.register_motorcycle_unit(uuid,text,text,date,date,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.register_motorcycle_unit($1,$2,$3,$4,$5,$6) $$;
create or replace function public.create_stocktake(date,text,jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.create_stocktake($1,$2,$3) $$;
create or replace function public.create_warranty(uuid,uuid,uuid,text,text,date,date,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_warranty($1,$2,$3,$4,$5,$6,$7,$8) $$;
create or replace function public.create_service_order(uuid,uuid,uuid,uuid,text,text,uuid,text,numeric,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_service_order($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) $$;
create or replace function public.update_service_order(uuid,text,text,numeric) returns void language sql security invoker set search_path='' as $$ select private.update_service_order($1,$2,$3,$4) $$;
do $$ declare sig text;begin for sig in select unnest(array[
'public.set_motorcycle_inventory_controls(uuid,numeric,integer)','public.register_motorcycle_unit(uuid,text,text,date,date,text)','public.create_stocktake(date,text,jsonb)',
'public.create_warranty(uuid,uuid,uuid,text,text,date,date,text)','public.create_service_order(uuid,uuid,uuid,uuid,text,text,uuid,text,numeric,text)','public.update_service_order(uuid,text,text,numeric)'
]) loop execute format('revoke all on function %s from public,anon',sig);execute format('grant execute on function %s to authenticated',sig);end loop;end $$;

