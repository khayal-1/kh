-- Keep every active chart-of-accounts row visible in accounting reports,
-- including accounts whose only historical entries have been reversed.
create or replace view public.accounting_trial_balance
with (security_invoker = true)
as
with posted_totals as (
  select l.account_id,
         sum(l.debit)::numeric(14,2) as total_debit,
         sum(l.credit)::numeric(14,2) as total_credit
  from public.journal_entry_lines l
  join public.journal_entries e on e.id=l.journal_entry_id
  where e.status='posted'
  group by l.account_id
)
select
  a.id as account_id,
  a.code as account_code,
  a.name as account_name,
  a.account_type,
  coalesce(t.total_debit,0)::numeric(14,2) as total_debit,
  coalesce(t.total_credit,0)::numeric(14,2) as total_credit,
  greatest(coalesce(t.total_debit,0)-coalesce(t.total_credit,0),0)::numeric(14,2) as debit_balance,
  greatest(coalesce(t.total_credit,0)-coalesce(t.total_debit,0),0)::numeric(14,2) as credit_balance
from public.accounting_accounts a
left join posted_totals t on t.account_id=a.id;

create or replace view public.accounting_cash_balances
with (security_invoker = true)
as
with posted_totals as (
  select l.account_id, sum(l.debit-l.credit)::numeric(14,2) as balance
  from public.journal_entry_lines l
  join public.journal_entries e on e.id=l.journal_entry_id
  where e.status='posted'
  group by l.account_id
)
select
  c.id as cash_account_id,
  c.name as cash_account_name,
  c.account_kind,
  c.currency,
  coalesce(t.balance,0)::numeric(14,2) as balance
from public.cash_accounts c
left join posted_totals t on t.account_id=c.account_id;
