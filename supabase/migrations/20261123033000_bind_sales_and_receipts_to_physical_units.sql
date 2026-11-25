begin;

-- Physical acquisition cost belongs to a specific motorcycle unit. Keep the
-- model-level cost as a fallback for legacy stock only.
alter table public.motorcycle_units
  add column if not exists unit_cost numeric(14,2) check (unit_cost is null or unit_cost >= 0);

-- Every received physical unit is traceable to the exact receipt line.
create table if not exists public.purchase_receipt_units (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.purchase_receipts(id) on delete restrict,
  receipt_item_id uuid not null references public.purchase_receipt_items(id) on delete restrict,
  purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete restrict,
  motorcycle_unit_id uuid not null unique references public.motorcycle_units(id) on delete restrict,
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  created_at timestamptz not null default now()
);
create index if not exists purchase_receipt_units_receipt_idx
  on public.purchase_receipt_units(receipt_id);
create index if not exists purchase_receipt_units_po_item_idx
  on public.purchase_receipt_units(purchase_order_item_id);

alter table public.purchase_receipt_units enable row level security;
revoke all on public.purchase_receipt_units from anon,authenticated;
grant select on public.purchase_receipt_units to authenticated;
create policy purchase_receipt_units_read on public.purchase_receipt_units
  for select to authenticated using (public.can_manage_purchasing());

-- The trigger honors a unit explicitly selected by a VIN sale. Legacy bulk POS
-- still uses deterministic automatic allocation until its UI is migrated.
create or replace function private.post_sale_item_cogs()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  c uuid;
  i uuid;
  j uuid;
  v numeric(14,2);
  v_unit_id uuid;
  v_updated integer := 0;
  v_explicit_unit text := nullif(current_setting('ekm.sale_unit_id', true),'');
begin
  if v_explicit_unit is not null then
    begin
      v_unit_id := v_explicit_unit::uuid;
    exception when others then
      raise exception 'معرّف الوحدة المحددة غير صالح' using errcode='22023';
    end;
    update public.motorcycle_units
       set unit_status='sold', sale_item_id=new.id
     where id=v_unit_id
       and motorcycle_id=new.motorcycle_id
       and unit_status='available';
    get diagnostics v_updated = row_count;
    if v_updated <> new.quantity then
      raise exception 'الوحدة المحددة لم تعد متاحة أو لا تطابق طراز الدراجة؛ ألغيت العملية بالكامل'
        using errcode='23514';
    end if;
  else
    with picked as (
      select id
        from public.motorcycle_units
       where motorcycle_id=new.motorcycle_id and unit_status='available'
       order by registered_at,id
       limit new.quantity
       for update skip locked
    )
    update public.motorcycle_units u
       set unit_status='sold', sale_item_id=new.id
      from picked
     where u.id=picked.id;
    get diagnostics v_updated = row_count;
    if v_updated <> new.quantity then
      raise exception 'لا توجد وحدة مسجلة متاحة لكل كمية البيع؛ لم يتم اعتماد الفاتورة'
        using errcode='23514';
    end if;
  end if;

  if new.unit_cost is not null and new.unit_cost>0 then
    select id into c from public.accounting_accounts where code='5000' and is_active;
    select id into i from public.accounting_accounts where code='1200' and is_active;
    v:=round(new.unit_cost*new.quantity,2);
    insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
    select s.created_at::date,'تكلفة بضاعة فاتورة '||s.invoice_number,'sale_cogs',new.id,s.created_by
      from public.sales s where s.id=new.sale_id returning id into j;
    if j is null or c is null or i is null then
      raise exception 'حسابات تكلفة البضاعة أو المخزون غير مهيأة؛ ألغيت عملية البيع'
        using errcode='23514';
    end if;
    insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
    values(j,c,v,0,'تكلفة البضاعة المباعة'),(j,i,0,v,'تخفيض قيمة المخزون');
  end if;

  update public.sales s
     set costing_status=case when exists(
       select 1 from public.sale_items si
        where si.sale_id=new.sale_id and si.unit_cost is null
     ) then 'incomplete' else 'complete' end
   where s.id=new.sale_id;
  return new;
