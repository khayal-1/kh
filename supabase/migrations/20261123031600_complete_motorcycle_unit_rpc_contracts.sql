begin;

-- Complete the unit schema consumed by the application. Keep VIN/engine identity
-- on the physical unit, not on the motorcycle model.
alter table public.motorcycle_units
  add column if not exists engine_number text,
  add column if not exists odometer_reading integer not null default 0,
  add column if not exists unit_condition text not null default 'new',
  add column if not exists is_demo boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.motorcycle_units'::regclass
      and conname='motorcycle_units_odometer_nonnegative'
  ) then
    alter table public.motorcycle_units
      add constraint motorcycle_units_odometer_nonnegative
      check (odometer_reading >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.motorcycle_units'::regclass
      and conname='motorcycle_units_condition_check'
  ) then
    alter table public.motorcycle_units
      add constraint motorcycle_units_condition_check
      check (unit_condition in ('new','used'));
  end if;
end $$;

-- Treat differences in letter case and whitespace as the same identifier.
-- If legacy rows conflict, fail the migration rather than silently merging units.
do $$
begin
  if exists (
    select 1 from public.motorcycle_units
    where nullif(regexp_replace(upper(btrim(vin)), '\s+', '', 'g'),'') is not null
    group by regexp_replace(upper(btrim(vin)), '\s+', '', 'g')
    having count(*) > 1
  ) then
    raise exception 'Duplicate VIN values exist after case/whitespace normalization; reconcile them before applying this migration.';
  end if;
  if exists (
    select 1 from public.motorcycle_units
    where nullif(regexp_replace(upper(btrim(engine_number)), '\s+', '', 'g'),'') is not null
    group by regexp_replace(upper(btrim(engine_number)), '\s+', '', 'g')
    having count(*) > 1
  ) then
    raise exception 'Duplicate engine numbers exist after case/whitespace normalization; reconcile them before applying this migration.';
  end if;
end $$;

create unique index if not exists motorcycle_units_vin_normalized_uidx
  on public.motorcycle_units (regexp_replace(upper(btrim(vin)), '\s+', '', 'g'));
create unique index if not exists motorcycle_units_engine_normalized_uidx
  on public.motorcycle_units (regexp_replace(upper(btrim(engine_number)), '\s+', '', 'g'))
  where nullif(btrim(engine_number),'') is not null;

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
set search_path=''
as $$
declare
  v_id uuid;
  v_stock integer;
  v_registered integer;
  v_vin text := regexp_replace(upper(btrim(coalesce(p_vin,''))), '\s+', '', 'g');
  v_engine text := nullif(regexp_replace(upper(btrim(coalesce(p_engine_number,''))), '\s+', '', 'g'),'');
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

  select stock into v_stock
  from public.motorcycles
  where id=p_motorcycle_id
  for update;
  if not found then
    raise exception 'نوع الدراجة غير موجود' using errcode='P0002';
  end if;

  select count(*) into v_registered
  from public.motorcycle_units
  where motorcycle_id=p_motorcycle_id
    and unit_status in ('available','reserved','service');
  if v_registered>=v_stock then
    raise exception 'عدد الوحدات المسجلة وصل إلى كمية المخزون؛ راجع الاستلام والجرد أولاً' using errcode='23514';
  end if;

  insert into public.motorcycle_units(
    motorcycle_id,vin,engine_number,barcode,odometer_reading,unit_condition,
    warranty_start,warranty_end,notes,registered_by
  ) values (
    p_motorcycle_id,v_vin,v_engine,v_barcode,p_odometer_reading,p_unit_condition,
    p_warranty_start,p_warranty_end,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())
  )
  returning id into v_id;
  return v_id;
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
set search_path=''
as $$
declare
  v_unit public.motorcycle_units%rowtype;
  v_vin text := regexp_replace(upper(btrim(coalesce(p_vin,''))), '\s+', '', 'g');
  v_engine text := nullif(regexp_replace(upper(btrim(coalesce(p_engine_number,''))), '\s+', '', 'g'),'');
begin
  if (select auth.uid()) is null
     or (not private.can_manage_finance() and not public.has_employee_permission('catalog_manage')) then
    raise exception 'غير مصرح بتعديل بيانات الوحدة' using errcode='42501';
  end if;
  if p_unit_id is null or v_vin=''
     or p_unit_status not in ('available','reserved','sold','service')
     or p_odometer_reading is null or p_odometer_reading<0
     or coalesce(p_unit_condition,'') not in ('new','used')
     or (p_warranty_end is not null and p_warranty_start is not null and p_warranty_end<p_warranty_start) then
    raise exception 'بيانات الوحدة غير صحيحة' using errcode='22023';
  end if;

  select * into v_unit from public.motorcycle_units where id=p_unit_id for update;
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
      odometer_reading=p_odometer_reading,
      unit_condition=p_unit_condition,
      warranty_start=p_warranty_start,
      warranty_end=p_warranty_end,
      notes=nullif(btrim(coalesce(p_notes,'')),'')
  where id=p_unit_id;
end;
$$;

create or replace function public.register_motorcycle_unit_with_engine_number(
  p_motorcycle_id uuid,p_vin text,p_engine_number text,p_barcode text default null,
  p_warranty_start date default null,p_warranty_end date default null,p_notes text default null,
  p_odometer_reading integer default 0,p_unit_condition text default 'new'
)
returns uuid
language sql
security invoker
set search_path=''
as $$
  select private.register_motorcycle_unit_with_engine_number(
    $1,$2,$3,$4,$5,$6,$7,$8,$9
  );
$$;

create or replace function public.update_motorcycle_unit_details(
  p_unit_id uuid,p_vin text,p_engine_number text,p_barcode text,p_unit_status text,
  p_odometer_reading integer,p_unit_condition text,p_warranty_start date default null,
  p_warranty_end date default null,p_notes text default null
)
returns void
language sql
security invoker
set search_path=''
as $$
  select private.update_motorcycle_unit_details($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);
$$;

-- This RPC exposes only non-demo, available unit identifiers needed by the public
-- catalogue; it never returns VIN, engine number, cost, warranty, or customer data.
create or replace function public.get_store_motorcycle_units()
returns table(unit_id uuid,motorcycle_id uuid,unit_condition text)
language sql
stable
security definer
set search_path=''
as $$
  select u.id,u.motorcycle_id,u.unit_condition
  from public.motorcycle_units u
  join public.motorcycles m on m.id=u.motorcycle_id
  where u.unit_status='available'
    and not u.is_demo
    and m.status='available'
    and not coalesce(m.is_demo,false)
  order by u.registered_at,u.id;
$$;

revoke all on function private.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text) from public,anon,authenticated;
revoke all on function private.update_motorcycle_unit_details(uuid,text,text,text,text,integer,text,date,date,text) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text) to authenticated;
grant execute on function private.update_motorcycle_unit_details(uuid,text,text,text,text,integer,text,date,date,text) to authenticated;

revoke all on function public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text) from public,anon;
grant execute on function public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text) to authenticated;
revoke all on function public.update_motorcycle_unit_details(uuid,text,text,text,text,integer,text,date,date,text) from public,anon;
grant execute on function public.update_motorcycle_unit_details(uuid,text,text,text,text,integer,text,date,date,text) to authenticated;
revoke all on function public.get_store_motorcycle_units() from public;
grant execute on function public.get_store_motorcycle_units() to anon,authenticated;

commit;
