begin;

-- A restocked return first reactivates the exact sold units through the
-- sale_return_items trigger, then increases model stock in the same transaction.
-- Mark the stock change as an approved sale-return path so the generic stock
-- trigger does not create a duplicate movement (the return RPC already records it).
do $$
declare
  v_definition text;
  v_before text:='   update public.motorcycles set stock=stock+v_quantity where id=v_sale_item.motorcycle_id;';
  v_after text:='   perform set_config(''ekm.stock_movement_source'',''sale'',true); update public.motorcycles set stock=stock+v_quantity where id=v_sale_item.motorcycle_id; perform set_config(''ekm.stock_movement_source'','''',true);';
begin
  select pg_get_functiondef('public.create_sale_return(uuid,jsonb,text)'::regprocedure)
    into v_definition;
  if position(v_before in v_definition)=0 then
    raise exception 'Unable to harden customer return stock update; expected source fragment was not found.';
  end if;
  v_definition:=replace(v_definition,v_before,v_after);
  execute v_definition;
end;
$$;

commit;
