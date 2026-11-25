-- Migration: enforce_balanced_immutable_journals_and_finance_views
-- Protects posted double-entry journals and exposes read-only accounting reports.

alter table public.employee_permissions
  drop constraint if exists employee_permissions_permission_key_check;
alter table public.employee_permissions
  add constraint employee_permissions_permission_key_check
  check (permission_key = any (array[
    'catalog_view','catalog_manage','requests_view','requests_manage',
    'customer_data_view','sales_manage','expenses_manage','accounting_view'
  ]::text[]));

create or replace function private.assert_journal_entry_balanced()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry_id uuid;
  v_status text;
  v_count integer;
  v_debit numeric(14,2);
  v_credit numeric(14,2);
begin
  if tg_table_name = 'journal_entries' then
    v_entry_id := coalesce(new.id, old.id);
  else
    v_entry_id := coalesce(new.journal_entry_id, old.journal_entry_id);
  end if;

  select status into v_status
  from public.journal_entries
  where id = v_entry_id;

  if not found or v_status <> 'posted' then
    return null;
  end if;

  select count(*), coalesce(sum(debit),0), coalesce(sum(credit),0)
    into v_count, v_debit, v_credit
  from public.journal_entry_lines
  where journal_entry_id = v_entry_id;

  if v_count < 2 or v_debit <= 0 or abs(v_debit-v_credit) > 0.005 then
    raise exception 'القيد المحاسبي رقم % غير متوازن: المدين % والدائن %', v_entry_id, v_debit, v_credit
      using errcode = '23514';
  end if;

  return null;
end;
$$;

drop trigger if exists journal_entry_balance_check on public.journal_entries;
create constraint trigger journal_entry_balance_check
after insert or update on public.journal_entries
deferrable initially deferred
for each row execute function private.assert_journal_entry_balanced();

drop trigger if exists journal_entry_lines_balance_check on public.journal_entry_lines;
create constraint trigger journal_entry_lines_balance_check
after insert or update or delete on public.journal_entry_lines
deferrable initially deferred
for each row execute function private.assert_journal_entry_balanced();

create or replace function private.prevent_posted_journal_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry_id uuid;
  v_status text;
begin
  if tg_table_name = 'journal_entries' then
    v_entry_id := old.id;
  else
    v_entry_id := old.journal_entry_id;
  end if;

  select status into v_status from public.journal_entries where id = v_entry_id;
  if v_status = 'posted' then
    raise exception 'لا يمكن تعديل أو حذف قيد محاسبي مُرحّل؛ استخدم قيدًا عكسيًا أو تسوية'
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists protect_posted_journal_entry on public.journal_entries;
create trigger protect_posted_journal_entry
before update or delete on public.journal_entries
for each row execute function private.prevent_posted_journal_mutation();

drop trigger if exists protect_posted_journal_line on public.journal_entry_lines;
create trigger protect_posted_journal_line
before update or delete on public.journal_entry_lines
for each row execute function private.prevent_posted_journal_mutation();

create or replace view public.accounting_trial_balance
with (security_invoker = true)
as
select
  a.id as account_id,
  a.code as account_code,
  a.name as account_name,
  a.account_type,
  coalesce(sum(l.debit),0)::numeric(14,2) as total_debit,
  coalesce(sum(l.credit),0)::numeric(14,2) as total_credit,
  greatest(coalesce(sum(l.debit-l.credit),0),0)::numeric(14,2) as debit_balance,
  greatest(coalesce(sum(l.credit-l.debit),0),0)::numeric(14,2) as credit_balance
from public.accounting_accounts a
left join public.journal_entry_lines l on l.account_id = a.id
left join public.journal_entries e on e.id = l.journal_entry_id and e.status = 'posted'
where l.id is null or e.id is not null
group by a.id,a.code,a.name,a.account_type;

create or replace view public.accounting_cash_balances
with (security_invoker = true)
as
select
  c.id as cash_account_id,
  c.name as cash_account_name,
  c.account_kind,
  c.currency,
  coalesce(sum(l.debit-l.credit),0)::numeric(14,2) as balance
from public.cash_accounts c
left join public.journal_entry_lines l on l.account_id = c.account_id
left join public.journal_entries e on e.id = l.journal_entry_id and e.status = 'posted'
where l.id is null or e.id is not null
group by c.id,c.name,c.account_kind,c.currency;

grant select on public.accounting_trial_balance, public.accounting_cash_balances to authenticated;
