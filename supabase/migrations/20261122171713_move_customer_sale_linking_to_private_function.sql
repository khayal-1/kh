begin;
create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.create_showroom_sale_for_customer_impl(
  p_customer_user_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_payment_amount numeric,
  p_payment_method text,
  p_payment_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer public.clients%rowtype;
  v_result jsonb;
  v_sale_id uuid;
  v_temporary_client_id uuid;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception using errcode='42501', message='ليس لديك صلاحية تسجيل المبيعات';
  end if;

  if p_customer_user_id is not null then
    select * into v_customer from public.clients
    where user_id=p_customer_user_id for share;
    if not found then
      raise exception using errcode='P0002', message='حساب العميل المحدد غير مرتبط بملف عميل';
    end if;

    v_result := public.create_showroom_sale(
      coalesce(nullif(btrim(v_customer.display_name),''),p_customer_name),
      coalesce(nullif(btrim(v_customer.phone),''),p_customer_phone),
      p_items,p_payment_amount,p_payment_method,p_payment_reference,p_notes
    );
    v_sale_id := (v_result->>'id')::uuid;
    select customer_id into v_temporary_client_id from public.sales where id=v_sale_id for update;
    update public.sales set customer_id=v_customer.id where id=v_sale_id;

    if v_temporary_client_id is not null and v_temporary_client_id<>v_customer.id
      and not exists(select 1 from public.sales where customer_id=v_temporary_client_id) then
      delete from public.clients where id=v_temporary_client_id and user_id is null;
    end if;
  else
    v_result := public.create_showroom_sale(
      p_customer_name,p_customer_phone,p_items,p_payment_amount,
      p_payment_method,p_payment_reference,p_notes
    );
  end if;
  return v_result;
end;
$$;

revoke all on function private.create_showroom_sale_for_customer_impl(uuid,text,text,jsonb,numeric,text,text,text) from public,anon;
grant execute on function private.create_showroom_sale_for_customer_impl(uuid,text,text,jsonb,numeric,text,text,text) to authenticated;

create or replace function public.create_showroom_sale_for_customer(
  p_customer_user_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_payment_amount numeric,
  p_payment_method text,
  p_payment_reference text default null,
  p_notes text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.create_showroom_sale_for_customer_impl($1,$2,$3,$4,$5,$6,$7,$8);
$$;

revoke all on function public.create_showroom_sale_for_customer(uuid,text,text,jsonb,numeric,text,text,text) from public,anon;
grant execute on function public.create_showroom_sale_for_customer(uuid,text,text,jsonb,numeric,text,text,text) to authenticated;
commit;
