begin;

alter table public.customer_requests
  alter column client_user_id drop not null;
alter table public.customer_requests
  add column if not exists requester_name text,
  add column if not exists requester_phone text,
  add column if not exists requester_email text,
  add column if not exists preferred_contact text not null default 'phone';

do $contact_checks$
begin
  if not exists (select 1 from pg_constraint where conrelid='public.customer_requests'::regclass and conname='customer_requests_preferred_contact_check') then
    alter table public.customer_requests add constraint customer_requests_preferred_contact_check
      check (preferred_contact in ('phone','whatsapp','email','sms'));
  end if;
end
$contact_checks$;

drop policy if exists request_guest_create on public.customer_requests;
create policy request_guest_create on public.customer_requests
for insert to anon with check (
  client_user_id is null
  and status = 'pending'::public.request_status
  and length(btrim(coalesce(requester_name,''))) between 2 and 120
  and (
    length(btrim(coalesce(requester_phone,''))) between 7 and 32
    or length(btrim(coalesce(requester_email,''))) between 5 and 254
  )
  and preferred_contact in ('phone','whatsapp','email','sms')
);

grant insert (motorcycle_id, requested_name, requested_model_year, budget, notes,
              requester_name, requester_phone, requester_email, preferred_contact)
on public.customer_requests to anon;

drop policy if exists request_create on public.customer_requests;
create policy request_create on public.customer_requests
for insert to authenticated with check (
  client_user_id = (select auth.uid())
  and status = 'pending'::public.request_status
);
grant insert (client_user_id, motorcycle_id, requested_name, requested_model_year,
              budget, notes, requester_name, requester_phone, requester_email, preferred_contact)
on public.customer_requests to authenticated;

alter table public.contact_messages
  add column if not exists phone text,
  add column if not exists preferred_contact text not null default 'email',
  add column if not exists status text not null default 'new';

do $contact_message_checks$
begin
  if not exists (select 1 from pg_constraint where conrelid='public.contact_messages'::regclass and conname='contact_messages_preferred_contact_check') then
    alter table public.contact_messages add constraint contact_messages_preferred_contact_check
      check (preferred_contact in ('phone','whatsapp','email','sms'));
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.contact_messages'::regclass and conname='contact_messages_status_check') then
    alter table public.contact_messages add constraint contact_messages_status_check
      check (status in ('new','in_progress','replied','closed'));
  end if;
end
$contact_message_checks$;

grant insert (sender_user_id, name, email, message, phone, preferred_contact)
on public.contact_messages to anon, authenticated;
grant select, update (status) on public.contact_messages to authenticated;

create table if not exists public.customer_request_replies (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.customer_requests(id) on delete restrict,
  reply_body text not null check (length(btrim(reply_body)) between 1 and 10000),
  channel text not null check (channel in ('phone','whatsapp','email','sms','internal')),
  sent_by uuid not null references auth.users(id) on delete restrict,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.contact_message_replies (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.contact_messages(id) on delete restrict,
  reply_body text not null check (length(btrim(reply_body)) between 1 and 10000),
  channel text not null check (channel in ('phone','whatsapp','email','sms','internal')),
  sent_by uuid not null references auth.users(id) on delete restrict,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists customer_request_replies_request_idx on public.customer_request_replies(request_id, created_at desc);
create index if not exists contact_message_replies_message_idx on public.contact_message_replies(message_id, created_at desc);
create index if not exists customer_requests_created_at_idx on public.customer_requests(created_at desc);
create index if not exists contact_messages_created_at_idx on public.contact_messages(created_at desc);

alter table public.customer_request_replies enable row level security;
alter table public.contact_message_replies enable row level security;
revoke all on public.customer_request_replies, public.contact_message_replies from anon, authenticated;
grant select, insert on public.customer_request_replies, public.contact_message_replies to authenticated;

create policy customer_request_replies_staff_read on public.customer_request_replies
for select to authenticated using (
  public.has_any_role(array['manager','owner','admin']::public.app_role[])
  or public.has_employee_permission('requests_view')
  or public.has_employee_permission('requests_manage')
);
create policy customer_request_replies_staff_insert on public.customer_request_replies
for insert to authenticated with check (
  sent_by = (select auth.uid())
  and (
    public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('requests_manage')
  )
);

drop policy if exists contact_messages_staff_read on public.contact_messages;
create policy contact_messages_staff_read on public.contact_messages
for select to authenticated using (
  public.has_any_role(array['manager','owner','admin']::public.app_role[])
  or public.has_employee_permission('requests_view')
  or public.has_employee_permission('requests_manage')
  or public.has_employee_permission('customer_data_view')
);
drop policy if exists contact_messages_staff_update on public.contact_messages;
create policy contact_messages_staff_update on public.contact_messages
for update to authenticated using (
  public.has_any_role(array['manager','owner','admin']::public.app_role[])
  or public.has_employee_permission('requests_manage')
) with check (
  public.has_any_role(array['manager','owner','admin']::public.app_role[])
  or public.has_employee_permission('requests_manage')
);
create policy contact_message_replies_staff_read on public.contact_message_replies
for select to authenticated using (
  public.has_any_role(array['manager','owner','admin']::public.app_role[])
  or public.has_employee_permission('requests_view')
  or public.has_employee_permission('requests_manage')
  or public.has_employee_permission('customer_data_view')
);
create policy contact_message_replies_staff_insert on public.contact_message_replies
for insert to authenticated with check (
  sent_by = (select auth.uid())
  and (
    public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('requests_manage')
  )
);
commit;