begin;

create table if not exists public.supplier_return_units (
  id uuid primary key default gen_random_uuid(),
  supplier_return_item_id uuid not null references public.supplier_return_items(id) on delete restrict,
  motorcycle_unit_id uuid not null unique references public.motorcycle_units(id) on delete restrict,
  unit_cost numeric(14,2) not null check(unit_cost>=0),
  created_at timestamptz not null default now()
);
create index if not exists supplier_return_units_item_idx
  on public.supplier_return_units(supplier_return_item_id);
alter table public.supplier_return_units enable row level security;
revoke all on public.supplier_return_units from anon,authenticated;
grant select on public.supplier_return_units to authenticated;
create policy supplier_return_units_read on public.supplier_return_units
  for select to authenticated using(public.can_manage_purchasing());

create or replace function private.create_supplier_return_for_units_impl(
  p_purchase_order_id uuid,
  p_supplier_bill_id uuid,
  p_items jsonb,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  o public.purchase_orders%rowtype;
  bill public.supplier_bills%rowtype;
  item jsonb;
  unit_value text;
  receipt_item public.purchase_receipt_items%rowtype;
  unit_row public.motorcycle_units%rowtype;
  return_id uuid;
  return_number bigint;
  return_item_id uuid;
  unit_id uuid;
  qty integer;
  already_returned integer;
  total_credit numeric(14,2):=0;
  existing_credit numeric(14,2):=0;
  item_count integer:=0;
  ids text[];
begin
  if (select auth.uid()) is null or not public.can_manage_purchasing() then
    raise exception 'ليس لديك صلاحية تسجيل مرتجعات الموردين' using errcode='42501';
  end if;
  select * into o from public.purchase_orders where id=p_purchase_order_id for update;
  if not found then raise exception 'أمر التوريد غير موجود' using errcode='P0002'; end if;
  select * into bill from public.supplier_bills
   where id=p_supplier_bill_id and supplier_id=o.supplier_id
     and (purchase_order_id is null or purchase_order_id=p_purchase_order_id)
   for update;
  if not found then raise exception 'فاتورة المورد غير مرتبطة بهذا المورد أو أمر التوريد' using errcode='23503'; end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>20 then
    raise exception 'حدد وحدات فعلية لإرجاعها للمورد' using errcode='22023';
  end if;

  select array_agg(u.value)
    into ids
    from jsonb_array_elements(p_items) p,
         jsonb_array_elements_text(p.value->'unit_ids') u(value);
  if coalesce(cardinality(ids),0)<1
     or cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then
    raise exception 'اختر أرقام شاسيه مختلفة لكل وحدة مرتجعة' using errcode='22023';
  end if;

  insert into public.supplier_returns(
    supplier_id,purchase_order_id,supplier_bill_id,notes,created_by
  ) values(o.supplier_id,p_purchase_order_id,p_supplier_bill_id,
    nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()))
  returning id,return_number into return_id,return_number;

  for item in select value from jsonb_array_elements(p_items) x(value) loop
    begin
      select * into receipt_item
        from public.purchase_receipt_items
       where id=(item->>'purchase_receipt_item_id')::uuid
       for update;
    exception when invalid_text_representation then
      raise exception 'بند الاستلام المحدد غير صالح' using errcode='22023';
    end;
    if not found or not exists(
      select 1 from public.purchase_receipts pr
       where pr.id=receipt_item.receipt_id and pr.purchase_order_id=p_purchase_order_id
    ) then
      raise exception 'بند الاستلام غير تابع لأمر التوريد المحدد' using errcode='P0002';
    end if;
    if jsonb_typeof(item->'unit_ids') is distinct from 'array'
       or jsonb_array_length(item->'unit_ids')<1 then
      raise exception 'حدد أرقام الشاسيه للوحدات المراد إرجاعها' using errcode='22023';
    end if;
    qty:=jsonb_array_length(item->'unit_ids');
    select coalesce(sum(sri.quantity),0)::integer into already_returned
      from public.supplier_return_items sri
     where sri.purchase_receipt_item_id=receipt_item.id;
    if qty>receipt_item.quantity-already_returned then
      raise exception 'عدد الوحدات المرتجعة يتجاوز الوحدات المستلمة المتبقية' using errcode='23514';
    end if;

    insert into public.supplier_return_items(
      supplier_return_id,purchase_receipt_item_id,motorcycle_id,quantity,unit_cost
    ) values(return_id,receipt_item.id,receipt_item.motorcycle_id,qty,receipt_item.unit_cost)
    returning id into return_item_id;

    for unit_value in select value from jsonb_array_elements_text(item->'unit_ids') loop
      begin unit_id:=unit_value::uuid;
      exception when others then raise exception 'معرّف وحدة مرتجعة غير صالح' using errcode='22023'; end;
      select u.* into unit_row
        from public.motorcycle_units u
        join public.purchase_receipt_units pru on pru.motorcycle_unit_id=u.id
       where u.id=unit_id
         and pru.receipt_item_id=receipt_item.id
         and u.motorcycle_id=receipt_item.motorcycle_id
         and u.unit_status='available'
       for update of u;
      if not found then
        raise exception 'إحدى الوحدات المحددة لا تتبع بند الاستلام أو لم تعد متاحة' using errcode='23514';
      end if;
      insert into public.supplier_return_units(
        supplier_return_item_id,motorcycle_unit_id,unit_cost
      ) values(return_item_id,unit_id,receipt_item.unit_cost);
      update public.motorcycle_units set unit_status='retired' where id=unit_id;
    end loop;

    perform set_config('ekm.stock_movement_source','purchase_return',true);
    perform set_config('ekm.stock_movement_reference',return_id::text,true);
    update public.motorcycles set stock=stock-qty
     where id=receipt_item.motorcycle_id and stock>=qty;
    if not found then
      raise exception 'الرصيد المسجل لا يكفي لإرجاع الوحدات المحددة للمورد' using errcode='23514';
    end if;
    perform set_config('ekm.stock_movement_source','',true);
    perform set_config('ekm.stock_movement_reference','',true);

    total_credit:=total_credit+(qty*receipt_item.unit_cost);
    item_count:=item_count+1;
  end loop;

  select coalesce(sum(sri.line_total),0) into existing_credit
    from public.supplier_return_items sri
    join public.supplier_returns sr on sr.id=sri.supplier_return_id
   where sr.supplier_bill_id=p_supplier_bill_id and sr.id<>return_id;
  if existing_credit+total_credit>bill.total_amount then
    raise exception 'إجمالي إشعارات الخصم يتجاوز قيمة فاتورة المورد' using errcode='23514';
  end if;
  return jsonb_build_object(
    'id',return_id,'return_number',return_number,
    'items_count',item_count,'credit_amount',round(total_credit,2)
  );
end;
$$;
revoke all on function private.create_supplier_return_for_units_impl(uuid,uuid,jsonb,text) from public,anon;
grant execute on function private.create_supplier_return_for_units_impl(uuid,uuid,jsonb,text) to authenticated;

create or replace function public.create_supplier_return_for_units(
  p_purchase_order_id uuid,p_supplier_bill_id uuid,p_items jsonb,p_notes text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select private.create_supplier_return_for_units_impl($1,$2,$3,$4);
$$;
revoke all on function public.create_supplier_return_for_units(uuid,uuid,jsonb,text) from public,anon;
grant execute on function public.create_supplier_return_for_units(uuid,uuid,jsonb,text) to authenticated;

revoke all on function public.create_supplier_return(uuid,uuid,jsonb,text) from public,anon,authenticated;

commit;
