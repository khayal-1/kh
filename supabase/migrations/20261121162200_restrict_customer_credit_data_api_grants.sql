revoke all privileges on table public.customer_credit_balances from public, anon, authenticated;
grant select on table public.customer_credit_balances to authenticated;

revoke all privileges on table public.customer_credit_transactions from public, anon, authenticated;
grant select on table public.customer_credit_transactions to authenticated;