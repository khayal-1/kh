begin;
drop policy if exists contact_create on public.contact_messages;
create policy contact_create on public.contact_messages
for insert to anon, authenticated with check (
  (sender_user_id is null or sender_user_id = (select auth.uid()))
  and length(btrim(coalesce(name,''))) between 2 and 120
  and length(btrim(coalesce(message,''))) between 1 and 10000
  and (
    length(btrim(coalesce(phone,''))) between 7 and 32
    or length(btrim(coalesce(email,''))) between 5 and 254
  )
  and preferred_contact in ('phone','whatsapp','email','sms')
);

revoke insert on public.customer_requests from anon, authenticated;
grant insert (client_user_id, motorcycle_id, requested_name, requested_model_year,
              budget, notes, requester_name, requester_phone, requester_email, preferred_contact)
on public.customer_requests to anon, authenticated;

revoke insert on public.contact_messages from anon, authenticated;
grant insert (sender_user_id, name, email, message, phone, preferred_contact)
on public.contact_messages to anon, authenticated;

revoke insert on public.customer_request_replies, public.contact_message_replies from authenticated;
grant insert (request_id, reply_body, channel, sent_by, sent_at)
on public.customer_request_replies to authenticated;
grant insert (message_id, reply_body, channel, sent_by, sent_at)
on public.contact_message_replies to authenticated;
commit;