end;
$$;

-- Atomic, VIN-specific showroom sale used by the barcode/VIN scanner.
create or replace function private.create_showroom_sale_for_unit_impl(
  p_unit_id uuid,
  p_customer_user_id uuid default null,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_payment_amount numeric default 0,
  p_payment_method text default null,
  p_payment_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  u public.motorcycle_units%rowtype;
  b public.motorcycles%rowtype;
  cl public.clients%rowtype;
  v_customer_id uuid;
  v_customer_name text;
  v_customer_phone text;
  v_sale_id uuid;
  v_item_id uuid;
  v_invoice text;
  v_paid numeric(14,2):=coalesce(p_payment_amount,0);
  v_total numeric(14,2);
  v_status text;
  v_cost numeric(14,2);
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception 'ليس لديك صلاحية تسجيل المبيعات' using errcode='42501';
  end if;
  if p_unit_id is null or v_paid<0 then
    raise exception 'بيانات الوحدة أو الدفعة غير صحيحة' using errcode='22023';
  end if;

  select * into u from public.motorcycle_units where id=p_unit_id for update;
  if not found or u.unit_status<>'available' then
    raise exception 'هذه الوحدة غير موجودة أو لم تعد متاحة للبيع' using errcode='23514';
  end if;
  select * into b from public.motorcycles where id=u.motorcycle_id for update;
  if not found or b.status<>'available'::public.motorcycle_status then
    raise exception 'طراز الدراجة غير متاح للبيع' using errcode='23514';
  end if;
  if b.stock<1 then
    raise exception 'رصيد الطراز لا يحتوي على وحدة متاحة' using errcode='23514';
  end if;

  if p_customer_user_id is not null then
    select * into cl from public.clients where user_id=p_customer_user_id for share;
    if not found then
      raise exception 'حساب العميل المحدد غير مرتبط بملف عميل' using errcode='P0002';
    end if;
    v_customer_id:=cl.id;
    v_customer_name:=coalesce(nullif(btrim(cl.display_name),''),nullif(btrim(p_customer_name),''),'عميل');
    v_customer_phone:=coalesce(nullif(btrim(cl.phone),''),nullif(btrim(p_customer_phone),''),'');
  else
    v_customer_name:=coalesce(nullif(btrim(p_customer_name),''),'عميل نقدي');
    v_customer_phone:=nullif(btrim(coalesce(p_customer_phone,'')),'');
    insert into public.clients(user_id,display_name,phone)
    values(null,v_customer_name,v_customer_phone)
    returning id into v_customer_id;
  end if;

  v_total:=round(b.price,2);
  if v_paid>v_total then
    raise exception 'المبلغ المدفوع أكبر من إجمالي الفاتورة' using errcode='23514';
  end if;
  if v_paid>0 and coalesce(p_payment_method,'') not in ('cash','bank_transfer','card','other') then
    raise exception 'طريقة الدفع غير صحيحة' using errcode='22023';
  end if;

  v_invoice:='EKM-'||to_char(now(),'YYYYMMDD')||'-'||
    lpad(nextval('public.sale_invoice_number_seq')::text,6,'0');
  v_status:=case when v_paid=0 then 'unpaid' when v_paid<v_total then 'partial' else 'paid' end;

  insert into public.sales(
    invoice_number,customer_id,customer_name,customer_phone,channel,
    subtotal,total,amount_paid,payment_status,notes,created_by
  ) values (
    v_invoice,v_customer_id,v_customer_name,nullif(v_customer_phone,''),'showroom',
    v_total,v_total,v_paid,v_status,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())
  ) returning id into v_sale_id;

  v_cost:=coalesce(u.unit_cost,(select unit_cost from public.motorcycle_inventory_costs where motorcycle_id=b.id));
  perform set_config('ekm.sale_unit_id',u.id::text,true);
  insert into public.sale_items(
    sale_id,motorcycle_id,motorcycle_name,model_year,unit_price,quantity,line_total,unit_cost
  ) values (
    v_sale_id,b.id,b.name,b.model_year,b.price,1,b.price,v_cost
  ) returning id into v_item_id;
  perform set_config('ekm.sale_unit_id','',true);

  perform set_config('ekm.stock_movement_source','sale',true);
  update public.motorcycles set stock=stock-1 where id=b.id;
  perform set_config('ekm.stock_movement_source','',true);
  insert into public.stock_movements(
    motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by
  ) values(b.id,'sale',-1,v_sale_id,'بيع الوحدة '||u.vin||' ضمن فاتورة '||v_invoice,(select auth.uid()));

  if v_paid>0 then
    insert into public.payments(sale_id,amount,method,reference,received_by)
    values(v_sale_id,v_paid,p_payment_method,nullif(btrim(coalesce(p_payment_reference,'')),''),(select auth.uid()));
  end if;

  return jsonb_build_object(
    'id',v_sale_id,'sale_id',v_sale_id,'sale_item_id',v_item_id,'created_at',now(),
    'invoice_number',v_invoice,'customer_id',v_customer_id,
    'customer_name',v_customer_name,'customer_phone',v_customer_phone,
    'motorcycle_id',b.id,'motorcycle_name',b.name,'model_year',b.model_year,
    'unit_id',u.id,'vin',u.vin,'engine_number',u.engine_number,
    'unit_price',b.price,'total',v_total,'amount_paid',v_paid,
    'balance_due',v_total-v_paid,'payment_status',v_status
  );
