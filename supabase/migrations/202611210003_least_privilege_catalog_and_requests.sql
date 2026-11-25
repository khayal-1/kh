begin;

-- Staff can view the full catalog, but only managers/owners/admins can change it.
drop policy if exists catalog_staff on public.motorcycles;
create policy catalog_staff_read
  on public.motorcycles
  for select
  to authenticated
  using (public.has_any_role(array['employee', 'manager', 'owner', 'admin']::public.app_role[]));
create policy catalog_admin_insert
  on public.motorcycles
  for insert
  to authenticated
  with check (public.has_any_role(array['manager', 'owner', 'admin']::public.app_role[]));
create policy catalog_admin_update
  on public.motorcycles
  for update
  to authenticated
  using (public.has_any_role(array['manager', 'owner', 'admin']::public.app_role[]))
  with check (public.has_any_role(array['manager', 'owner', 'admin']::public.app_role[]));
-- Preserve inventory history: no authenticated role can hard-delete catalog rows.
revoke delete on table public.motorcycles from authenticated;

-- Staff may change only request status, not ownership or submitted customer details.
revoke update on table public.customer_requests from authenticated;
grant update(status) on table public.customer_requests to authenticated;

drop policy if exists request_staff on public.customer_requests;
create policy request_staff_status_update
  on public.customer_requests
  for update
  to authenticated
  using (public.has_any_role(array['employee', 'manager', 'owner', 'admin']::public.app_role[]))
  with check (public.has_any_role(array['employee', 'manager', 'owner', 'admin']::public.app_role[]));

commit;
