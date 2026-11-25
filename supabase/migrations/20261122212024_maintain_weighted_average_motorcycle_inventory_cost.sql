-- Applied migration source recovered from Supabase migration ledger.

create or replace function private.recalculate_motorcycle_average_cost(p_motorcycle_id uuid)
returns void language plpgsql security definer set search_path='' as $function$
declare v_received_qty numeric;v_received_value numeric;v_returned_qty numeric;v_returned_value numeric;v_net_qty numeric;v_net_value numeric;
begin
 if p_motorcycle_id is null then return;end if;
 select coalesce(sum(quantity),0),coalesce(sum(quantity*unit_cost),0)
 into v_received_qty,v_received_value from public.purchase_receipt_items where motorcycle_id=p_motorcycle_id;
 select coalesce(sum(quantity),0),coalesce(sum(quantity*unit_cost),0)
 into v_returned_qty,v_returned_value from public.supplier_return_items where motorcycle_id=p_motorcycle_id;
 v_net_qty:=v_received_qty-v_returned_qty;v_net_value:=v_received_value-v_returned_value;
 if v_net_qty>0 then
  insert into public.motorcycle_inventory_costs(motorcycle_id,unit_cost,updated_by,updated_at)
  values(p_motorcycle_id,round(v_net_value/v_net_qty,2),(select auth.uid()),now())
  on conflict(motorcycle_id) do update set unit_cost=excluded.unit_cost,updated_by=excluded.updated_by,updated_at=now();
 end if;
end $function$;

create or replace function private.sync_motorcycle_average_cost_from_receipt()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
 if tg_op='DELETE' then perform private.recalculate_motorcycle_average_cost(old.motorcycle_id);return old;end if;
 if tg_op='UPDATE' and old.motorcycle_id is distinct from new.motorcycle_id then perform private.recalculate_motorcycle_average_cost(old.motorcycle_id);end if;
 perform private.recalculate_motorcycle_average_cost(new.motorcycle_id);return new;
end $function$;

create or replace function private.sync_motorcycle_average_cost_from_supplier_return()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
 if tg_op='DELETE' then perform private.recalculate_motorcycle_average_cost(old.motorcycle_id);return old;end if;
 if tg_op='UPDATE' and old.motorcycle_id is distinct from new.motorcycle_id then perform private.recalculate_motorcycle_average_cost(old.motorcycle_id);end if;
 perform private.recalculate_motorcycle_average_cost(new.motorcycle_id);return new;
end $function$;

drop trigger if exists purchase_receipt_items_average_cost_sync on public.purchase_receipt_items;
create trigger purchase_receipt_items_average_cost_sync
after insert or update or delete on public.purchase_receipt_items
for each row execute function private.sync_motorcycle_average_cost_from_receipt();

drop trigger if exists supplier_return_items_average_cost_sync on public.supplier_return_items;
create trigger supplier_return_items_average_cost_sync
after insert or update or delete on public.supplier_return_items
for each row execute function private.sync_motorcycle_average_cost_from_supplier_return();

revoke all on function private.recalculate_motorcycle_average_cost(uuid) from public,anon,authenticated;
revoke all on function private.sync_motorcycle_average_cost_from_receipt() from public,anon,authenticated;
revoke all on function private.sync_motorcycle_average_cost_from_supplier_return() from public,anon,authenticated;

