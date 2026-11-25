-- Source recovered from the applied production migration ledger.
create or replace function private.get_financial_statements(p_start_date date,p_end_date date,p_as_of_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.can_manage_finance() and not public.has_employee_permission('accounting_view') then raise exception 'غير مصرح بعرض القوائم المالية' using errcode='42501';end if;
 if p_start_date is null or p_end_date is null or p_as_of_date is null or p_end_date<p_start_date then raise exception 'فترة القوائم المالية غير صحيحة' using errcode='22023';end if;
 with period_balances as (
  select a.id,a.code,a.name,a.account_type,
   coalesce(sum(l.debit) filter(where j.entry_date between p_start_date and p_end_date),0)::numeric(14,2) as period_debit,
   coalesce(sum(l.credit) filter(where j.entry_date between p_start_date and p_end_date),0)::numeric(14,2) as period_credit,
   coalesce(sum(l.debit) filter(where j.entry_date<=p_as_of_date),0)::numeric(14,2) as asof_debit,
   coalesce(sum(l.credit) filter(where j.entry_date<=p_as_of_date),0)::numeric(14,2) as asof_credit
  from public.accounting_accounts a
  left join public.journal_entry_lines l on l.account_id=a.id
  left join public.journal_entries j on j.id=l.journal_entry_id and j.status='posted'
  group by a.id,a.code,a.name,a.account_type
 ), income as (
  select coalesce(sum(case when account_type='revenue' then period_credit-period_debit else 0 end),0)::numeric(14,2) revenue,
   coalesce(sum(case when account_type='expense' then period_debit-period_credit else 0 end),0)::numeric(14,2) expenses
  from period_balances
 ), asof_income as (
  select coalesce(sum(case when account_type='revenue' then asof_credit-asof_debit when account_type='expense' then -(asof_debit-asof_credit) else 0 end),0)::numeric(14,2) net_income
  from period_balances
 ), balance as (
  select
   coalesce(sum(asof_debit-asof_credit) filter(where account_type='asset'),0)::numeric(14,2) assets,
   coalesce(sum(asof_credit-asof_debit) filter(where account_type='liability'),0)::numeric(14,2) liabilities,
   coalesce(sum(asof_credit-asof_debit) filter(where account_type='equity'),0)::numeric(14,2) equity
  from period_balances
 )
 select jsonb_build_object(
  'period_start',p_start_date,'period_end',p_end_date,'as_of_date',p_as_of_date,
  'income_statement',jsonb_build_object(
   'accounts',(select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name,'account_type',account_type,'amount',case when account_type='revenue' then period_credit-period_debit else period_debit-period_credit end) order by code),'[]'::jsonb) from period_balances where account_type in ('revenue','expense')),
   'total_revenue',income.revenue,'total_expenses',income.expenses,'net_income',income.revenue-income.expenses
  ),
  'balance_sheet',jsonb_build_object(
   'accounts',(select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name,'account_type',account_type,'balance',case when account_type='asset' then asof_debit-asof_credit else asof_credit-asof_debit end) order by code),'[]'::jsonb) from period_balances where account_type in ('asset','liability','equity')),
   'assets',balance.assets,'liabilities',balance.liabilities,'equity',balance.equity,'cumulative_net_income',asof_income.net_income,
   'total_equity_including_result',balance.equity+asof_income.net_income,
   'difference',balance.assets-(balance.liabilities+balance.equity+asof_income.net_income)
  ),
  'trial_balance',(select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name,'account_type',account_type,'debit',asof_debit,'credit',asof_credit,'net_debit',greatest(asof_debit-asof_credit,0),'net_credit',greatest(asof_credit-asof_debit,0)) order by code),'[]'::jsonb) from period_balances)
 ) into result from income,balance,asof_income;
 return result;
end $$;
create or replace function public.get_financial_statements(date,date,date)
returns jsonb language sql security invoker set search_path='' as $$ select private.get_financial_statements($1,$2,$3) $$;
revoke all on function public.get_financial_statements(date,date,date) from public,anon;
grant execute on function public.get_financial_statements(date,date,date) to authenticated;

