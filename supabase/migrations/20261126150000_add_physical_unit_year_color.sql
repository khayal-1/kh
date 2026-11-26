-- Add physical-unit attributes without changing model-level catalog data.
-- Existing rows remain valid; the fields are optional for legacy stock.
alter table public.motorcycle_units
  add column if not exists unit_year smallint,
  add column if not exists unit_color text;

do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.motorcycle_units'::regclass and conname='motorcycle_units_unit_year_range') then
    alter table public.motorcycle_units add constraint motorcycle_units_unit_year_range
      check (unit_year is null or unit_year between 1900 and 2200) not valid;
  end if;
end $$;

create or replace function private.receive_supplier_purchase_order_units_impl(
  p_order_id uuid,
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
  poi public.purchase_order_items%rowtype;
  item jsonb;
  unit jsonb;
  receipt_id uuid;
  receipt_number text;
  receipt_item_id uuid;
  unit_id uuid;
  qty integer;
  total_qty integer:=0;
  all_received boolean;
  vin_value text;
  engine_value text;
  condition_value text;
  unit_cost_value numeric(14,2);
begin
  if (select auth.uid()) is null or not public.can_manage_purchasing() then
    raise exception 'ليس لديك صلاحية استلام التوريد' using errcode='42501';
  end if;
  select * into o from public.purchase_orders where id=p_order_id for update;
  if not found or o.status='cancelled' or o.status='received' then
    raise exception 'أمر التوريد غير موجود أو مغلق' using errcode='P0002';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>20 then
    raise exception 'يجب تحديد بند واحد على الأقل للاستلام' using errcode='22023';
  end if;

  receipt_number:='GR-'||to_char(now(),'YYYYMMDD')||'-'||
    lpad(nextval('public.supplier_receipt_number_seq')::text,6,'0');
  insert into public.purchase_receipts(receipt_number,purchase_order_id,received_by,notes)
  values(receipt_number,p_order_id,(select auth.uid()),nullif(btrim(coalesce(p_notes,'')),''))
  returning id into receipt_id;

  perform set_config('ekm.stock_movement_source','purchase_receipt',true);
  perform set_config('ekm.stock_movement_reference',receipt_id::text,true);

  for item in select value from jsonb_array_elements(p_items) as x(value) loop
    begin
      select * into poi from public.purchase_order_items
       where id=(item->>'purchase_order_item_id')::uuid
         and purchase_order_id=p_order_id for update;
    exception when invalid_text_representation then
      raise exception 'بند أمر الشراء غير صالح' using errcode='22023';
    end;
    if not found then
      raise exception 'بند التوريد غير تابع لأمر الشراء' using errcode='P0002';
    end if;
    if jsonb_typeof(item->'units') is distinct from 'array'
       or jsonb_array_length(item->'units')<1 then
      raise exception 'أدخل بيانات كل وحدة مستلمة ورقم شاسيهها' using errcode='22023';
    end if;
    qty:=jsonb_array_length(item->'units');
    if qty>poi.quantity_ordered-poi.quantity_received then
      raise exception 'عدد الوحدات المستلمة أكبر من الكمية المتبقية في أمر الشراء' using errcode='23514';
    end if;
    unit_cost_value:=poi.unit_cost;
    insert into public.purchase_receipt_items(
      receipt_id,purchase_order_item_id,motorcycle_id,quantity,unit_cost
    ) values(receipt_id,poi.id,poi.motorcycle_id,qty,unit_cost_value)
    returning id into receipt_item_id;

    for unit in select value from jsonb_array_elements(item->'units') as x(value) loop
      vin_value:=regexp_replace(upper(btrim(coalesce(unit->>'vin',''))),'\s+','','g');
      engine_value:=nullif(regexp_replace(upper(btrim(coalesce(unit->>'engine_number',''))),'\s+','','g'),'');
      condition_value:=coalesce(unit->>'unit_condition','new');
      if vin_value='' or condition_value not in ('new','used')
         or coalesce((unit->>'odometer_reading')::integer,0)<0 then
        raise exception 'رقم الشاسيه أو بيانات الوحدة غير صحيحة' using errcode='22023';
      end if;
      insert into public.motorcycle_units(
        motorcycle_id,vin,engine_number,barcode,unit_status,unit_cost,
        odometer_reading,unit_condition,warranty_start,warranty_end,notes,registered_by,
        unit_year,unit_color
      ) values (
        poi.motorcycle_id,vin_value,engine_value,
        nullif(btrim(coalesce(unit->>'barcode','')),''),'available',unit_cost_value,
        coalesce((unit->>'odometer_reading')::integer,0),condition_value,
        nullif(unit->>'warranty_start','')::date,nullif(unit->>'warranty_end','')::date,
        nullif(btrim(coalesce(unit->>'notes','')),''),(select auth.uid()),
        nullif(unit->>'unit_year','')::smallint,
        nullif(btrim(coalesce(unit->>'unit_color','')),'')
      ) returning id into unit_id;
      insert into public.purchase_receipt_units(
        receipt_id,receipt_item_id,purchase_order_item_id,motorcycle_unit_id,unit_cost
      ) values(receipt_id,receipt_item_id,poi.id,unit_id,unit_cost_value);
    end loop;

    update public.purchase_order_items
       set quantity_received=quantity_received+qty
     where id=poi.id;
    update public.motorcycles set stock=stock+qty where id=poi.motorcycle_id;
    total_qty:=total_qty+qty;
  end loop;

  select bool_and(quantity_received=quantity_ordered) into all_received
    from public.purchase_order_items where purchase_order_id=p_order_id;
  update public.purchase_orders
     set status=case when all_received then 'received' else 'partially_received' end,
         updated_at=now()
   where id=p_order_id;

  return jsonb_build_object(
    'receipt_id',receipt_id,'receipt_number',receipt_number,
    'quantity_received',total_qty,
    'status',case when all_received then 'received' else 'partially_received' end
  );
end;
$$;
-- Wrapper remains the same signature, permissions and transaction boundary.
