-- Source recovered from the applied production migration ledger.
create policy payments_finance_select
on public.payments for select to authenticated
using (public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));

create policy customer_credit_transactions_finance_select
on public.customer_credit_transactions for select to authenticated
using (public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));
