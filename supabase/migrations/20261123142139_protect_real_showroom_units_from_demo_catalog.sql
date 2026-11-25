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
  v_model_is_demo boolean;
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

  select is_demo into v_model_is_demo
    from public.motorcycles
   where id=p_motorcycle_id
   for update;
  if not found then
    raise exception 'نوع الدراجة غير موجود' using errcode='P0002';
  end if;
  if coalesce(v_model_is_demo,false) then
    raise exception 'هذا نوع تجريبي؛ أنشئ نوعًا فعليًا قبل تسجيل مخزون المعرض عليه' using errcode='23514';
  end if;

  insert into public.motorcycle_units(
    motorcycle_id,vin,engine_number,barcode,odometer_reading,unit_condition,
    warranty_start,warranty_end,notes,registered_by
  ) values (
    p_motorcycle_id,v_vin,v_engine,v_barcode,p_odometer_reading,p_unit_condition,
    p_warranty_start,p_warranty_end,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())
  )
  returning id into v_id;

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

create or replace function private.set_motorcycle_unit_store_visibility_impl(
  p_unit_id uuid,
  p_is_published boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_unit public.motorcycle_units%rowtype;
  v_model_is_demo boolean;
begin
  if (select auth.uid()) is null
     or not (
       public.has_any_role(array['admin'::public.app_role,'manager'::public.app_role,'owner'::public.app_role])
       or public.has_employee_permission('catalog_manage')
     ) then
    raise exception 'غير مصرح بإدارة عرض الدراجات في المتجر' using errcode='42501';
  end if;
  if p_unit_id is null or p_is_published is null then
    raise exception 'بيانات النشر غير مكتملة' using errcode='22023';
  end if;

  select * into v_unit
    from public.motorcycle_units
   where id=p_unit_id
   for update;
  if not found then
    raise exception 'الوحدة غير موجودة' using errcode='P0002';
  end if;

  select is_demo into v_model_is_demo
    from public.motorcycles
   where id=v_unit.motorcycle_id
   for update;

  if p_is_published then
    if v_unit.is_demo or coalesce(v_model_is_demo,false)
       or v_unit.sale_item_id is not null
       or v_unit.unit_status not in ('available','retired') then
      raise exception 'لا يمكن نشر هذه الوحدة؛ يجب أن تكون وحدة فعلية غير مباعة وغير محجوزة أو تحت الصيانة' using errcode='23514';
    end if;
    update public.motorcycle_units
       set unit_status='available', is_published=true
     where id=p_unit_id;
    update public.motorcycles
       set status='available'
     where id=v_unit.motorcycle_id;
    perform pg_catalog.set_config('ekm.stock_movement_source','stocktake',true);
    update public.motorcycles m
       set stock=(select count(*)::integer from public.motorcycle_units u
                   where u.motorcycle_id=m.id
                     and u.unit_status in ('available','reserved','service'))
     where m.id=v_unit.motorcycle_id
       and m.stock is distinct from (
         select count(*)::integer from public.motorcycle_units u
          where u.motorcycle_id=m.id
            and u.unit_status in ('available','reserved','service')
       );
  else
    update public.motorcycle_units
       set is_published=false
     where id=p_unit_id;
  end if;
end;
$function$;

revoke all on function private.set_motorcycle_unit_store_visibility_impl(uuid,boolean) from public, anon, authenticated;
grant execute on function private.set_motorcycle_unit_store_visibility_impl(uuid,boolean) to authenticated;
revoke all on function private.delete_motorcycle_unit_impl(uuid) from public, anon, authenticated;
grant execute on function private.delete_motorcycle_unit_impl(uuid) to authenticated;
