create or replace function private.register_motorcycle_unit_with_opening_cost(
  p_motorcycle_id uuid,
  p_vin text,
  p_engine_number text,
  p_barcode text,
  p_warranty_start date,
  p_warranty_end date,
  p_notes text,
  p_odometer_reading integer,
  p_unit_condition text,
  p_unit_cost numeric
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
  v_stock integer;
  v_previous_stock integer;
  v_previous_average numeric(14,2);
  v_new_average numeric(14,2);
  v_model_is_demo boolean;
  v_inventory_account uuid;
  v_opening_equity_account uuid;
  v_journal_id uuid;
  v_cost numeric(14,2) := round(p_unit_cost,2);
  v_vin text := regexp_replace(upper(btrim(coalesce(p_vin,''))), '[[:space:]]+', '', 'g');
  v_engine text := nullif(regexp_replace(upper(btrim(coalesce(p_engine_number,''))), '[[:space:]]+', '', 'g'),'');
  v_barcode text := nullif(btrim(coalesce(p_barcode,'')),'');
begin
  if (select auth.uid()) is null
     or (not private.can_manage_finance() and not public.has_employee_permission('catalog_manage')) then
    raise exception 'غير مصرح بتسجيل بيانات الوحدة' using errcode='42501';
  end if;

  if p_motorcycle_id is null or v_vin='' or v_cost is null or v_cost<=0
     or p_odometer_reading is null or p_odometer_reading<0
     or coalesce(p_unit_condition,'') not in ('new','used')
     or (p_warranty_end is not null and p_warranty_start is not null and p_warranty_end<p_warranty_start) then
    raise exception 'بيانات الوحدة أو تكلفة الرصيد الافتتاحي غير صحيحة' using errcode='22023';
  end if;

  select is_demo into v_model_is_demo
    from public.motorcycles
   where id=p_motorcycle_id
   for update;
  if not found then
    raise exception 'نوع الدراجة غير موجود' using errcode='P0002';
  end if;
  if coalesce(v_model_is_demo,false) then
    raise exception 'هذا نوع تجريبي؛ أنشئ نوعًا فعليًا قبل تسجيل مخزون المعرض عليه' using errcode='23514';
  end if;

  select count(*)::integer
    into v_previous_stock
    from public.motorcycle_units
   where motorcycle_id=p_motorcycle_id
     and unit_status in ('available','reserved','service');

  select unit_cost into v_previous_average
    from public.motorcycle_inventory_costs
   where motorcycle_id=p_motorcycle_id
   for update;

  if v_previous_stock>0 and (v_previous_average is null or v_previous_average<=0) then
    raise exception 'سجل تكلفة المخزون الحالية للطراز قبل إضافة رصيد افتتاحي جديد' using errcode='23514';
  end if;

  v_new_average := case
    when v_previous_stock=0 then v_cost
    else round(((v_previous_stock*v_previous_average)+v_cost)/(v_previous_stock+1),2)
  end;

  insert into public.motorcycle_units(
    motorcycle_id,vin,engine_number,barcode,odometer_reading,unit_condition,
    unit_cost,warranty_start,warranty_end,notes,registered_by
  ) values (
    p_motorcycle_id,v_vin,v_engine,v_barcode,p_odometer_reading,p_unit_condition,
    v_cost,p_warranty_start,p_warranty_end,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())
  )
  returning id into v_id;

  insert into public.motorcycle_inventory_costs(motorcycle_id,unit_cost,updated_by)
  values(p_motorcycle_id,v_new_average,(select auth.uid()))
  on conflict(motorcycle_id) do update
    set unit_cost=excluded.unit_cost,
        updated_by=excluded.updated_by,
        updated_at=now();

  select id into v_inventory_account
    from public.accounting_accounts where code='1200' and is_active;
  select id into v_opening_equity_account
    from public.accounting_accounts where code='3010' and is_active;
  if v_inventory_account is null or v_opening_equity_account is null then
    raise exception 'حساب المخزون أو رأس المال الافتتاحي غير مهيأ' using errcode='23514';
  end if;

  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
  values(current_date,'إثبات وحدة ضمن الرصيد الافتتاحي — VIN '||v_vin,
         'opening_stock_unit',v_id,(select auth.uid()))
  returning id into v_journal_id;

  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
  values
    (v_journal_id,v_inventory_account,v_cost,0,'إضافة تكلفة وحدة فعلية إلى مخزون المعرض'),
    (v_journal_id,v_opening_equity_account,0,v_cost,'مقابل الرصيد الافتتاحي للمخزون');

  select count(*)::integer into v_stock
    from public.motorcycle_units
   where motorcycle_id=p_motorcycle_id
     and unit_status in ('available','reserved','service');

  perform pg_catalog.set_config('ekm.stock_movement_source','stocktake',true);
  update public.motorcycles set stock=v_stock
   where id=p_motorcycle_id and stock is distinct from v_stock;

  return v_id;
end;
$function$;

revoke all on function private.register_motorcycle_unit_with_opening_cost(uuid,text,text,text,date,date,text,integer,text,numeric) from public,anon;
grant execute on function private.register_motorcycle_unit_with_opening_cost(uuid,text,text,text,date,date,text,integer,text,numeric) to authenticated;

create or replace function public.register_motorcycle_unit_with_engine_number(
  p_motorcycle_id uuid,
  p_vin text,
  p_engine_number text,
  p_barcode text,
  p_warranty_start date,
  p_warranty_end date,
  p_notes text,
  p_odometer_reading integer,
  p_unit_condition text,
  p_unit_cost numeric
)
returns uuid
language sql
set search_path = ''
as $function$
  select private.register_motorcycle_unit_with_opening_cost(
    $1,$2,$3,$4,$5,$6,$7,$8,$9,$10
  );
$function$;

revoke all on function public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text,numeric) from public,anon;
grant execute on function public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text,numeric) to authenticated;

-- Disable older registration entry points that allowed adding unpriced opening stock.
revoke all on function public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text) from public,anon,authenticated;
revoke all on function public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text) from public,anon,authenticated;
revoke all on function private.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text) from public,anon,authenticated;
revoke all on function private.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text) from public,anon,authenticated;
