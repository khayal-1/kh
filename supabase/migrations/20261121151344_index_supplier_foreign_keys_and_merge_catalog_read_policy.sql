begin;
create index if not exists purchase_order_items_motorcycle_idx on public.purchase_order_items(motorcycle_id);
create index if not exists purchase_orders_created_by_idx on public.purchase_orders(created_by);
create index if not exists purchase_receipts_received_by_idx on public.purchase_receipts(received_by);
create index if not exists suppliers_created_by_idx on public.suppliers(created_by);
drop policy if exists catalog_employee_read on public.motorcycles;
drop policy if exists catalog_public_read on public.motorcycles;
create policy catalog_read on public.motorcycles for select to anon,authenticated using (
 status='available'::public.motorcycle_status
 or public.has_any_role(array['manager','owner','admin']::public.app_role[])
 or public.has_employee_permission('catalog_view')
 or public.has_employee_permission('catalog_manage')
);
commit;