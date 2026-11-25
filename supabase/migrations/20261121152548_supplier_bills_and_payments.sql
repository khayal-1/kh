create table if not exists public.supplier_bills (
  id uuid primary key default gen_random_uuid(),
  bill_number text not null,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_order_id uuid references public.purchase_orders(id) on delete restrict,
  bill_date date not null default current_date,
  due_date date,
  total_amount numeric(14,2) not null check (total_amount > 0),
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint supplier_bills_supplier_bill_number_unique unique (supplier_id,bill_number),
  constraint supplier_bills_due_date_check check (due_date is null or due_date >= bill_date)
);

create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  payment_number bigint generated always as identity unique,
  supplier_bill_id uuid not null references public.supplier_bills(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  method text not null check (method in ('cash','bank_transfer','instapay','cheque','other')),
  reference text,
  notes text,
  paid_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict
);

create index if not exists supplier_bills_supplier_date_idx on public.supplier_bills(supplier_id,bill_date desc);
create index if not exists supplier_bills_purchase_order_idx on public.supplier_bills(purchase_order_id);
create index if not exists supplier_payments_bill_date_idx on public.supplier_payments(supplier_bill_id,paid_at desc);
create index if not exists supplier_payments_supplier_date_idx on public.supplier_payments(supplier_id,paid_at desc);

alter table public.supplier_bills enable row level security;
alter table public.supplier_payments enable row level security;
drop policy if exists supplier_bills_read on public.supplier_bills;
create policy supplier_bills_read on public.supplier_bills for select to authenticated using ((select public.can_manage_purchasing()));
drop policy if exists supplier_payments_read on public.supplier_payments;
create policy supplier_payments_read on public.supplier_payments for select to authenticated using ((select public.can_manage_purchasing()));
revoke all on public.supplier_bills from anon, authenticated;
revoke all on public.supplier_payments from anon, authenticated;
grant select on public.supplier_bills to authenticated;
grant select on public.supplier_payments to authenticated;

create or replace function public.create_supplier_bill(
  p_supplier_id uuid,
  p_bill_number text,
  p_total_amount numeric,
  p_bill_date date default current_date,
  p_due_date date default null,
  p_purchase_order_id uuid default null,
  p_notes text default null
) returns public.supplier_bills
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_bill public.supplier_bills;
begin
  if auth.uid() is null or not public.can_manage_purchasing() then
    raise exception 'غير مصرح بإدارة فواتير الموردين' using errcode = '42501';
  end if;
  if p_supplier_id is null or nullif(btrim(p_bill_number),'') is null or p_total_amount is null or p_total_amount <= 0 then
    raise exception 'بيانات فاتورة المورد غير مكتملة أو غير صحيحة' using errcode = '22023';
  end if;
  if p_bill_date is null or (p_due_date is not null and p_due_date < p_bill_date) then
    raise exception 'تاريخ الاستحقاق لا يمكن أن يسبق تاريخ الفاتورة' using errcode = '22023';
  end if;
  if not exists(select 1 from public.suppliers s where s.id=p_supplier_id and s.is_active) then
    raise exception 'المورد غير موجود أو موقوف' using errcode = '23503';
  end if;
  if p_purchase_order_id is not null and not exists(select 1 from public.purchase_orders po where po.id=p_purchase_order_id and po.supplier_id=p_supplier_id and po.status <> 'cancelled') then
    raise exception 'أمر التوريد لا يتبع هذا المورد أو أنه ملغى' using errcode = '23503';
  end if;
  insert into public.supplier_bills(bill_number,supplier_id,purchase_order_id,bill_date,due_date,total_amount,notes,created_by)
  values (btrim(p_bill_number),p_supplier_id,p_purchase_order_id,p_bill_date,p_due_date,round(p_total_amount,2),nullif(btrim(p_notes),''),auth.uid())
  returning * into v_bill;
  return v_bill;
end;
$$;

create or replace function public.record_supplier_payment(
  p_supplier_bill_id uuid,p_amount numeric,p_method text,p_reference text default null,p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_bill public.supplier_bills; v_paid numeric(14,2); v_balance numeric(14,2); v_payment public.supplier_payments;
begin
  if auth.uid() is null or not public.can_manage_purchasing() then
    raise exception 'غير مصرح بتسجيل مدفوعات الموردين' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 or p_method not in ('cash','bank_transfer','instapay','cheque','other') then
    raise exception 'قيمة الدفعة أو طريقة الدفع غير صحيحة' using errcode = '22023';
  end if;
  select * into v_bill from public.supplier_bills where id=p_supplier_bill_id for update;
  if not found then raise exception 'فاتورة المورد غير موجودة' using errcode = 'P0002'; end if;
  select coalesce(sum(amount),0) into v_paid from public.supplier_payments where supplier_bill_id=v_bill.id;
  v_balance := v_bill.total_amount-v_paid;
  if round(p_amount,2)>v_balance then raise exception 'قيمة الدفعة أكبر من الرصيد المستحق: %',v_balance using errcode = '22023'; end if;
  insert into public.supplier_payments(supplier_bill_id,supplier_id,amount,method,reference,notes,created_by)
  values(v_bill.id,v_bill.supplier_id,round(p_amount,2),p_method,nullif(btrim(p_reference),''),nullif(btrim(p_notes),''),auth.uid())
  returning * into v_payment;
  return jsonb_build_object('payment_number',v_payment.payment_number,'amount',v_payment.amount,'balance_due',v_balance-v_payment.amount);
end;
$$;

revoke all on function public.create_supplier_bill(uuid,text,numeric,date,date,uuid,text) from public, anon;
revoke all on function public.record_supplier_payment(uuid,numeric,text,text,text) from public, anon;
grant execute on function public.create_supplier_bill(uuid,text,numeric,date,date,uuid,text) to authenticated;
grant execute on function public.record_supplier_payment(uuid,numeric,text,text,text) to authenticated;
