begin;

grant delete on public.customer_requests, public.customer_request_replies to authenticated;

drop policy if exists request_closed_delete on public.customer_requests;
create policy request_closed_delete on public.customer_requests
for delete to authenticated
using (
  status in ('rejected'::public.request_status, 'completed'::public.request_status, 'expired'::public.request_status)
  and public.has_any_role(array['manager','owner','admin']::public.app_role[])
);

drop policy if exists request_reply_delete on public.customer_request_replies;
create policy request_reply_delete on public.customer_request_replies
for delete to authenticated
using (public.has_any_role(array['manager','owner','admin']::public.app_role[]));

create or replace function public.delete_closed_customer_request(p_request_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_status public.request_status;
begin
  if not public.has_any_role(array['manager','owner','admin']::public.app_role[]) then
    raise exception 'Only management can delete closed customer requests' using errcode = '42501';
  end if;
  select status into v_status from public.customer_requests where id = p_request_id for update;
  if not found then raise exception 'Customer request not found' using errcode = 'P0002'; end if;
  if v_status not in ('rejected'::public.request_status, 'completed'::public.request_status, 'expired'::public.request_status) then
    raise exception 'Only rejected, completed, or expired requests can be deleted' using errcode = '22023';
  end if;
  delete from public.customer_request_replies where request_id = p_request_id;
  delete from public.customer_requests where id = p_request_id;
end;
$$;

revoke all on function public.delete_closed_customer_request(uuid) from public, anon;
grant execute on function public.delete_closed_customer_request(uuid) to authenticated;

commit;