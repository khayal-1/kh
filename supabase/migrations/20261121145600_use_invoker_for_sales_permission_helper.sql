create or replace function public.can_manage_sales()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select
    public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('sales_manage');
$$;