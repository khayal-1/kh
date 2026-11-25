-- Applied LIVE to the "El Khayal Motors Website" Supabase project on 2026-11-21.
-- Mark as applied on the live project (do not re-run):
--   supabase migration repair --status applied 20261121130000
-- Safe to run on a fresh database.

-- 1) Event-trigger helper must never be callable through the REST API
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- 2) Customers may only create requests in the initial 'pending' state
alter policy request_create on public.customer_requests
  with check (client_user_id = (select auth.uid()) and status = 'pending'::public.request_status);

-- 3) Missing foreign-key indexes
create index if not exists audit_logs_actor_user_id_idx on public.audit_logs (actor_user_id);
create index if not exists contact_messages_sender_user_id_idx on public.contact_messages (sender_user_id);
create index if not exists customer_requests_motorcycle_id_idx on public.customer_requests (motorcycle_id);
create index if not exists employee_permissions_granted_by_idx on public.employee_permissions (granted_by);
create index if not exists favorites_motorcycle_id_idx on public.favorites (motorcycle_id);
create index if not exists motorcycles_created_by_idx on public.motorcycles (created_by);
create index if not exists photo_assets_created_by_idx on public.photo_assets (created_by);
create index if not exists photo_assets_motorcycle_id_idx on public.photo_assets (motorcycle_id);
create index if not exists user_roles_assigned_by_idx on public.user_roles (assigned_by);
