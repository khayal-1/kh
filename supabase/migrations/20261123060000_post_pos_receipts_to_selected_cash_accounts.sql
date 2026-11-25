begin;

create or replace function public.get_sales_cash_accounts()
returns table(id uuid,name text,account_kind text,currency char(3))
language sql
stable
security definer
set search_path=''
as $$
  select ca.id,ca.name,ca.account_kind,ca.currency
  from public.cash_accounts ca
  where ca.is_active
    and public.can_manage_sales()
  order by ca.account_kind,ca.name;
$$;
revoke all on function public.get_sales_cash_accounts() from public,anon;
grant execute on function public.get_sales_cash_accounts() to authenticated;

-- A payment with a selected cash account posts directly to that account.
-- Legacy callers without a selection remain in suspense account 1030.
create or replace function private.post_sale_payment_journal()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  cash_id uuid;
  cash_account_id_value uuid;
  ar_id uuid;
  journal_id uuid;
  configured_cash_id text:=nullif(current_setting('ekm.cash_account_id',true),'');
begin
  if configured_cash_id is not null then
    begin cash_account_id_value:=configured_cash_id::uuid;
    exception when others then raise exception 'حساب الخزينة المحدد غير صالح' using errcode='22023'; end;
    select account_id into cash_id
      from public.cash_accounts
     where id=cash_account_id_value and is_active;
    if cash_id is null then
      raise exception 'حساب الخزينة أو البنك المحدد غير نشط أو غير موجود' using errcode='23514';
    end if;
    update public.payments set cash_account_id=cash_account_id_value where id=new.id;
  else
    select id into cash_id from public.accounting_accounts where code='1030' and is_active;
  end if;
  select id into ar_id from public.accounting_accounts where code='1100' and is_active;
  if cash_id is null or ar_id is null then
    raise exception 'حساب الخزينة أو حساب العملاء غير مهيأ' using errcode='23514';
  end if;
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
  values(
    new.paid_at::date,
    case when cash_account_id_value is null then 'تحصيل دفعة بيع غير موزعة على خزينة/بنك' else 'تحصيل دفعة بيع إلى حساب نقدي/بنكي محدد' end,
    'sale_payment',new.id,new.received_by
  ) returning id into journal_id;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
  values(
    journal_id,cash_id,new.amount,0,
    case when cash_account_id_value is null then 'متحصلات بانتظار تحديد الخزينة أو البنك' else 'متحصلات في حساب الخزينة/البنك المحدد' end
  ),(journal_id,ar_id,0,new.amount,'تخفيض رصيد العميل');
  update public.payments set journal_entry_id=journal_id where id=new.id;
  return new;
end;
$$;

