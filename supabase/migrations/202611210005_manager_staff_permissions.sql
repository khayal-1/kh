begin;

-- Foundational employee permission storage. This migration must precede the
-- staff-management grants, POS permission helper and finance permission checks.
create table if not exists public.employee_permissions (
  user_id uuid not null references auth.users(id) on delete cascade,
  permission_key text not null check (permission_key = any (array[
    'catalog_view','catalog_manage','requests_view','requests_manage',
    'customer_data_view','sales_manage','expenses_manage','accounting_view'
  ]::text[])),
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(user_id,permission_key)
);
create index if not exists employee_permissions_granted_by_idx
  on public.employee_permissions(granted_by);

alter table public.employee_permissions enable row level security;
revoke all on public.employee_permissions from anon,authenticated;
grant select on public.employee_permissions to authenticated;

drop policy if exists employee_permissions_read on public.employee_permissions;
drop policy if exists employee_permissions_read_self_or_manager on public.employee_permissions;
create policy employee_permissions_read_self_or_manager
on public.employee_permissions
for select to authenticated
using (
  user_id=(select auth.uid())
  or public.has_any_role(array['manager','owner','admin']::public.app_role[])
);

create or replace function public.has_employee_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select (select auth.uid()) is not null
     and exists (
       select 1
       from public.employee_permissions ep
       where ep.user_id=(select auth.uid())
         and ep.permission_key=p_permission
     );
$$;
revoke all on function public.has_employee_permission(text) from public,anon;
grant execute on function public.has_employee_permission(text) to authenticated;

commit;
