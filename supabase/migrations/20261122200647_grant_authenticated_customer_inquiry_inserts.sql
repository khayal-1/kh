-- Restore authenticated customer INSERT privileges while keeping anonymous writes disabled.
-- RLS policies continue to restrict inserts to the signed-in customer's own records.
grant insert on public.customer_requests to authenticated;
grant insert on public.contact_messages to authenticated;