create or replace function private.create_showroom_sale_for_unit_with_cash_impl(
  p_unit_id uuid,p_customer_user_id uuid,p_customer_name text,p_customer_phone text,
  p_payment_amount numeric,p_payment_method text,p_payment_reference text,
  p_notes text,p_cash_account_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  if coalesce(p_payment_amount,0)>0 then
    if p_cash_account_id is null or not exists(
      select 1 from public.cash_accounts where id=p_cash_account_id and is_active
    ) then
      raise exception 'اختر حساب الخزينة أو البنك الذي استلم الدفعة' using errcode='22023';
    end if;
  end if;
  perform set_config('ekm.cash_account_id',coalesce(p_cash_account_id::text,''),true);
  return private.create_showroom_sale_for_unit_impl(
    p_unit_id,p_customer_user_id,p_customer_name,p_customer_phone,
    p_payment_amount,p_payment_method,p_payment_reference,p_notes
  );
end;
$$;
revoke all on function private.create_showroom_sale_for_unit_with_cash_impl(uuid,uuid,text,text,numeric,text,text,text,uuid) from public,anon;
grant execute on function private.create_showroom_sale_for_unit_with_cash_impl(uuid,uuid,text,text,numeric,text,text,text,uuid) to authenticated;

create or replace function public.create_showroom_sale_for_unit(
  p_unit_id uuid,p_customer_user_id uuid,p_customer_name text,p_customer_phone text,
  p_payment_amount numeric,p_payment_method text,p_payment_reference text,
  p_notes text,p_cash_account_id uuid
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select private.create_showroom_sale_for_unit_with_cash_impl($1,$2,$3,$4,$5,$6,$7,$8,$9);
$$;
revoke all on function public.create_showroom_sale_for_unit(uuid,uuid,text,text,numeric,text,text,text,uuid) from public,anon;
grant execute on function public.create_showroom_sale_for_unit(uuid,uuid,text,text,numeric,text,text,text,uuid) to authenticated;

create or replace function private.create_showroom_sale_with_units_cash_impl(
  p_customer_user_id uuid,p_customer_name text,p_customer_phone text,
  p_items jsonb,p_payment_amount numeric,p_payment_method text,
  p_payment_reference text,p_notes text,p_cash_account_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  if coalesce(p_payment_amount,0)>0 then
    if p_cash_account_id is null or not exists(
      select 1 from public.cash_accounts where id=p_cash_account_id and is_active
    ) then
      raise exception 'اختر حساب الخزينة أو البنك الذي استلم الدفعة' using errcode='22023';
    end if;
  end if;
  perform set_config('ekm.cash_account_id',coalesce(p_cash_account_id::text,''),true);
  return private.create_showroom_sale_with_units_impl(
    p_customer_user_id,p_customer_name,p_customer_phone,p_items,
    p_payment_amount,p_payment_method,p_payment_reference,p_notes
  );
end;
$$;
revoke all on function private.create_showroom_sale_with_units_cash_impl(uuid,text,text,jsonb,numeric,text,text,text,uuid) from public,anon;
grant execute on function private.create_showroom_sale_with_units_cash_impl(uuid,text,text,jsonb,numeric,text,text,text,uuid) to authenticated;

create or replace function public.create_showroom_sale_with_units(
  p_customer_user_id uuid,p_customer_name text,p_customer_phone text,
  p_items jsonb,p_payment_amount numeric,p_payment_method text,
  p_payment_reference text,p_notes text,p_cash_account_id uuid
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select private.create_showroom_sale_with_units_cash_impl($1,$2,$3,$4,$5,$6,$7,$8,$9);
$$;
revoke all on function public.create_showroom_sale_with_units(uuid,text,text,jsonb,numeric,text,text,text,uuid) from public,anon;
grant execute on function public.create_showroom_sale_with_units(uuid,text,text,jsonb,numeric,text,text,text,uuid) to authenticated;

create or replace function private.record_sale_payment_idempotent_with_cash_impl(
  p_sale_id uuid,p_amount numeric,p_method text,p_reference text,
  p_idempotency_key uuid,p_cash_account_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  prior_payment public.payments%rowtype;
begin
  if p_cash_account_id is null or not exists(
    select 1 from public.cash_accounts where id=p_cash_account_id and is_active
  ) then
    raise exception 'اختر حساب الخزينة أو البنك الذي استلم الدفعة' using errcode='22023';
  end if;
  select * into prior_payment from public.payments
   where idempotency_key=p_idempotency_key;
  if found and prior_payment.cash_account_id is distinct from p_cash_account_id then
    raise exception 'مفتاح إعادة المحاولة مرتبط بحساب خزينة مختلف؛ استخدم نفس الحساب الأصلي' using errcode='23505';
  end if;
  perform set_config('ekm.cash_account_id',p_cash_account_id::text,true);
  return private.record_sale_payment_idempotent_impl(
    p_sale_id,p_amount,p_method,p_reference,p_idempotency_key
  );
end;
$$;
revoke all on function private.record_sale_payment_idempotent_with_cash_impl(uuid,numeric,text,text,uuid,uuid) from public,anon;
grant execute on function private.record_sale_payment_idempotent_with_cash_impl(uuid,numeric,text,text,uuid,uuid) to authenticated;

create or replace function public.record_sale_payment(
  p_sale_id uuid,p_amount numeric,p_method text,p_reference text,
  p_idempotency_key uuid,p_cash_account_id uuid
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select private.record_sale_payment_idempotent_with_cash_impl($1,$2,$3,$4,$5,$6);
$$;
revoke all on function public.record_sale_payment(uuid,numeric,text,text,uuid,uuid) from public,anon;
grant execute on function public.record_sale_payment(uuid,numeric,text,text,uuid,uuid) to authenticated;

commit;
