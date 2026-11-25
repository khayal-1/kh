-- Public visitors may browse published motorcycles, but customer-only actions require a customer account.
drop policy if exists request_guest_create on public.customer_requests;

drop policy if exists request_create on public.customer_requests;
create policy request_create
  on public.customer_requests
  for insert
  to authenticated
  with check (
    client_user_id = (select auth.uid())
    and status = 'pending'
    and public.has_any_role(array['customer']::public.app_role[])
    and not public.has_any_role(array['employee','manager','owner','admin']::public.app_role[])
  );

drop policy if exists favorite_self on public.favorites;
create policy favorite_self
  on public.favorites
  for all
  to authenticated
  using (
    user_id = (select auth.uid())
    and public.has_any_role(array['customer']::public.app_role[])
    and not public.has_any_role(array['employee','manager','owner','admin']::public.app_role[])
  )
  with check (
    user_id = (select auth.uid())
    and public.has_any_role(array['customer']::public.app_role[])
    and not public.has_any_role(array['employee','manager','owner','admin']::public.app_role[])
  );

drop policy if exists contact_create on public.contact_messages;
create policy contact_create
  on public.contact_messages
  for insert
  to authenticated
  with check (
    sender_user_id = (select auth.uid())
    and public.has_any_role(array['customer']::public.app_role[])
    and not public.has_any_role(array['employee','manager','owner','admin']::public.app_role[])
    and length(btrim(coalesce(name,''))) between 2 and 120
    and length(btrim(coalesce(message,''))) between 1 and 10000
    and (
      length(btrim(coalesce(phone,''))) between 7 and 32
      or length(btrim(coalesce(email,''))) between 5 and 254
    )
    and preferred_contact in ('phone','whatsapp','email','sms')
  );

-- Keep the public catalogue readable for guests and signed-in users.
drop policy if exists catalog_read on public.motorcycles;
create policy catalog_read
  on public.motorcycles
  for select
  to anon, authenticated
  using (
    status = 'available'
    or public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('catalog_view')
    or public.has_employee_permission('catalog_manage')
  );