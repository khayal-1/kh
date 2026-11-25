alter table public.motorcycle_units
  add column if not exists is_published boolean not null default false;

update public.motorcycle_units u
set is_published = true
from public.motorcycles m
where m.id = u.motorcycle_id
  and u.unit_status = 'available'
  and not u.is_demo
  and not coalesce(m.is_demo,false)
  and m.status = 'available';

-- Reconcile real models against their physical, active VIN units.
do $$
begin
  perform pg_catalog.set_config('ekm.stock_movement_source','stocktake',true);
  update public.motorcycles m
     set stock = (
       select count(*)::integer
       from public.motorcycle_units u
       where u.motorcycle_id = m.id
         and u.unit_status in ('available','reserved','service')
     )
   where not coalesce(m.is_demo,false)
     and m.stock is distinct from (
       select count(*)::integer
       from public.motorcycle_units u
       where u.motorcycle_id = m.id
         and u.unit_status in ('available','reserved','service')
     );
end;
$$;

create or replace function private.update_motorcycle_unit_details(
  p_unit_id uuid,
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
     set vin=v_vin,
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

  if p_is_published then
    if v_unit.is_demo or v_unit.sale_item_id is not null
       or v_unit.unit_status not in ('available','retired') then
      raise exception 'لا يمكن نشر هذه الوحدة؛ يجب أن تكون وحدة فعلية غير مباعة وغير محجوزة أو تحت الصيانة' using errcode='23514';
    end if;
    update public.motorcycle_units
       set unit_status='available', is_published=true
     where id=p_unit_id;
    update public.motorcycles
       set status='available'
     where id=v_unit.motorcycle_id
       and not coalesce(is_demo,false);
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

create or replace function public.set_motorcycle_unit_store_visibility(
  p_unit_id uuid,
  p_is_published boolean
)
returns void
language sql
set search_path = ''
as $function$
  select private.set_motorcycle_unit_store_visibility_impl($1,$2);
$function$;

create or replace function private.delete_motorcycle_unit_impl(p_unit_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_unit public.motorcycle_units%rowtype;
  v_stock integer;
begin
  if (select auth.uid()) is null
     or not (
       public.has_any_role(array['admin'::public.app_role,'manager'::public.app_role,'owner'::public.app_role])
       or public.has_employee_permission('catalog_manage')
     ) then
    raise exception 'غير مصرح بحذف سجل الوحدة' using errcode='42501';
  end if;
  if p_unit_id is null then
    raise exception 'حدد الوحدة المطلوب حذفها' using errcode='22023';
  end if;

  select * into v_unit
    from public.motorcycle_units
   where id=p_unit_id
   for update;
  if not found then
    raise exception 'الوحدة غير موجودة' using errcode='P0002';
  end if;
  if v_unit.sale_item_id is not null or v_unit.unit_status='sold' then
    raise exception 'لا يمكن حذف وحدة مرتبطة بفاتورة بيع؛ استخدم إجراءات المرتجعات أو التصحيح المحاسبي' using errcode='23514';
  end if;

  begin
    delete from public.motorcycle_units where id=p_unit_id;
  exception when foreign_key_violation then
    raise exception 'لا يمكن حذف هذه الوحدة لأنها مرتبطة باستلام مشتريات أو فاتورة مورد أو مرتجع أو أمر صيانة. احتفظ بالسجل وصحح حالته بدلاً من حذفه.' using errcode='23503';
  end;

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

create or replace function public.delete_motorcycle_unit(p_unit_id uuid)
returns void
language sql
set search_path = ''
as $function$
  select private.delete_motorcycle_unit_impl($1);
$function$;

create or replace function public.get_store_motorcycle_units()
returns table(unit_id uuid, motorcycle_id uuid, unit_condition text)
language sql
stable
security definer
set search_path = ''
as $function$
  select u.id,u.motorcycle_id,u.unit_condition
    from public.motorcycle_units u
    join public.motorcycles m on m.id=u.motorcycle_id
   where u.unit_status='available'
     and u.is_published
     and not u.is_demo
     and m.status='available'
     and not coalesce(m.is_demo,false)
   order by u.registered_at,u.id;
$function$;

revoke all on function public.set_motorcycle_unit_store_visibility(uuid,boolean) from public, anon, authenticated;
grant execute on function public.set_motorcycle_unit_store_visibility(uuid,boolean) to authenticated;
revoke all on function public.delete_motorcycle_unit(uuid) from public, anon, authenticated;
grant execute on function public.delete_motorcycle_unit(uuid) to authenticated;
grant usage on schema private to authenticated;
grant execute on function private.set_motorcycle_unit_store_visibility_impl(uuid,boolean) to authenticated;
grant execute on function private.delete_motorcycle_unit_impl(uuid) to authenticated;
