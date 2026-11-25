-- Source recovered from the applied production migration ledger.
drop policy if exists customer_credit_transactions_finance_select on public.customer_credit_transactions;
drop policy if exists customer_credit_transactions_manager_select on public.customer_credit_transactions;
drop policy if exists customer_credit_transactions_read_own_customer on public.customer_credit_transactions;
create policy customer_credit_transactions_read_combined on public.customer_credit_transactions for select to authenticated using(
 public.can_manage_sales() or public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage')
 or exists(select 1 from public.clients c where c.id=customer_credit_transactions.customer_id and c.user_id=(select auth.uid()))
);

drop policy if exists payments_finance_select on public.payments;
drop policy if exists payments_read_authorized on public.payments;
drop policy if exists payments_read_own_customer on public.payments;
create policy payments_read_combined on public.payments for select to authenticated using(
 public.can_manage_sales() or public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage')
 or exists(select 1 from public.sales s join public.clients c on c.id=s.customer_id where s.id=payments.sale_id and c.user_id=(select auth.uid()))
);

drop policy if exists sale_items_read_authorized on public.sale_items;
drop policy if exists sale_items_read_own_customer on public.sale_items;
create policy sale_items_read_combined on public.sale_items for select to authenticated using(
 public.can_manage_sales()
 or exists(select 1 from public.sales s join public.clients c on c.id=s.customer_id where s.id=sale_items.sale_id and c.user_id=(select auth.uid()))
);

drop policy if exists sale_returns_read_own_customer on public.sale_returns;
drop policy if exists sale_returns_select_sales_managers on public.sale_returns;
create policy sale_returns_read_combined on public.sale_returns for select to authenticated using(
 public.can_manage_sales()
 or exists(select 1 from public.clients c where c.id=sale_returns.customer_id and c.user_id=(select auth.uid()))
);

drop policy if exists sales_read_authorized on public.sales;
drop policy if exists sales_read_own_customer on public.sales;
create policy sales_read_combined on public.sales for select to authenticated using(
 public.can_manage_sales()
 or exists(select 1 from public.clients c where c.id=sales.customer_id and c.user_id=(select auth.uid()))
);
