-- Keep anonymous catalogue reads independent from authenticated staff permission helpers.
-- This avoids requiring anon to execute internal role-checking functions.
drop policy if exists catalog_read on public.motorcycles;
drop policy if exists catalog_public_read on public.motorcycles;

create policy catalog_anon_read_available
on public.motorcycles
for select
to anon
using (status = 'available');

create policy catalog_authenticated_read
on public.motorcycles
for select
to authenticated
using (
  status = 'available'
  or public.has_any_role(array['employee','manager','owner','admin']::public.app_role[])
  or public.has_employee_permission('catalog_view')
  or public.has_employee_permission('catalog_manage')
);
