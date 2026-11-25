create or replace function public.has_public_store_units(p_motorcycle_id uuid)
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

revoke all on function public.has_public_store_units(uuid) from public;
grant execute on function public.has_public_store_units(uuid) to anon, authenticated;

drop policy if exists catalog_anon_read_available on public.motorcycles;
create policy catalog_anon_read_available
on public.motorcycles
for select
to anon
using (
  not coalesce(is_demo, false)
  and public.has_public_store_units(id)
);

drop policy if exists catalog_authenticated_read on public.motorcycles;
create policy catalog_authenticated_read
on public.motorcycles
for select
to authenticated
using (
  (
    not coalesce(is_demo, false)
    and public.has_public_store_units(id)
  )
  or public.has_any_role(array['employee'::public.app_role, 'manager'::public.app_role, 'owner'::public.app_role, 'admin'::public.app_role])
  or public.has_employee_permission('catalog_view')
  or public.has_employee_permission('catalog_manage')
);

create or replace function public.get_store_motorcycle_units()
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

update public.motorcycle_units
set is_published = true
where not coalesce(is_demo, false);