end;
$$;

revoke all on function private.create_showroom_sale_for_unit_impl(uuid,uuid,text,text,numeric,text,text,text) from public,anon;
grant execute on function private.create_showroom_sale_for_unit_impl(uuid,uuid,text,text,numeric,text,text,text) to authenticated;

create or replace function public.create_showroom_sale_for_unit(
  p_unit_id uuid,
  p_customer_user_id uuid default null,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_payment_amount numeric default 0,
  p_payment_method text default null,
  p_payment_reference text default null,
  p_notes text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select private.create_showroom_sale_for_unit_impl($1,$2,$3,$4,$5,$6,$7,$8);
$$;
revoke all on function public.create_showroom_sale_for_unit(uuid,uuid,text,text,numeric,text,text,text) from public,anon;
grant execute on function public.create_showroom_sale_for_unit(uuid,uuid,text,text,numeric,text,text,text) to authenticated;

-- Receive physical units, not just a model quantity. Each VIN and cost is
-- committed in the same transaction as the receipt, stock movement and GRNI.
create or replace function private.receive_supplier_purchase_order_units_impl(
  p_order_id uuid,
  p_items jsonb,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  o public.purchase_orders%rowtype;
  poi public.purchase_order_items%rowtype;
  item jsonb;
  unit jsonb;
  receipt_id uuid;
  receipt_number text;
  receipt_item_id uuid;
  unit_id uuid;
  qty integer;
  total_qty integer:=0;
  all_received boolean;
  vin_value text;
  engine_value text;
  condition_value text;
  unit_cost_value numeric(14,2);
begin
  if (select auth.uid()) is null or not public.can_manage_purchasing() then
    raise exception 'ليس لديك صلاحية استلام التوريد' using errcode='42501';
  end if;
  select * into o from public.purchase_orders where id=p_order_id for update;
  if not found or o.status='cancelled' or o.status='received' then
    raise exception 'أمر التوريد غير موجود أو مغلق' using errcode='P0002';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>20 then
    raise exception 'يجب تحديد بند واحد على الأقل للاستلام' using errcode='22023';
  end if;

  receipt_number:='GR-'||to_char(now(),'YYYYMMDD')||'-'||
    lpad(nextval('public.supplier_receipt_number_seq')::text,6,'0');
  insert into public.purchase_receipts(receipt_number,purchase_order_id,received_by,notes)
  values(receipt_number,p_order_id,(select auth.uid()),nullif(btrim(coalesce(p_notes,'')),''))
  returning id into receipt_id;

  perform set_config('ekm.stock_movement_source','purchase_receipt',true);
  perform set_config('ekm.stock_movement_reference',receipt_id::text,true);

  for item in select value from jsonb_array_elements(p_items) as x(value) loop
    begin
      select * into poi from public.purchase_order_items
       where id=(item->>'purchase_order_item_id')::uuid
         and purchase_order_id=p_order_id for update;
    exception when invalid_text_representation then
      raise exception 'بند أمر الشراء غير صالح' using errcode='22023';
    end;
    if not found then
      raise exception 'بند التوريد غير تابع لأمر الشراء' using errcode='P0002';
    end if;
    if jsonb_typeof(item->'units') is distinct from 'array'
       or jsonb_array_length(item->'units')<1 then
      raise exception 'أدخل بيانات كل وحدة مستلمة ورقم شاسيهها' using errcode='22023';
    end if;
    qty:=jsonb_array_length(item->'units');
    if qty>poi.quantity_ordered-poi.quantity_received then
      raise exception 'عدد الوحدات المستلمة أكبر من الكمية المتبقية في أمر الشراء' using errcode='23514';
    end if;
    unit_cost_value:=poi.unit_cost;
    insert into public.purchase_receipt_items(
      receipt_id,purchase_order_item_id,motorcycle_id,quantity,unit_cost
    ) values(receipt_id,poi.id,poi.motorcycle_id,qty,unit_cost_value)
    returning id into receipt_item_id;

    for unit in select value from jsonb_array_elements(item->'units') as x(value) loop
      vin_value:=regexp_replace(upper(btrim(coalesce(unit->>'vin',''))),'\s+','','g');
      engine_value:=nullif(regexp_replace(upper(btrim(coalesce(unit->>'engine_number',''))),'\s+','','g'),'');
      condition_value:=coalesce(unit->>'unit_condition','new');
      if vin_value='' or condition_value not in ('new','used')
         or coalesce((unit->>'odometer_reading')::integer,0)<0 then
        raise exception 'رقم الشاسيه أو بيانات الوحدة غير صحيحة' using errcode='22023';
      end if;
      insert into public.motorcycle_units(
        motorcycle_id,vin,engine_number,barcode,unit_status,unit_cost,
        odometer_reading,unit_condition,warranty_start,warranty_end,notes,registered_by
      ) values (
        poi.motorcycle_id,vin_value,engine_value,
        nullif(btrim(coalesce(unit->>'barcode','')),''),'available',unit_cost_value,
        coalesce((unit->>'odometer_reading')::integer,0),condition_value,
        nullif(unit->>'warranty_start','')::date,nullif(unit->>'warranty_end','')::date,
        nullif(btrim(coalesce(unit->>'notes','')),''),(select auth.uid())
      ) returning id into unit_id;
      insert into public.purchase_receipt_units(
        receipt_id,receipt_item_id,purchase_order_item_id,motorcycle_unit_id,unit_cost
      ) values(receipt_id,receipt_item_id,poi.id,unit_id,unit_cost_value);
    end loop;

    update public.purchase_order_items
       set quantity_received=quantity_received+qty
     where id=poi.id;
    update public.motorcycles set stock=stock+qty where id=poi.motorcycle_id;
    total_qty:=total_qty+qty;
  end loop;

  select bool_and(quantity_received=quantity_ordered) into all_received
    from public.purchase_order_items where purchase_order_id=p_order_id;
  update public.purchase_orders
     set status=case when all_received then 'received' else 'partially_received' end,
         updated_at=now()
   where id=p_order_id;

  return jsonb_build_object(
    'receipt_id',receipt_id,'receipt_number',receipt_number,
    'quantity_received',total_qty,
    'status',case when all_received then 'received' else 'partially_received' end
  );
end;
$$;
revoke all on function private.receive_supplier_purchase_order_units_impl(uuid,jsonb,text) from public,anon;
grant execute on function private.receive_supplier_purchase_order_units_impl(uuid,jsonb,text) to authenticated;

create or replace function public.receive_supplier_purchase_order_units(
  p_order_id uuid,p_items jsonb,p_notes text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select private.receive_supplier_purchase_order_units_impl($1,$2,$3);
$$;
revoke all on function public.receive_supplier_purchase_order_units(uuid,jsonb,text) from public,anon;
grant execute on function public.receive_supplier_purchase_order_units(uuid,jsonb,text) to authenticated;

commit;
