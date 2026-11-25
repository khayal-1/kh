begin;

-- A model's on-hand stock must agree with its individually tracked physical units.
create or replace view public.inventory_unit_reconciliation
with (security_invoker=true)
as
select
  m.id as motorcycle_id,
  m.name as motorcycle_name,
  m.stock as model_stock,
  (count(u.id) filter (where u.unit_status in ('available','reserved','service')))::integer as physical_units,
  (m.stock-(count(u.id) filter (where u.unit_status in ('available','reserved','service'))))::integer as difference,
  (count(u.id) filter (where u.unit_status='available'))::integer as available_units,
  (count(u.id) filter (where u.unit_status='reserved'))::integer as reserved_units,
  (count(u.id) filter (where u.unit_status='service'))::integer as service_units,
  (count(u.id) filter (where u.unit_status='sold'))::integer as sold_units,
  (count(u.id) filter (where u.unit_status='retired'))::integer as retired_units
from public.motorcycles m
left join public.motorcycle_units u on u.motorcycle_id=m.id
group by m.id,m.name,m.stock;
grant select on public.inventory_unit_reconciliation to authenticated;

create or replace function private.guard_motorcycle_stock_matches_units()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_source text:=coalesce(current_setting('ekm.stock_movement_source',true),'');
  v_units integer;
begin
  if new.stock is not distinct from old.stock then return new; end if;
  if v_source not in ('sale','purchase_receipt','purchase_return','stocktake') then
    raise exception 'لا تعدّل مخزون الطراز مباشرة؛ استخدم استلامًا مسجلًا أو جردًا للوحدات ذات أرقام الشاسيه'
      using errcode='23514';
  end if;
  select count(*)::integer into v_units
    from public.motorcycle_units
   where motorcycle_id=new.id
     and unit_status in ('available','reserved','service');
  if new.stock<>v_units then
    raise exception 'تغيير الرصيد لا يطابق عدد الوحدات الفعلية المسجلة بأرقام الشاسيه لهذا الطراز'
      using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_motorcycle_stock_matches_units() from public,anon,authenticated;
drop trigger if exists motorcycles_stock_unit_guard on public.motorcycles;
create trigger motorcycles_stock_unit_guard
before update of stock on public.motorcycles
for each row execute function private.guard_motorcycle_stock_matches_units();

-- The stocktake operation records the movement through the stock trigger and
-- may only set a count equal to the tracked physical units.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('private.create_stocktake(date,text,jsonb)'::regprocedure)
    into v_definition;
  v_definition:=replace(
    v_definition,
    '   insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by) values(v_bike.id,''adjustment'',v_delta,v_id,''تسوية جرد رقم ''||v_stocktake_number,(select auth.uid()));',
    ''
  );
  v_definition:=replace(
    v_definition,
    '  v_count:=(v_item->>''counted_quantity'')::integer;if v_count<0 then raise exception ''الكمية المعدودة لا يمكن أن تكون سالبة'' using errcode=''22023'';end if;',
    '  v_count:=(v_item->>''counted_quantity'')::integer;if v_count<0 then raise exception ''الكمية المعدودة لا يمكن أن تكون سالبة'' using errcode=''22023'';end if; if v_count<>(select count(*) from public.motorcycle_units where motorcycle_id=v_bike.id and unit_status in (''available'',''reserved'',''service'')) then raise exception ''عدد الجرد لا يطابق الوحدات المسجلة بأرقام الشاسيه'' using errcode=''23514'';end if;'
  );
  v_definition:=replace(
    v_definition,
    '   update public.motorcycles set stock=v_count where id=v_bike.id;',
    '   perform set_config(''ekm.stock_movement_source'',''stocktake'',true); update public.motorcycles set stock=v_count where id=v_bike.id; perform set_config(''ekm.stock_movement_source'','''',true);'
  );
  if position('v_count<>(select count(*)' in v_definition)=0
     or position('set_config(''ekm.stock_movement_source'',''stocktake''' in v_definition)=0
     or position('insert into public.stock_movements' in v_definition)>0 then
    raise exception 'Unable to harden stocktake function; expected source fragments were not found.';
  end if;
  execute v_definition;
end;
$$;

-- Disable the old quantity-only receiving endpoint. All new receipts must carry
-- a VIN per physical unit through receive_supplier_purchase_order_units.
revoke all on function public.receive_supplier_purchase_order(uuid,jsonb,text) from public,anon,authenticated;

commit;
