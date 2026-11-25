create index if not exists customer_credit_transactions_created_by_idx
  on public.customer_credit_transactions(created_by)
  where created_by is not null;
create index if not exists supplier_returns_created_by_idx
  on public.supplier_returns(created_by)
  where created_by is not null;
create index if not exists supplier_returns_purchase_order_id_idx
  on public.supplier_returns(purchase_order_id)
  where purchase_order_id is not null;
create index if not exists supplier_return_items_motorcycle_id_idx
  on public.supplier_return_items(motorcycle_id);