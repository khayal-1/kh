begin;

revoke delete on table public.customer_requests from authenticated;
grant select, insert, update on table public.customer_requests to authenticated;

drop policy if exists request_staff on public.customer_requests;
create policy request_staff
  on public.customer_requests
  for update
  to authenticated
  using (public.has_any_role(array['employee', 'manager', 'owner', 'admin']::public.app_role[]))
  with check (public.has_any_role(array['employee', 'manager', 'owner', 'admin']::public.app_role[]));

commit;
