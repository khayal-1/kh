begin;

create or replace function public.can_view_sale_item_unit(p_sale_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select (select auth.uid()) is not null
     and (
       public.can_manage_sales()
       or exists(
         select 1
         from public.sale_items si
         join public.sales s on s.id=si.sale_id
         join public.clients c on c.id=s.customer_id
         where si.id=p_sale_item_id
           and c.user_id=(select auth.uid())
       )
     );
$$;
revoke all on function public.can_view_sale_item_unit(uuid) from public,anon;
grant execute on function public.can_view_sale_item_unit(uuid) to authenticated;

drop policy if exists sale_item_units_customer_read on public.sale_item_units;
create policy sale_item_units_customer_read on public.sale_item_units
  for select to authenticated
  using(public.can_view_sale_item_unit(sale_item_id));

commit;
