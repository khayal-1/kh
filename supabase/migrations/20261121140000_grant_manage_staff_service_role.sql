-- Grant only the public-table privileges used by manage-staff.
-- The function still verifies the caller's manager/owner/admin role before any action.
grant select, insert, update, delete on table public.user_roles to service_role;
grant select on table public.profiles to service_role;
grant delete on table public.clients to service_role;
grant select, insert on table public.employee_permissions to service_role;
