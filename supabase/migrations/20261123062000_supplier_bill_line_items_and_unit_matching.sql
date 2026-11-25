begin;

create table if not exists public.supplier_bill_items (
  id uuid primary key default gen_random_uuid(),
  supplier_bill_id uuid not null references public.supplier_bills(id) on delete restrict,
  line_number integer not null check (line_number > 0),
  line_type text not null check (line_type in ('inventory','direct')),
  purchase_receipt_item_id uuid references public.purchase_receipt_items(id) on delete restrict,
  description text not null check (length(btrim(description)) between 1 and 500),
  quantity integer not null check (quantity > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  constraint supplier_bill_items_line_unique unique (supplier_bill_id,line_number),
  constraint supplier_bill_items_receipt_shape check (
    (line_type='inventory' and purchase_receipt_item_id is not null)
    or (line_type='direct' and purchase_receipt_item_id is null)
  )
);
create index if not exists supplier_bill_items_bill_idx
  on public.supplier_bill_items(supplier_bill_id,line_number);
create index if not exists supplier_bill_items_receipt_idx
  on public.supplier_bill_items(purchase_receipt_item_id);

-- A physical unit can be invoiced only once, even if multiple supplier bills
-- are created against the same receipt or purchase order.
create table if not exists public.supplier_bill_item_units (
  id uuid primary key default gen_random_uuid(),
  supplier_bill_item_id uuid not null references public.supplier_bill_items(id) on delete restrict,
  motorcycle_unit_id uuid not null unique references public.motorcycle_units(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists supplier_bill_item_units_line_idx
  on public.supplier_bill_item_units(supplier_bill_item_id);

alter table public.supplier_bill_items enable row level security;
alter table public.supplier_bill_item_units enable row level security;
revoke all on public.supplier_bill_items,public.supplier_bill_item_units from anon,authenticated;
grant select on public.supplier_bill_items,public.supplier_bill_item_units to authenticated;
drop policy if exists supplier_bill_items_read on public.supplier_bill_items;
create policy supplier_bill_items_read on public.supplier_bill_items
  for select to authenticated using (public.can_manage_purchasing());
drop policy if exists supplier_bill_item_units_read on public.supplier_bill_item_units;
create policy supplier_bill_item_units_read on public.supplier_bill_item_units
  for select to authenticated using (public.can_manage_purchasing());

-- The journal trigger is deferred so the bill header and all detail lines are
-- committed atomically and the ledger sees the complete invoice.
create or replace function private.post_supplier_bill_journal()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  ap uuid;
  grni uuid;
  inv uuid;
  journal_id uuid;
  received_cost numeric(14,2);
  billed numeric(14,2);
  clear_grni numeric(14,2);
  direct_amount numeric(14,2);
  line_row record;
  receipt_item public.purchase_receipt_items%rowtype;
  variance numeric(14,2);
begin
  select id into ap from public.accounting_accounts where code='2010' and is_active;
  select id into grni from public.accounting_accounts where code='2060' and is_active;
  select id into inv from public.accounting_accounts where code='1200' and is_active;
  if ap is null or grni is null or inv is null then
    raise exception 'حسابات الموردين والمخزون والبضاعة المستلمة غير المفوترة غير مهيأة'
      using errcode='23514';
  end if;

  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
  values(new.bill_date,'فاتورة مورد رقم '||new.bill_number,'supplier_bill',new.id,new.created_by)
  returning id into journal_id;

  if exists(select 1 from public.supplier_bill_items where supplier_bill_id=new.id) then
    for line_row in
      select * from public.supplier_bill_items
       where supplier_bill_id=new.id order by line_number
    loop
      if line_row.line_type='inventory' then
        select * into receipt_item
          from public.purchase_receipt_items
         where id=line_row.purchase_receipt_item_id;
        if not found then
          raise exception 'بند الاستلام المرتبط بفاتورة المورد غير موجود' using errcode='23503';
        end if;
        received_cost:=round(line_row.quantity*receipt_item.unit_cost,2);
        variance:=round(line_row.line_total-received_cost,2);
        if received_cost>0 then
          insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
          values(journal_id,grni,received_cost,0,'تسوية تكلفة الوحدات المستلمة المرتبطة ببند الفاتورة');
        end if;
        if variance>0 then
          insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
          values(journal_id,inv,variance,0,'فرق سعر فاتورة المورد عن تكلفة الاستلام');
        elsif variance<0 then
          insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
          values(journal_id,inv,0,abs(variance),'تخفيض تكلفة المخزون حسب فاتورة المورد');
        end if;
      else
        if line_row.line_total>0 then
          insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
          values(journal_id,inv,line_row.line_total,0,'تكلفة أو مصروف مباشر ضمن فاتورة المورد');
        end if;
      end if;
    end loop;
  else
    -- Preserve the historical posting behavior for pre-existing bills.
    if new.purchase_order_id is not null then
      select coalesce(sum(pri.quantity*pri.unit_cost),0) into received_cost
        from public.purchase_receipt_items pri
        join public.purchase_receipts pr on pr.id=pri.receipt_id
       where pr.purchase_order_id=new.purchase_order_id;
      select coalesce(sum(b.total_amount),0) into billed
        from public.supplier_bills b
       where b.purchase_order_id=new.purchase_order_id and b.id<>new.id
         and exists(select 1 from public.journal_entries je
                     where je.source_type='supplier_bill' and je.source_id=b.id);
      clear_grni:=least(new.total_amount,greatest(0,received_cost-billed));
      direct_amount:=new.total_amount-clear_grni;
    else
      clear_grni:=0;
      direct_amount:=new.total_amount;
    end if;
    if clear_grni>0 then
      insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
      values(journal_id,grni,clear_grni,0,'تسوية بضاعة مستلمة غير مفوترة');
    end if;
    if direct_amount>0 then
      insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
      values(journal_id,inv,direct_amount,0,'مشتريات مباشرة أو فاتورة قديمة غير مفصلة');
    end if;
  end if;

  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
  values(journal_id,ap,0,new.total_amount,'إثبات مستحق المورد');
  return new;
end;
$$;

drop trigger if exists supplier_bills_post_journal on public.supplier_bills;
create constraint trigger supplier_bills_post_journal
after insert on public.supplier_bills
deferrable initially deferred
for each row execute function private.post_supplier_bill_journal();

-- Replace the legacy header-only RPC. Every new invoice must contain lines.
revoke all on function public.create_supplier_bill(uuid,text,numeric,date,date,uuid,text)
  from public,anon,authenticated;
drop function public.create_supplier_bill(uuid,text,numeric,date,date,uuid,text);

create or replace function public.create_supplier_bill(
  p_supplier_id uuid,
  p_bill_number text,
  p_total_amount numeric,
  p_bill_date date,
  p_due_date date,
  p_purchase_order_id uuid,
  p_notes text,
  p_items jsonb
) returns public.supplier_bills
language plpgsql
security definer
set search_path=''
as $$
declare
  v_bill public.supplier_bills;
  v_item record;
  v_line_id uuid;
  v_receipt_item public.purchase_receipt_items%rowtype;
  v_unit_ids uuid[];
  v_line_type text;
  v_description text;
  v_quantity integer;
  v_unit_cost numeric(14,2);
  v_line_total numeric(14,2);
  v_total numeric(14,2):=0;
  v_line_count integer:=0;
begin
  if auth.uid() is null or not public.can_manage_purchasing() then
    raise exception 'غير مصرح بإدارة فواتير الموردين' using errcode='42501';
  end if;
  if p_supplier_id is null or nullif(btrim(p_bill_number),'') is null
     or p_total_amount is null or p_total_amount<=0 or p_bill_date is null then
    raise exception 'بيانات فاتورة المورد غير مكتملة أو غير صحيحة' using errcode='22023';
  end if;
  if p_due_date is not null and p_due_date<p_bill_date then
    raise exception 'تاريخ الاستحقاق لا يمكن أن يسبق تاريخ الفاتورة' using errcode='22023';
  end if;
  if not exists(select 1 from public.suppliers s where s.id=p_supplier_id and s.is_active) then
    raise exception 'المورد غير موجود أو موقوف' using errcode='23503';
  end if;
  if p_purchase_order_id is not null then
    perform 1 from public.purchase_orders po
     where po.id=p_purchase_order_id and po.supplier_id=p_supplier_id
       and po.status<>'cancelled' for update;
    if not found then
      raise exception 'أمر التوريد لا يتبع هذا المورد أو أنه ملغى' using errcode='23503';
    end if;
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'يجب إرسال بنود الفاتورة في قائمة صحيحة' using errcode='22023';
  end if;
  if jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>100 then
    raise exception 'يجب إضافة بند واحد على الأقل إلى فاتورة المورد' using errcode='22023';
  end if;

  insert into public.supplier_bills(
    bill_number,supplier_id,purchase_order_id,bill_date,due_date,
    total_amount,notes,created_by
  ) values(
    btrim(p_bill_number),p_supplier_id,p_purchase_order_id,p_bill_date,p_due_date,
    round(p_total_amount,2),nullif(btrim(p_notes),''),auth.uid()
  ) returning * into v_bill;

  for v_item in
    select value,ordinality
      from jsonb_array_elements(p_items) with ordinality as x(value,ordinality)
     order by ordinality
  loop
    begin
      v_line_type:=coalesce(v_item.value->>'line_type','inventory');
      v_quantity:=(v_item.value->>'quantity')::integer;
      v_unit_cost:=(v_item.value->>'unit_cost')::numeric(14,2);
    exception when others then
      raise exception 'بيانات بند فاتورة المورد غير صحيحة' using errcode='22023';
    end;
    v_description:=nullif(btrim(coalesce(v_item.value->>'description','')),'');
    if v_quantity is null or v_quantity<1 or v_unit_cost is null or v_unit_cost<0
       or v_line_type not in ('inventory','direct') then
      raise exception 'الكمية أو تكلفة الوحدة أو نوع بند الفاتورة غير صحيح' using errcode='22023';
    end if;
    v_line_total:=round(v_quantity*v_unit_cost,2);

    if v_line_type='inventory' then
      if p_purchase_order_id is null then
        raise exception 'يجب ربط فاتورة المخزون بأمر التوريد' using errcode='22023';
      end if;
      begin
        select * into v_receipt_item
          from public.purchase_receipt_items
         where id=(v_item.value->>'purchase_receipt_item_id')::uuid
         for update;
      exception when invalid_text_representation then
        raise exception 'بند الاستلام المحدد غير صالح' using errcode='22023';
      end;
      if not found or not exists(
        select 1 from public.purchase_receipts pr
        where pr.id=v_receipt_item.receipt_id
          and pr.purchase_order_id=p_purchase_order_id
      ) then
        raise exception 'بند الاستلام لا يتبع أمر التوريد المحدد' using errcode='23503';
      end if;
      if v_description is null then
        select poi.motorcycle_name into v_description
          from public.purchase_order_items poi
         where poi.id=v_receipt_item.purchase_order_item_id;
      end if;
    else
      if v_item.value ? 'purchase_receipt_item_id'
         and nullif(v_item.value->>'purchase_receipt_item_id','') is not null then
        raise exception 'البند المباشر لا يرتبط ببند استلام' using errcode='22023';
      end if;
      if v_description is null then
        raise exception 'أدخل وصفًا للبند المباشر' using errcode='22023';
      end if;
    end if;

    insert into public.supplier_bill_items(
      supplier_bill_id,line_number,line_type,purchase_receipt_item_id,
      description,quantity,unit_cost,line_total
    ) values(
      v_bill.id,v_item.ordinality::integer,v_line_type,
      case when v_line_type='inventory' then v_receipt_item.id else null end,
      v_description,v_quantity,v_unit_cost,v_line_total
    ) returning id into v_line_id;

    if v_line_type='inventory' then
      select array_agg(picked.motorcycle_unit_id order by picked.registered_at,picked.motorcycle_unit_id)
        into v_unit_ids
        from (
          select pru.motorcycle_unit_id,mu.registered_at
            from public.purchase_receipt_units pru
            join public.motorcycle_units mu on mu.id=pru.motorcycle_unit_id
           where pru.receipt_item_id=v_receipt_item.id
             and not exists(
               select 1 from public.supplier_bill_item_units sbiu
               where sbiu.motorcycle_unit_id=pru.motorcycle_unit_id
             )
             and not exists(
               select 1 from public.supplier_return_units sru
               where sru.motorcycle_unit_id=pru.motorcycle_unit_id
             )
           order by mu.registered_at,pru.motorcycle_unit_id
           limit v_quantity
           for update of pru skip locked
        ) picked;
      if coalesce(cardinality(v_unit_ids),0)<>v_quantity then
        raise exception 'الكمية المفوترة تتجاوز الوحدات المستلمة غير المفوترة والمتاحة في بند الاستلام: %',
          v_description using errcode='23514';
      end if;
      insert into public.supplier_bill_item_units(supplier_bill_item_id,motorcycle_unit_id)
      select v_line_id,unnest(v_unit_ids);
    end if;

    v_total:=v_total+v_line_total;
    v_line_count:=v_line_count+1;
  end loop;

  if round(v_total,2)<>round(p_total_amount,2) then
    raise exception 'إجمالي الفاتورة لا يساوي مجموع البنود: إجمالي البنود % وإجمالي الفاتورة %',
      round(v_total,2),round(p_total_amount,2) using errcode='23514';
  end if;
  return v_bill;
end;
$$;

revoke all on function public.create_supplier_bill(uuid,text,numeric,date,date,uuid,text,jsonb)
  from public,anon;
grant execute on function public.create_supplier_bill(uuid,text,numeric,date,date,uuid,text,jsonb)
  to authenticated;

commit;
