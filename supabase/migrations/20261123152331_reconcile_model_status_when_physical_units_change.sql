create or replace function private.sync_motorcycle_store_status_from_unit(p_motorcycle_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status public.motorcycle_status;
begin
  if p_motorcycle_id is null then
    return;
  end if;

  select case
    when exists (
      select 1 from public.motorcycle_units u
       where u.motorcycle_id = p_motorcycle_id
         and u.unit_status = 'available'
         and not coalesce(u.is_demo, false)
    ) then 'available'::public.motorcycle_status
    when exists (
      select 1 from public.motorcycle_units u
       where u.motorcycle_id = p_motorcycle_id
         and u.unit_status = 'reserved'
         and not coalesce(u.is_demo, false)
    ) then 'reserved'::public.motorcycle_status
    when exists (
      select 1 from public.motorcycle_units u
       where u.motorcycle_id = p_motorcycle_id
         and u.unit_status = 'sold'
         and not coalesce(u.is_demo, false)
    )
    and not exists (
      select 1 from public.motorcycle_units u
       where u.motorcycle_id = p_motorcycle_id
         and u.unit_status <> 'sold'
         and not coalesce(u.is_demo, false)
    ) then 'sold'::public.motorcycle_status
    else 'unavailable'::public.motorcycle_status
  end into v_status;

  update public.motorcycles m
     set status = v_status
   where m.id = p_motorcycle_id
     and not coalesce(m.is_demo, false)
     and m.status is distinct from 'draft'::public.motorcycle_status
     and m.status is distinct from v_status;
end;
$function$;

revoke all on function private.sync_motorcycle_store_status_from_unit(uuid) from public, anon, authenticated;
