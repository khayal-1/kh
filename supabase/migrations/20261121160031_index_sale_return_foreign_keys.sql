create index if not exists sale_return_items_motorcycle_id_idx on public.sale_return_items(motorcycle_id);
create index if not exists sale_returns_created_by_idx on public.sale_returns(created_by);
create index if not exists sale_returns_customer_id_idx on public.sale_returns(customer_id);