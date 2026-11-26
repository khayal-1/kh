-- Preserve the existing unit-edit RPC for old clients while adding a scoped,
-- authenticated path to update unit-level year/color on this unit only.
begin;

create or replace function private.update_motorcycle_unit_details_with_attributes_impl(
  p_unit_id uuid,
  p_unit_year smallint,
  p_unit_color text,
  p_vin text,
  p_engine_number text,
  p_barcode text,
  p_unit_status text,
  p_odometer_reading integer,
  p_unit_condition text,
  p_warranty_start date,
  p_warranty_end date,
  p_notes text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_unit public.motorcycle_units%rowtype;
  v_vin text := regexp_replace(upper(btrim(coalesce(p_vin,''))), '\s+', '', 'g');
  v_engine text := nullif(regexp_replace(upper(btrim(coalesce(p_engine_number,''))), '\s+', '', 'g'),'');
  v_stock integer;
begin
  if (select auth.uid()) is null
     or (not private.can_manage_finance() and not public.has_employee_permission('catalog_manage')) then
    raise exception 'غير مصرح بتعديل بيانات الوحدة' using errcode='42501';
  end if;
  if p_unit_id is null or v_vin=''
     or p_unit_status not in ('available','reserved','sold','service','retired')
     or p_odometer_reading is null or p_odometer_reading<0
     or coalesce(p_unit_condition,'') not in ('new','used')
     or (p_unit_year is not null and p_unit_year not between 1900 and 2200)
     or (p_unit_color is not null and length(btrim(p_unit_color))>60)
     or (p_warranty_end is not null and p_warranty_start is not null and p_warranty_end<p_warranty_start) then
    raise exception 'بيانات الوحدة غير صحيحة' using errcode='22023';
  end if;

  select * into v_unit
    from public.motorcycle_units
   where id=p_unit_id
   for update;
  if not found then
    raise exception 'الوحدة غير موجودة' using errcode='P0002';
  end if;
  if v_unit.sale_item_id is not null and p_unit_status<>'sold' then
    raise exception 'لا يمكن تغيير حالة وحدة مرتبطة بفاتورة بيع' using errcode='23514';
  end if;
  if p_unit_status='sold' and v_unit.sale_item_id is null then
    raise exception 'لا يمكن تعيين حالة مباع دون ربط الوحدة بعنصر فاتورة' using errcode='23514';
  end if;

  update public.motorcycle_units
     set unit_year=p_unit_year,
         unit_color=nullif(btrim(coalesce(p_unit_color,'')),''),
         vin=v_vin,
         engine_number=v_engine,
         barcode=nullif(btrim(coalesce(p_barcode,'')),''),
         unit_status=p_unit_status,
         is_published=case when p_unit_status='available' then is_published else false end,
         odometer_reading=p_odometer_reading,
         unit_condition=p_unit_condition,
         warranty_start=p_warranty_start,
         warranty_end=p_warranty_end,
         notes=nullif(btrim(coalesce(p_notes,'')),'')
   where id=p_unit_id;

  select count(*)::integer into v_stock
    from public.motorcycle_units
   where motorcycle_id=v_unit.motorcycle_id
     and unit_status in ('available','reserved','service');
  perform pg_catalog.set_config('ekm.stock_movement_source','stocktake',true);
  update public.motorcycles
     set stock=v_stock
   where id=v_unit.motorcycle_id
     and stock is distinct from v_stock;
end;
$function$;

revoke all on function private.update_motorcycle_unit_details_with_attributes_impl(uuid,smallint,text,text,text,text,text,integer,text,date,date,text) from public,anon,authenticated;
grant execute on function private.update_motorcycle_unit_details_with_attributes_impl(uuid,smallint,text,text,text,text,text,integer,text,date,date,text) to authenticated;

create or replace function public.update_motorcycle_unit_details_with_attributes(
  p_unit_id uuid,
  p_unit_year smallint,
  p_unit_color text,
  p_vin text,
  p_engine_number text,
  p_barcode text,
  p_unit_status text,
  p_odometer_reading integer,
  p_unit_condition text,
  p_warranty_start date default null,
  p_warranty_end date default null,
  p_notes text default null
)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.update_motorcycle_unit_details_with_attributes_impl(
    $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12
  );
$function$;
revoke all on function public.update_motorcycle_unit_details_with_attributes(uuid,smallint,text,text,text,text,text,integer,text,date,date,text) from public,anon;
grant execute on function public.update_motorcycle_unit_details_with_attributes(uuid,smallint,text,text,text,text,text,integer,text,date,date,text) to authenticated;

commit;
