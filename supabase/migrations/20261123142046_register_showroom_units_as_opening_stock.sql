create or replace function private.register_motorcycle_unit_with_engine_number(
  p_motorcycle_id uuid,
  p_vin text,
  p_engine_number text,
  p_barcode text default null,
  p_warranty_start date default null,
  p_warranty_end date default null,
  p_notes text default null,
  p_odometer_reading integer default 0,
  p_unit_condition text default 'new'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
  v_stock integer;
  v_vin text := regexp_replace(upper(btrim(coalesce(p_vin,''))), '[[:space:]]+', '', 'g');
  v_engine text := nullif(regexp_replace(upper(btrim(coalesce(p_engine_number,''))), '[[:space:]]+', '', 'g'),'');
  v_barcode text := nullif(btrim(coalesce(p_barcode,'')),'');
begin
  if (select auth.uid()) is null
     or (not private.can_manage_finance() and not public.has_employee_permission('catalog_manage')) then
    raise exception 'غير مصرح بتسجيل بيانات الوحدة' using errcode='42501';
  end if;
  if p_motorcycle_id is null or v_vin=''
     or p_odometer_reading is null or p_odometer_reading<0
     or coalesce(p_unit_condition,'') not in ('new','used')
     or (p_warranty_end is not null and p_warranty_start is not null and p_warranty_end<p_warranty_start) then
    raise exception 'بيانات الوحدة غير صحيحة' using errcode='22023';
  end if;

  perform 1
    from public.motorcycles
   where id=p_motorcycle_id
   for update;
  if not found then
    raise exception 'نوع الدراجة غير موجود' using errcode='P0002';
  end if;

  insert into public.motorcycle_units(
    motorcycle_id,vin,engine_number,barcode,odometer_reading,unit_condition,
    warranty_start,warranty_end,notes,registered_by
  ) values (
    p_motorcycle_id,v_vin,v_engine,v_barcode,p_odometer_reading,p_unit_condition,
    p_warranty_start,p_warranty_end,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())
  )
  returning id into v_id;

  -- Registering a physically present VIN is an audited opening-stock adjustment.
  select count(*)::integer into v_stock
    from public.motorcycle_units
   where motorcycle_id=p_motorcycle_id
     and unit_status in ('available','reserved','service');
  perform pg_catalog.set_config('ekm.stock_movement_source','stocktake',true);
  update public.motorcycles
     set stock=v_stock
   where id=p_motorcycle_id
     and stock is distinct from v_stock;

  return v_id;
end;
$function$;