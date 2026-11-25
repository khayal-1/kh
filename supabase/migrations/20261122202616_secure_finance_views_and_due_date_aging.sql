-- Source recovered from the applied production migration ledger.
alter table public.sales add column if not exists due_date date;

create or replace view public.accounting_aging_report
with (security_invoker=true) as
select 'customer'::text as party_type,s.customer_id as party_id,s.customer_name as party_name,s.invoice_number as document_number,
 s.created_at::date as document_date,s.due_date,
 greatest(0,s.total-s.amount_paid-s.credit_applied-coalesce(r.returns_total,0))::numeric(14,2) as balance_due,
 case when s.due_date is null then null else greatest(0,current_date-s.due_date)::integer end as days_overdue
from public.sales s left join (select sale_id,sum(total_amount) returns_total from public.sale_returns group by sale_id) r on r.sale_id=s.id
where s.status='posted' and s.total-s.amount_paid-s.credit_applied-coalesce(r.returns_total,0)>0
union all
select 'supplier'::text,sb.supplier_id,sp.name,sb.bill_number,sb.bill_date,sb.due_date,
 greatest(0,sb.total_amount-coalesce(p.paid,0)-coalesce(r.returned,0)-coalesce(a.allocated,0))::numeric(14,2),
 case when sb.due_date is null then null else greatest(0,current_date-sb.due_date)::integer end
from public.supplier_bills sb join public.suppliers sp on sp.id=sb.supplier_id
left join (select supplier_bill_id,sum(amount) paid from public.supplier_payments group by supplier_bill_id) p on p.supplier_bill_id=sb.id
left join (select sr.supplier_bill_id,sum(sri.line_total) returned from public.supplier_returns sr join public.supplier_return_items sri on sri.supplier_return_id=sr.id group by sr.supplier_bill_id) r on r.supplier_bill_id=sb.id
left join (select supplier_bill_id,sum(amount) allocated from public.supplier_advance_allocations group by supplier_bill_id) a on a.supplier_bill_id=sb.id
where sb.total_amount-coalesce(p.paid,0)-coalesce(r.returned,0)-coalesce(a.allocated,0)>0;

create or replace view public.accounting_cash_book
with (security_invoker=true) as
select ca.id as cash_account_id,ca.name as cash_account_name,ca.account_kind,ca.currency,
 je.id as journal_entry_id,je.entry_number,je.entry_date,je.description,jel.debit,jel.credit,(jel.debit-jel.credit) as movement,
 sum(jel.debit-jel.credit) over(partition by ca.id order by je.entry_date,je.created_at,jel.id rows unbounded preceding) as running_balance
from public.cash_accounts ca join public.journal_entry_lines jel on jel.account_id=ca.account_id
join public.journal_entries je on je.id=jel.journal_entry_id and je.status='posted';

create or replace view public.finance_budget_vs_actual
with (security_invoker=true) as
select b.id as budget_id,b.budget_name,b.status,p.period_code,p.start_date,p.end_date,
 a.id as account_id,a.code as account_code,a.name as account_name,a.account_type,
 bl.cost_center_id,coalesce(bl.budget_amount,0) as budget_amount,
 coalesce(sum(case when je.id is not null then case when a.account_type='expense' then jel.debit-jel.credit else jel.credit-jel.debit end else 0 end),0)::numeric(14,2) as actual_amount,
 (coalesce(bl.budget_amount,0)-coalesce(sum(case when je.id is not null then case when a.account_type='expense' then jel.debit-jel.credit else jel.credit-jel.debit end else 0 end),0))::numeric(14,2) as variance
from public.finance_budgets b join public.fiscal_periods p on p.id=b.period_id
join public.finance_budget_lines bl on bl.budget_id=b.id
join public.accounting_accounts a on a.id=bl.account_id
left join public.journal_entry_lines jel on jel.account_id=a.id and (bl.cost_center_id is null or jel.cost_center_id=bl.cost_center_id)
left join public.journal_entries je on je.id=jel.journal_entry_id and je.status='posted' and je.entry_date between p.start_date and p.end_date
group by b.id,b.budget_name,b.status,p.period_code,p.start_date,p.end_date,a.id,a.code,a.name,a.account_type,bl.cost_center_id,bl.budget_amount;

revoke all on public.accounting_aging_report,public.accounting_cash_book,public.finance_budget_vs_actual from anon;
grant select on public.accounting_aging_report,public.accounting_cash_book,public.finance_budget_vs_actual to authenticated;

