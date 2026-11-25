alter table public.customer_requests
  add column motorcycle_unit_id uuid,
  add column requested_unit_vin text,
  add column requested_unit_condition text;

alter table public.customer_requests
  add constraint customer_requests_motorcycle_unit_id_fkey
    foreign key (motorcycle_unit_id)
    references public.motorcycle_units(id)
    on delete restrict,
  add constraint customer_requests_requested_unit_condition_check
    check (requested_unit_condition is null or requested_unit_condition in ('new','used')),
  add constraint customer_requests_unit_snapshot_check
    check (
      motorcycle_unit_id is null
      or (requested_unit_vin is not null and requested_unit_condition is not null)
    );

create index customer_requests_motorcycle_unit_id_idx
  on public.customer_requests(motorcycle_unit_id)
  where motorcycle_unit_id is not null;

create or replace function private.validate_customer_request_motorcycle_unit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_motorcycle_id uuid;
  v_vin text;
  v_condition text;
begin
  if new.motorcycle_unit_id is null then
    new.requested_unit_vin := null;
    new.requested_unit_condition := null;
    return new;
  end if;

  select u.motorcycle_id, u.vin, u.unit_condition
    into v_motorcycle_id, v_vin, v_condition
    from public.motorcycle_units u
    join public.motorcycles m on m.id = u.motorcycle_id
   where u.id = new.motorcycle_unit_id
     and u.unit_status = 'available'
     and not coalesce(u.is_demo, false)
     and not coalesce(m.is_demo, false);

  if not found then
    raise exception 'الوحدة المختارة لم تعد متاحة للطلب؛ حدّث المتجر واختر وحدة أخرى'
      using errcode = '23514';
  end if;

  if new.motorcycle_id is not null
     and new.motorcycle_id is distinct from v_motorcycle_id then
    raise exception 'الوحدة المختارة لا تتبع الطراز المحدد'
      using errcode = '23514';
  end if;

  new.motorcycle_id := v_motorcycle_id;
  new.requested_unit_vin := v_vin;
  new.requested_unit_condition := v_condition;
  return new;
end;
$function$;

revoke all on function private.validate_customer_request_motorcycle_unit() from public, anon, authenticated;

drop trigger if exists customer_requests_validate_motorcycle_unit on public.customer_requests;
create trigger customer_requests_validate_motorcycle_unit
before insert or update of motorcycle_unit_id, motorcycle_id
on public.customer_requests
for each row
execute function private.validate_customer_request_motorcycle_unit();
