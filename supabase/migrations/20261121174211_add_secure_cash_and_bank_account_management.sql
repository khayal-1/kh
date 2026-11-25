create or replace function private.create_cash_account(p_name text,p_kind text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := (select auth.uid());
  v_name text := nullif(btrim(coalesce(p_name,'')),'');
  v_kind text := coalesce(p_kind,'');
  v_parent_code text;
  v_parent_id uuid;
  v_code text;
  v_account_id uuid;
  v_cash_id uuid;
begin
  if v_user is null or not public.has_any_role(array['manager','owner','admin']::public.app_role[]) then
    raise exception 'غير مصرح بإدارة الخزائن والبنوك' using errcode='42501';
  end if;
  if v_name is null or length(v_name)>120 or v_kind not in ('cash','bank') then
    raise exception 'اسم الحساب أو نوعه غير صحيح' using errcode='22023';
  end if;
  if exists(select 1 from public.cash_accounts where lower(name)=lower(v_name)) then
    raise exception 'يوجد حساب خزينة أو بنك بهذا الاسم بالفعل' using errcode='23505';
  end if;

  v_parent_code := case when v_kind='cash' then '1010' else '1020' end;
  select id into v_parent_id from public.accounting_accounts
    where code=v_parent_code and account_type='asset' and is_active;
  if v_parent_id is null then
    raise exception 'الحساب الرئيسي للخزينة أو البنك غير موجود' using errcode='23503';
  end if;

  perform pg_advisory_xact_lock(hashtext('elkhayal_cash_account_code_'||v_parent_code));
  select (coalesce(max(code::bigint),v_parent_code::bigint)+1)::text into v_code
  from public.accounting_accounts
  where parent_code=v_parent_code and code ~ '^[0-9]+$';

  insert into public.accounting_accounts(code,name,account_type,parent_code,is_system,is_active)
  values(v_code,v_name,'asset',v_parent_code,false,true)
  returning id into v_account_id;

  insert into public.cash_accounts(name,account_id,account_kind,currency)
  values(v_name,v_account_id,v_kind,'EGP')
  returning id into v_cash_id;

  return jsonb_build_object('cash_account_id',v_cash_id,'account_id',v_account_id,'account_code',v_code,'name',v_name,'account_kind',v_kind);
end;
$$;

revoke all on function private.create_cash_account(text,text) from public,anon;
grant execute on function private.create_cash_account(text,text) to authenticated;

create or replace function public.create_cash_account(p_name text,p_kind text)
returns jsonb
language sql
security invoker
set search_path=''
as $$ select private.create_cash_account($1,$2); $$;

revoke all on function public.create_cash_account(text,text) from public,anon;
grant execute on function public.create_cash_account(text,text) to authenticated;
