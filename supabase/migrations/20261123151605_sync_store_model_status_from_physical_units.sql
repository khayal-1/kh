create or replace function private.sync_motorcycle_store_status_from_unit(p_motorcycle_id uuid)
returns void
language sql
security definer
set search_path = ''
as $function$
  update public.motorcycles m
     set status = 'available'::public.motorcycle_status
   where m.id = p_motorcycle_id
     and not coalesce(m.is_demo, false)
     and m.status is distinct from 'available'::public.motorcycle_status
     and exists (
       select 1
         from public.motorcycle_units u
        where u.motorcycle_id = m.id
          and u.unit_status = 'available'
          and not coalesce(u.is_demo, false)
     );
$function$;

create or replace function private.sync_motorcycle_store_status_after_unit_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    perform private.sync_motorcycle_store_status_from_unit(old.motorcycle_id);
    return old;
  end if;

  if tg_op = 'UPDATE'
     and old.motorcycle_id is distinct from new.motorcycle_id then
    perform private.sync_motorcycle_store_status_from_unit(old.motorcycle_id);
  end if;

  perform private.sync_motorcycle_store_status_from_unit(new.motorcycle_id);
  return new;
end;
$function$;

revoke all on function private.sync_motorcycle_store_status_from_unit(uuid) from public, anon, authenticated;
revoke all on function private.sync_motorcycle_store_status_after_unit_change() from public, anon, authenticated;

drop trigger if exists motorcycle_units_sync_store_model_status on public.motorcycle_units;
create trigger motorcycle_units_sync_store_model_status
after insert or update of motorcycle_id, unit_status, is_demo or delete
on public.motorcycle_units
for each row
execute function private.sync_motorcycle_store_status_after_unit_change();

update public.motorcycles m
   set status = 'available'::public.motorcycle_status
 where not coalesce(m.is_demo, false)
   and m.status is distinct from 'available'::public.motorcycle_status
   and exists (
     select 1
       from public.motorcycle_units u
      where u.motorcycle_id = m.id
        and u.unit_status = 'available'
        and not coalesce(u.is_demo, false)
   );
