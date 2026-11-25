-- Respect both model-level publication and unit-level publication in the public storefront.
-- Archiving a model hides it without deleting sales, units, or inventory history.
create or replace function private.get_store_motorcycle_units_impl()
returns table(unit_id uuid, motorcycle_id uuid, unit_condition text)
language sql
stable
security definer
set search_path = ''
as $function$
  select u.id, u.motorcycle_id, u.unit_condition
  from public.motorcycle_units as u
  join public.motorcycles as m on m.id = u.motorcycle_id
  where u.unit_status = 'available'
    and u.is_published = true
    and m.status = 'available'
    and not coalesce(u.is_demo, false)
    and not coalesce(m.is_demo, false)
  order by u.registered_at, u.id;
$function$;
