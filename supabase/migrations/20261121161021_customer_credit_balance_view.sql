create or replace view public.customer_credit_balances
with (security_invoker = true)
as
select c.id as customer_id,
       c.display_name as customer_name,
       c.phone as customer_phone,
       coalesce(sum(t.amount),0)::numeric(12,2) as balance
from public.clients c
join public.customer_credit_transactions t on t.customer_id=c.id
group by c.id,c.display_name,c.phone
having coalesce(sum(t.amount),0)>0.009;

grant select on public.customer_credit_balances to authenticated;