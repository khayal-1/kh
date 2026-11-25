-- Owner-only operational reset and transactional restore.
create or replace function public.owner_reset_operational_data(p_owner_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_tables text;
begin
  if p_owner_id is null or not exists (
    select 1 from public.user_roles
    where user_id = p_owner_id and role = 'owner'::public.app_role
  ) then
    raise exception 'Owner authorization required' using errcode = '42501';
  end if;

  select string_agg(format('%I.%I', 'public', table_name), ', ' order by table_name)
    into v_tables
  from information_schema.tables
  where table_schema = 'public'
    and table_type = 'BASE TABLE'
    and table_name not in ('profiles','user_roles','employee_permissions','accounting_accounts','cash_accounts','finance_settings','tax_rates','audit_logs');

  if v_tables is not null then
    execute 'truncate table ' || v_tables || ' restart identity';
  end if;

  delete from public.user_roles
   where user_id <> p_owner_id or role <> 'owner'::public.app_role;
  delete from public.profiles where id <> p_owner_id;
  delete from public.employee_permissions where user_id <> p_owner_id;

  return jsonb_build_object('ok', true, 'preserved', jsonb_build_array(
    'owner account', 'owner role', 'owner permissions', 'accounting_accounts', 'cash_accounts',
    'finance_settings', 'tax_rates', 'audit_logs'
  ));
end;
$$;

create or replace function public.owner_restore_operational_data(p_owner_id uuid, p_backup jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_table text;
  v_rows jsonb;
  v_sql text;
  v_columns text;
  v_select_columns text;
  v_fk record;
  v_invalid boolean;
  v_inserted integer := 0;
  v_count integer;
  v_max_identity bigint;
  v_identity record;
begin
  if p_owner_id is null or not exists (
    select 1 from public.user_roles
    where user_id = p_owner_id and role = 'owner'::public.app_role
  ) then
    raise exception 'Owner authorization required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_backup) <> 'object'
     or p_backup->>'format' <> 'khayal-backup'
     or coalesce((p_backup->>'version')::integer, 0) <> 1
     or jsonb_typeof(p_backup->'tables') <> 'object'
     or (select count(*) from jsonb_object_keys(p_backup->'tables')) <> (
       select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'
     ) then
    raise exception 'Unsupported or invalid backup format';
  end if;

  perform public.owner_reset_operational_data(p_owner_id);
  perform set_config('session_replication_role', 'replica', true);

  for v_table, v_rows in
    select key, value from jsonb_each(p_backup->'tables')
  loop
    if v_table in ('accounting_accounts','cash_accounts','finance_settings','tax_rates','audit_logs') then
      continue;
    end if;
    if not exists (
      select 1 from information_schema.tables
      where table_schema='public' and table_name=v_table and table_type='BASE TABLE'
    ) then
      raise exception 'Backup contains an unknown table: %', v_table;
    end if;
    if jsonb_typeof(v_rows) <> 'array' then
      raise exception 'Invalid row collection for table %', v_table;
    end if;

    if v_table = 'profiles' then
      select coalesce(jsonb_agg(value), '[]'::jsonb) into v_rows
      from jsonb_array_elements(v_rows) where value->>'id' <> p_owner_id::text;
    elsif v_table = 'user_roles' then
      select coalesce(jsonb_agg(value), '[]'::jsonb) into v_rows
      from jsonb_array_elements(v_rows) where value->>'user_id' <> p_owner_id::text;
    elsif v_table = 'employee_permissions' then
      select coalesce(jsonb_agg(value), '[]'::jsonb) into v_rows
      from jsonb_array_elements(v_rows) where value->>'user_id' <> p_owner_id::text;
    end if;

    if jsonb_array_length(v_rows) = 0 then continue; end if;
    select string_agg(format('%I', column_name), ', ' order by ordinal_position),
           string_agg(format('r.%I', column_name), ', ' order by ordinal_position)
      into v_columns, v_select_columns
    from information_schema.columns
    where table_schema='public' and table_name=v_table and is_generated='NEVER';
    if v_columns is null then
      raise exception 'No insertable columns found for table %', v_table;
    end if;
    v_sql := format(
      'insert into public.%I (%s) overriding system value select %s from jsonb_populate_recordset(null::public.%I, $1) as r',
      v_table, v_columns, v_select_columns, v_table
    );
    execute v_sql using v_rows;
    get diagnostics v_count = row_count;
    v_inserted := v_inserted + v_count;
  end loop;

  perform set_config('session_replication_role', 'origin', true);

  -- Validate every public-schema FK before commit; any orphan aborts the whole restore.
  for v_fk in
    select child_ns.nspname as child_schema, child.relname as child_table,
           parent_ns.nspname as parent_schema, parent.relname as parent_table,
           string_agg(format('c.%I = p.%I', child_col.attname, parent_col.attname), ' and ' order by key_col.ord) as join_sql,
           string_agg(format('c.%I is not null', child_col.attname), ' and ' order by key_col.ord) as not_null_sql
    from pg_constraint con
    join pg_class child on child.oid=con.conrelid
    join pg_namespace child_ns on child_ns.oid=child.relnamespace
    join pg_class parent on parent.oid=con.confrelid
    join pg_namespace parent_ns on parent_ns.oid=parent.relnamespace
    join lateral unnest(con.conkey, con.confkey) with ordinality as key_col(child_attnum,parent_attnum,ord) on true
    join pg_attribute child_col on child_col.attrelid=child.oid and child_col.attnum=key_col.child_attnum
    join pg_attribute parent_col on parent_col.attrelid=parent.oid and parent_col.attnum=key_col.parent_attnum
    where con.contype='f' and child_ns.nspname='public' and parent_ns.nspname in ('public','auth')
    group by child_ns.nspname,child.relname,parent_ns.nspname,parent.relname,con.oid
  loop
    v_sql := format(
      'select exists (select 1 from %I.%I c left join %I.%I p on %s where %s and p.tableoid is null)',
      v_fk.child_schema,v_fk.child_table,v_fk.parent_schema,v_fk.parent_table,
      v_fk.join_sql,v_fk.not_null_sql
    );
    execute v_sql into v_invalid;
    if v_invalid then
      raise exception 'Restore rejected: foreign-key validation failed for %.%', v_fk.child_schema, v_fk.child_table;
    end if;
  end loop;

  -- Advance identity sequences to avoid collisions after restoration.
  for v_identity in
    select n.nspname as schema_name, c.relname as table_name, a.attname as column_name
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    join pg_attribute a on a.attrelid=c.oid
    where n.nspname='public' and c.relkind='r' and a.attnum>0 and not a.attisdropped
      and a.attidentity in ('a','d')
  loop
    v_sql := format('select max(%I) from %I.%I',v_identity.column_name,v_identity.schema_name,v_identity.table_name);
    execute v_sql into v_max_identity;
    if v_max_identity is not null then
      perform setval(pg_get_serial_sequence(format('%I.%I',v_identity.schema_name,v_identity.table_name),v_identity.column_name), v_max_identity, true);
    end if;
  end loop;

  return jsonb_build_object('ok',true,'inserted_rows',v_inserted,'preserved',jsonb_build_array(
    'owner account', 'owner role', 'accounting_accounts', 'cash_accounts',
    'finance_settings', 'tax_rates', 'audit_logs'
  ));
end;
$$;

revoke all on function public.owner_reset_operational_data(uuid) from public, anon, authenticated;
revoke all on function public.owner_restore_operational_data(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.owner_reset_operational_data(uuid) to service_role;
grant execute on function public.owner_restore_operational_data(uuid,jsonb) to service_role;
