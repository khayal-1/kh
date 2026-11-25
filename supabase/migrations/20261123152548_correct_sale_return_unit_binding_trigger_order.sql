drop trigger if exists sale_return_items_bind_physical_units on public.sale_return_items;

create or replace function private.bind_sale_return_item_units()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_linked_count integer;
  v_picked integer := 0;
  v_unit record;
begin
  select count(*)::integer
    into v_linked_count
    from public.sale_item_units
   where sale_item_id = new.sale_item_id;

  -- Preserve legacy returns for invoices created before VIN-level sale tracking.
  if v_linked_count = 0 then
    return new;
  end if;

  for v_unit in
    select u.id, u.vin, u.engine_number,
           coalesce(siu.unit_cost, u.unit_cost, si.unit_cost) as unit_cost
      from public.sale_item_units siu
      join public.motorcycle_units u on u.id = siu.motorcycle_unit_id
      join public.sale_items si on si.id = siu.sale_item_id
     where siu.sale_item_id = new.sale_item_id
       and u.sale_item_id = new.sale_item_id
       and u.unit_status = 'sold'
       and not exists (
         select 1
           from public.sale_return_item_units prior
          where prior.sale_item_id = new.sale_item_id
            and prior.motorcycle_unit_id = u.id
       )
     order by u.registered_at desc, u.id desc
     limit new.quantity
     for update of u skip locked
  loop
    insert into public.sale_return_item_units(
      sale_return_item_id, sale_item_id, motorcycle_unit_id,
      vin_snapshot, engine_number_snapshot, unit_cost
    ) values (
      new.id, new.sale_item_id, v_unit.id,
      v_unit.vin, v_unit.engine_number, v_unit.unit_cost
    );
    v_picked := v_picked + 1;
  end loop;

  if v_picked <> new.quantity then
    raise exception 'عدد الوحدات المرتبطة بالفاتورة لا يكفي للمرتجع؛ لا يمكن إعادة نفس الشاسيه مرتين'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

revoke all on function private.bind_sale_return_item_units() from public, anon, authenticated;

create trigger sale_return_items_bind_physical_units
after insert on public.sale_return_items
for each row
execute function private.bind_sale_return_item_units();
