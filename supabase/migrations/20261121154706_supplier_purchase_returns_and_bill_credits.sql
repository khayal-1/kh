create sequence if not exists public.supplier_return_number_seq;

create table public.supplier_returns (
  id uuid primary key default gen_random_uuid(),
  return_number bigint generated always as identity unique,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  supplier_bill_id uuid not null references public.supplier_bills(id) on delete restrict,
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.supplier_return_items (
  id uuid primary key default gen_random_uuid(),
  supplier_return_id uuid not null references public.supplier_returns(id) on delete restrict,
  purchase_receipt_item_id uuid not null references public.purchase_receipt_items(id) on delete restrict,
  motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  line_total numeric(14,2) generated always as (round(quantity * unit_cost, 2)) stored,
  created_at timestamptz not null default now(),
  unique (supplier_return_id, purchase_receipt_item_id)
);

create index supplier_returns_supplier_date_idx on public.supplier_returns(supplier_id, created_at desc);
create index supplier_returns_bill_idx on public.supplier_returns(supplier_bill_id);
create index supplier_return_items_return_idx on public.supplier_return_items(supplier_return_id);
create index supplier_return_items_receipt_item_idx on public.supplier_return_items(purchase_receipt_item_id);

alter table public.supplier_returns enable row level security;
alter table public.supplier_return_items enable row level security;

create policy "Purchasing managers can read supplier returns"
on public.supplier_returns for select to authenticated
using (public.can_manage_purchasing());

create policy "Purchasing managers can read supplier return items"
on public.supplier_return_items for select to authenticated
using (public.can_manage_purchasing());

revoke all on public.supplier_returns, public.supplier_return_items from anon, authenticated;
grant select on public.supplier_returns, public.supplier_return_items to authenticated;

create or replace function public.create_supplier_return(
  p_purchase_order_id uuid,
  p_supplier_bill_id uuid,
  p_items jsonb,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.purchase_orders%rowtype;
  v_bill public.supplier_bills%rowtype;
  v_item jsonb;
  v_receipt_item public.purchase_receipt_items%rowtype;
  v_return_id uuid;
  v_return_number bigint;
  v_receipt_item_id uuid;
  v_qty integer;
  v_already_returned integer;
  v_total_credit numeric(14,2) := 0;
  v_existing_credit numeric(14,2) := 0;
  v_count integer := 0;
begin
  if (select auth.uid()) is null or not public.can_manage_purchasing() then
    raise exception using errcode='42501', message='ليس لديك صلاحية تسجيل مرتجعات الموردين';
  end if;

  select * into v_order from public.purchase_orders
  where id=p_purchase_order_id for update;
  if not found then
    raise exception using errcode='P0002', message='أمر التوريد غير موجود';
  end if;

  select * into v_bill from public.supplier_bills
  where id=p_supplier_bill_id and supplier_id=v_order.supplier_id
    and (purchase_order_id is null or purchase_order_id=p_purchase_order_id)
  for update;
  if not found then
    raise exception using errcode='23503', message='فاتورة المورد غير مرتبطة بهذا المورد أو أمر التوريد';
  end if;

  if jsonb_typeof(p_items) is distinct from 'array'
     or coalesce(jsonb_array_length(p_items),0) < 1
     or coalesce(jsonb_array_length(p_items),0) > 20 then
    raise exception using errcode='22023', message='حدد من بند واحد إلى 20 بندًا للمرتجع';
  end if;
  if (select count(*) from jsonb_array_elements(p_items)) <>
     (select count(distinct value->>'purchase_receipt_item_id') from jsonb_array_elements(p_items)) then
    raise exception using errcode='22023', message='لا تكرر بند الاستلام في المرتجع';
  end if;

  insert into public.supplier_returns(supplier_id,purchase_order_id,supplier_bill_id,notes,created_by)
  values(v_order.supplier_id,p_purchase_order_id,p_supplier_bill_id,
    nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()))
  returning id,return_number into v_return_id,v_return_number;

  perform set_config('ekm.stock_movement_source','purchase_return',true);
  perform set_config('ekm.stock_movement_reference',v_return_id::text,true);

  for v_item in
    select value from jsonb_array_elements(p_items) as x(value)
    order by value->>'purchase_receipt_item_id'
  loop
    begin
      v_receipt_item_id := (v_item->>'purchase_receipt_item_id')::uuid;
      v_qty := (v_item->>'quantity')::integer;
    exception when others then
      raise exception using errcode='22023', message='بيانات بند المرتجع أو كميته غير صحيحة';
    end;
    if v_qty is null or v_qty < 1 then
      raise exception using errcode='22023', message='كمية المرتجع يجب أن تكون أكبر من صفر';
    end if;

    select pri.* into v_receipt_item
    from public.purchase_receipt_items pri
    join public.purchase_receipts pr on pr.id=pri.receipt_id
    where pri.id=v_receipt_item_id and pr.purchase_order_id=p_purchase_order_id
    for update of pri;
    if not found then
      raise exception using errcode='P0002', message='بند الاستلام غير تابع لأمر التوريد المحدد';
    end if;

    select coalesce(sum(sri.quantity),0)::integer into v_already_returned
    from public.supplier_return_items sri
    where sri.purchase_receipt_item_id=v_receipt_item_id;

    if v_qty > v_receipt_item.quantity - v_already_returned then
      raise exception using errcode='23514', message='كمية المرتجع تتجاوز الكمية المستلمة المتبقية';
    end if;

    perform 1 from public.motorcycles where id=v_receipt_item.motorcycle_id
      and stock >= v_qty for update;
    if not found then
      raise exception using errcode='23514', message='المخزون الحالي لا يكفي لإرجاع هذه الكمية للمورد';
    end if;

    insert into public.supplier_return_items(
      supplier_return_id,purchase_receipt_item_id,motorcycle_id,quantity,unit_cost
    ) values (
      v_return_id,v_receipt_item_id,v_receipt_item.motorcycle_id,v_qty,v_receipt_item.unit_cost
    );

    update public.motorcycles set stock=stock-v_qty
    where id=v_receipt_item.motorcycle_id;

    v_total_credit := v_total_credit + (v_qty * v_receipt_item.unit_cost);
    v_count := v_count + 1;
  end loop;

  select coalesce(sum(sri.line_total),0) into v_existing_credit
  from public.supplier_return_items sri
  join public.supplier_returns sr on sr.id=sri.supplier_return_id
  where sr.supplier_bill_id=p_supplier_bill_id and sr.id<>v_return_id;

  if v_existing_credit + v_total_credit > v_bill.total_amount then
    raise exception using errcode='23514', message='إجمالي إشعارات الخصم يتجاوز قيمة فاتورة المورد';
  end if;

  return jsonb_build_object(
    'id',v_return_id,
    'return_number',v_return_number,
    'items_count',v_count,
    'credit_amount',round(v_total_credit,2)
  );
end;
$function$;

revoke all on function public.create_supplier_return(uuid,uuid,jsonb,text) from public, anon;
grant execute on function public.create_supplier_return(uuid,uuid,jsonb,text) to authenticated;

create or replace function public.record_supplier_payment(
  p_supplier_bill_id uuid,
  p_amount numeric,
  p_method text,
  p_reference text default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_bill public.supplier_bills%rowtype;
  v_paid numeric(14,2);
  v_credits numeric(14,2);
  v_balance numeric(14,2);
  v_payment public.supplier_payments%rowtype;
begin
  if (select auth.uid()) is null or not public.can_manage_purchasing() then
    raise exception using errcode='42501', message='غير مصرح بتسجيل مدفوعات الموردين';
  end if;
  if p_amount is null or p_amount <= 0 or p_method not in ('cash','bank_transfer','instapay','cheque','other') then
    raise exception using errcode='22023', message='قيمة الدفعة أو طريقة الدفع غير صحيحة';
  end if;
  select * into v_bill from public.supplier_bills where id=p_supplier_bill_id for update;
  if not found then
    raise exception using errcode='P0002', message='فاتورة المورد غير موجودة';
  end if;
  select coalesce(sum(amount),0) into v_paid
  from public.supplier_payments where supplier_bill_id=v_bill.id;
  select coalesce(sum(sri.line_total),0) into v_credits
  from public.supplier_return_items sri
  join public.supplier_returns sr on sr.id=sri.supplier_return_id
  where sr.supplier_bill_id=v_bill.id;
  v_balance := v_bill.total_amount - v_paid - v_credits;
  if round(p_amount,2) > v_balance then
    raise exception using errcode='23514', message='قيمة الدفعة أكبر من الرصيد المستحق بعد خصم المرتجعات: ' || v_balance;
  end if;
  insert into public.supplier_payments(supplier_bill_id,supplier_id,amount,method,reference,notes,created_by)
  values(v_bill.id,v_bill.supplier_id,round(p_amount,2),p_method,
    nullif(btrim(coalesce(p_reference,'')),''),nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()))
  returning * into v_payment;
  return jsonb_build_object(
    'payment_number',v_payment.payment_number,
    'amount',v_payment.amount,
    'balance_due',v_balance-v_payment.amount
  );
end;
$function$;

revoke all on function public.record_supplier_payment(uuid,numeric,text,text,text) from public, anon;
grant execute on function public.record_supplier_payment(uuid,numeric,text,text,text) to authenticated;
