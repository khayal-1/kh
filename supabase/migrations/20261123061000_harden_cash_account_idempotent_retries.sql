begin;

-- The five-argument endpoint predates mandatory cash-account attribution.
-- Disable it so clients cannot bypass the new six-argument contract.
revoke all on function public.record_sale_payment(uuid,numeric,text,text,uuid)
  from public,anon,authenticated;
revoke all on function public.create_showroom_sale(text,text,jsonb,numeric,text,text,text)
  from public,anon,authenticated;
revoke all on function public.create_showroom_sale_for_unit(uuid,uuid,text,text,numeric,text,text,text)
  from public,anon,authenticated;
revoke all on function public.create_showroom_sale_with_units(uuid,text,text,jsonb,numeric,text,text,text)
  from public,anon,authenticated;

-- Compare the original account inside the serialized idempotent operation.
-- Doing this in the implementation (after the sale row lock) closes the race
-- where two simultaneous retries could both observe no prior payment.
do $$
declare
  v_definition text;
  v_before text:='if v_payment.sale_id<>p_sale_id or v_payment.amount<>p_amount or v_payment.method<>p_method then';
  v_after text:='if v_payment.sale_id<>p_sale_id or v_payment.amount<>p_amount or v_payment.method<>p_method or v_payment.cash_account_id is distinct from nullif(current_setting(''ekm.cash_account_id'',true),'''')::uuid then';
begin
  select pg_get_functiondef(
    'private.record_sale_payment_idempotent_impl(uuid,numeric,text,text,uuid)'::regprocedure
  ) into v_definition;
  if position(v_before in v_definition)=0 then
    raise exception 'Unable to harden idempotent payment account matching.';
  end if;
  v_definition:=replace(v_definition,v_before,v_after);
  execute v_definition;
end;
$$;

commit;
