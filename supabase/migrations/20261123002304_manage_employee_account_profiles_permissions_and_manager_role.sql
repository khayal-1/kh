create or replace function public.manage_employee_account(
 p_user_id uuid,p_actor_id uuid,p_full_name text,p_phone text,p_permissions text[],p_role text
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
 v_actor_roles public.app_role[]; v_target_roles public.app_role[];
 v_permissions text[] := coalesce(p_permissions,array[]::text[]);
begin
 if p_user_id is null or p_actor_id is null or p_user_id=p_actor_id then raise exception 'Invalid employee account.'; end if;
 if p_full_name is null or length(btrim(p_full_name)) not between 1 and 120 then raise exception 'Name must be 1–120 characters.'; end if;
 if length(coalesce(p_phone,''))>32 then raise exception 'Phone number must be 32 characters or fewer.'; end if;
 if p_role not in ('employee','manager') then raise exception 'Unsupported account role.'; end if;
 if cardinality(v_permissions)>9
  or exists(select 1 from unnest(v_permissions) as item(permission) where permission not in
   ('catalog_view','catalog_manage','requests_view','requests_manage','customer_data_view','sales_manage','expenses_manage','accounting_view','finance_manage'))
  or cardinality(v_permissions)<>(select count(distinct permission) from unnest(v_permissions) as item(permission)) then
  raise exception 'Choose only available employee permissions.';
 end if;
 if 'customer_data_view'=any(v_permissions) and not ('requests_view'=any(v_permissions) or 'requests_manage'=any(v_permissions)) then
  raise exception 'Customer names and phones require customer request access.';
 end if;
 select array_agg(role) into v_actor_roles from public.user_roles where user_id=p_actor_id;
 if not (coalesce(v_actor_roles,array[]::public.app_role[]) && array['owner','admin','manager']::public.app_role[]) then
  raise exception 'Only management can edit employee accounts.';
 end if;
 select array_agg(role) into v_target_roles from public.user_roles where user_id=p_user_id;
 if v_target_roles is null or not ('employee'=any(v_target_roles) or 'manager'=any(v_target_roles))
  or 'owner'=any(v_target_roles) or 'admin'=any(v_target_roles) then
  raise exception 'The selected account is not an editable employee account.';
 end if;
 if 'manager'=any(v_actor_roles) and not ('owner'=any(v_actor_roles) or 'admin'=any(v_actor_roles)) then
  if 'manager'=any(v_target_roles) or p_role<>'employee' then raise exception 'Assistant managers can only manage regular employees.'; end if;
 end if;
 update public.profiles set full_name=btrim(p_full_name),phone=nullif(btrim(coalesce(p_phone,'')),''),updated_at=now() where id=p_user_id;
 if not found then raise exception 'Employee profile was not found.'; end if;
 delete from public.employee_permissions where user_id=p_user_id;
 if cardinality(v_permissions)>0 then
  insert into public.employee_permissions(user_id,permission_key,granted_by)
  select p_user_id,permission,p_actor_id from unnest(v_permissions) as item(permission);
 end if;
 delete from public.user_roles where user_id=p_user_id and role in ('employee'::public.app_role,'manager'::public.app_role);
 insert into public.user_roles(user_id,role,assigned_by) values(p_user_id,p_role::public.app_role,p_actor_id);
 return jsonb_build_object('success',true,'role',p_role);
end;
$$;
revoke all on function public.manage_employee_account(uuid,uuid,text,text,text[],text) from public,anon,authenticated;
grant execute on function public.manage_employee_account(uuid,uuid,text,text,text[],text) to service_role;
