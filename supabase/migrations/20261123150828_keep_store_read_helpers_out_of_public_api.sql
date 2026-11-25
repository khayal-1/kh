drop policy if exists catalog_anon_read_available on public.motorcycles;
drop policy if exists catalog_authenticated_read on public.motorcycles;

create or replace function private.has_public_store_units(p_motorcycle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.motorcycle_units u
    where u.motorcycle_id = p_motorcycle_id
      and u.unit_status = 'available'
      and not coalesce(u.is_demo, false)
  );
$function$;

create or replace function private.get_store_motorcycle_units_impl()
returns table(unit_id uuid, motorcycle_id uuid, unit_condition text)
language sql
stable
security definer
set search_path = ''
as $function$
  select u.id, u.motorcycle_id, u.unit_condition
  from public.motorcycle_units u
  join public.motorcycles m on m.id = u.motorcycle_id
  where u.unit_status = 'available'
    and not coalesce(u.is_demo, false)
    and not coalesce(m.is_demo, false)
  order by u.registered_at, u.id;
$function$;

revoke all on function private.has_public_store_units(uuid) from public;
revoke all on function private.get_store_motorcycle_units_impl() from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.has_public_store_units(uuid) to anon, authenticated;
grant execute on function private.get_store_motorcycle_units_impl() to anon, authenticated;

drop function if exists public.has_public_store_units(uuid);

create or replace function public.get_store_motorcycle_units()
returns table(unit_id uuid, motorcycle_id uuid, unit_condition text)
language sql
stable
set search_path = ''
as $function$
  select * from private.get_store_motorcycle_units_impl();
$function$;

create policy catalog_anon_read_available
on public.motorcycles
for select
to anon
using (
  not coalesce(is_demo, false)
  and private.has_public_store_units(id)
);

create policy catalog_authenticated_read
on public.motorcycles
for select
to authenticated
using (
  (
    not coalesce(is_demo, false)
    and private.has_public_store_units(id)
  )
  or public.has_any_role(array['employee'::public.app_role, 'manager'::public.app_role, 'owner'::public.app_role, 'admin'::public.app_role])
  or public.has_employee_permission('catalog_view')
  or public.has_employee_permission('catalog_manage')
);
