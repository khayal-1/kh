-- Showroom POS foundation: transactional sales, invoices, payments and stock ledger.
-- Apply this migration to the El Khayal Motors Supabase project before enabling POS.

begin;

alter table public.clients alter column user_id drop not null;

-- Extend the existing employee permission allow-list for the POS role.
do $permission$
declare
  permission_check record;
begin
  for permission_check in
    select conname
    from pg_constraint
    where conrelid = 'public.employee_permissions'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%catalog_view%'
  loop
    execute format('alter table public.employee_permissions drop constraint %I', permission_check.conname);
  end loop;
  alter table public.employee_permissions
    add constraint employee_permissions_permission_key_check
    check (permission_key in (
      'catalog_view', 'catalog_manage', 'requests_view',
      'requests_manage', 'customer_data_view', 'sales_manage'
    ));
end
$permission$;

create sequence if not exists public.sale_invoice_number_seq;

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  customer_id uuid references public.clients(id) on delete set null,
  customer_name text not null,
  customer_phone text,
  channel text not null default 'showroom' check (channel in ('showroom','website')),
  status text not null default 'posted' check (status in ('posted','voided')),
  subtotal numeric(12,2) not null check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total numeric(12,2) not null check (total >= 0),
  amount_paid numeric(12,2) not null default 0 check (amount_paid >= 0 and amount_paid <= total),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','partial','paid')),
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete restrict,
  motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,
  motorcycle_name text not null,
  model_year smallint,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  method text not null check (method in ('cash','bank_transfer','card','other')),
  reference text,
  received_by uuid not null references auth.users(id) on delete restrict,
  paid_at timestamptz not null default now()
);

create table if not exists public.stock_movements (
  id bigint generated always as identity primary key,
  motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,
  movement_type text not null check (movement_type in ('opening','sale','adjustment','purchase_receipt','sale_return')),
  quantity_delta integer not null check (quantity_delta <> 0),
  reference_id uuid,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists sales_created_at_idx on public.sales(created_at desc);
create index if not exists sales_created_by_idx on public.sales(created_by);
create index if not exists sale_items_sale_id_idx on public.sale_items(sale_id);
create index if not exists sale_items_motorcycle_id_idx on public.sale_items(motorcycle_id);
create index if not exists payments_sale_id_idx on public.payments(sale_id);
create index if not exists stock_movements_motorcycle_date_idx on public.stock_movements(motorcycle_id, created_at desc);
create index if not exists stock_movements_reference_idx on public.stock_movements(reference_id);

create or replace function public.can_manage_sales()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1 from public.user_roles r
      where r.user_id = (select auth.uid())
        and r.role in ('manager'::public.app_role, 'owner'::public.app_role, 'admin'::public.app_role)
    )
    or exists (
      select 1 from public.employee_permissions p
      where p.user_id = (select auth.uid())
        and p.permission_key = 'sales_manage'
    );
$$;

revoke all on function public.can_manage_sales() from public, anon;
grant execute on function public.can_manage_sales() to authenticated;

create or replace function public.record_motorcycle_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source text := coalesce(current_setting('ekm.stock_movement_source', true), '');
begin
  if tg_op = 'INSERT' then
    if new.stock > 0 then
      insert into public.stock_movements(motorcycle_id, movement_type, quantity_delta, notes, created_by)
      values (new.id, 'opening', new.stock, 'رصيد افتتاحي عند إضافة الدراجة', (select auth.uid()));
    end if;
  elsif new.stock is distinct from old.stock and v_source <> 'sale' then
    insert into public.stock_movements(motorcycle_id, movement_type, quantity_delta, notes, created_by)
    values (
      new.id, 'adjustment', new.stock - old.stock,
      'تسوية مخزون من تعديل بيانات الدراجة', (select auth.uid())
    );
  end if;
  return new;
end;
$$;

revoke all on function public.record_motorcycle_stock_movement() from public, anon, authenticated;
drop trigger if exists motorcycles_stock_movement on public.motorcycles;
create trigger motorcycles_stock_movement
after insert or update of stock on public.motorcycles
for each row execute function public.record_motorcycle_stock_movement();

create or replace function public.create_showroom_sale(
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_payment_amount numeric,
  p_payment_method text,
  p_payment_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_bike public.motorcycles%rowtype;
  v_motorcycle_id uuid;
  v_quantity integer;
  v_subtotal numeric(12,2) := 0;
  v_invoice text;
  v_sale_id uuid;
  v_customer_id uuid;
  v_customer_name text := nullif(btrim(coalesce(p_customer_name, '')), '');
  v_paid numeric(12,2) := coalesce(p_payment_amount, 0);
  v_status text;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception using errcode = '42501', message = 'ليس لديك صلاحية تسجيل المبيعات';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or coalesce(jsonb_array_length(p_items), 0) < 1
     or coalesce(jsonb_array_length(p_items), 0) > 20 then
    raise exception using errcode = '22023', message = 'يجب اختيار دراجة واحدة على الأقل وبحد أقصى 20 صنفًا';
  end if;
  if (select count(*) from jsonb_array_elements(p_items)) <>
     (select count(distinct value->>'motorcycle_id') from jsonb_array_elements(p_items)) then
    raise exception using errcode = '22023', message = 'لا تكرر الدراجة في أكثر من سطر';
  end if;

  -- Lock every selected motorcycle in a stable order before checking stock.
  for v_item in
    select value from jsonb_array_elements(p_items) as x(value)
    order by value->>'motorcycle_id'
  loop
    if coalesce(v_item->>'motorcycle_id','') = ''
       or coalesce(v_item->>'quantity','') !~ '^[0-9]+$' then
      raise exception using errcode = '22023', message = 'بيانات الصنف أو الكمية غير صحيحة';
    end if;
    begin
      v_motorcycle_id := (v_item->>'motorcycle_id')::uuid;
      v_quantity := (v_item->>'quantity')::integer;
    exception when others then
      raise exception using errcode = '22023', message = 'معرّف الدراجة أو الكمية غير صالح';
    end;
    if v_quantity < 1 or v_quantity > 100 then
      raise exception using errcode = '22023', message = 'الكمية يجب أن تكون بين 1 و100';
    end if;
    select * into v_bike
    from public.motorcycles
    where id = v_motorcycle_id
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'إحدى الدراجات المختارة لم تعد موجودة';
    end if;
    if v_bike.status <> 'available'::public.motorcycle_status or v_bike.stock < v_quantity then
      raise exception using errcode = '23514', message = 'المخزون غير كافٍ للدراجة: ' || v_bike.name;
    end if;
    v_subtotal := v_subtotal + (v_bike.price * v_quantity);
  end loop;

  if v_paid < 0 or v_paid > v_subtotal then
    raise exception using errcode = '23514', message = 'المبلغ المدفوع يجب ألا يتجاوز إجمالي الفاتورة';
  end if;
  if v_paid > 0 and coalesce(p_payment_method, '') not in ('cash','bank_transfer','card','other') then
    raise exception using errcode = '22023', message = 'طريقة الدفع غير صحيحة';
  end if;

  v_customer_name := coalesce(v_customer_name, 'عميل نقدي');
  insert into public.clients(user_id, display_name, phone)
  values (null, v_customer_name, nullif(btrim(coalesce(p_customer_phone,'')), ''))
  returning id into v_customer_id;

  v_invoice := 'EKM-' || to_char(now(), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.sale_invoice_number_seq')::text, 6, '0');
  v_status := case when v_paid = 0 then 'unpaid' when v_paid < v_subtotal then 'partial' else 'paid' end;

  insert into public.sales(
    invoice_number, customer_id, customer_name, customer_phone, channel,
    subtotal, total, amount_paid, payment_status, notes, created_by
  )
  values (
    v_invoice, v_customer_id, v_customer_name,
    nullif(btrim(coalesce(p_customer_phone,'')), ''), 'showroom',
    v_subtotal, v_subtotal, v_paid, v_status,
    nullif(btrim(coalesce(p_notes,'')), ''), (select auth.uid())
  )
  returning id into v_sale_id;

  perform set_config('ekm.stock_movement_source', 'sale', true);
  for v_item in
    select value from jsonb_array_elements(p_items) as x(value)
    order by value->>'motorcycle_id'
  loop
    v_motorcycle_id := (v_item->>'motorcycle_id')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    select * into v_bike from public.motorcycles where id = v_motorcycle_id;
    insert into public.sale_items(sale_id, motorcycle_id, motorcycle_name, model_year, unit_price, quantity, line_total)
    values (v_sale_id, v_bike.id, v_bike.name, v_bike.model_year, v_bike.price, v_quantity, v_bike.price * v_quantity);
    update public.motorcycles set stock = stock - v_quantity where id = v_bike.id;
    insert into public.stock_movements(motorcycle_id, movement_type, quantity_delta, reference_id, notes, created_by)
    values (v_bike.id, 'sale', -v_quantity, v_sale_id, 'خصم مخزون مقابل فاتورة ' || v_invoice, (select auth.uid()));
  end loop;

  if v_paid > 0 then
    insert into public.payments(sale_id, amount, method, reference, received_by)
    values (v_sale_id, v_paid, p_payment_method, nullif(btrim(coalesce(p_payment_reference,'')), ''), (select auth.uid()));
  end if;

  return jsonb_build_object(
    'id', v_sale_id,
    'invoice_number', v_invoice,
    'subtotal', v_subtotal,
    'total', v_subtotal,
    'amount_paid', v_paid,
    'balance_due', v_subtotal - v_paid,
    'payment_status', v_status
  );
end;
$$;

revoke all on function public.create_showroom_sale(text,text,jsonb,numeric,text,text,text) from public, anon;
grant execute on function public.create_showroom_sale(text,text,jsonb,numeric,text,text,text) to authenticated;

create or replace function public.record_sale_payment(
  p_sale_id uuid,
  p_amount numeric,
  p_method text,
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales%rowtype;
  v_paid numeric(12,2);
  v_status text;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception using errcode = '42501', message = 'ليس لديك صلاحية تسجيل المدفوعات';
  end if;
  if p_amount is null or p_amount <= 0 or coalesce(p_method,'') not in ('cash','bank_transfer','card','other') then
    raise exception using errcode = '22023', message = 'قيمة أو طريقة الدفع غير صحيحة';
  end if;
  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found or v_sale.status <> 'posted' then
    raise exception using errcode = 'P0002', message = 'الفاتورة غير موجودة أو غير قابلة للتحصيل';
  end if;
  if p_amount > v_sale.total - v_sale.amount_paid then
    raise exception using errcode = '23514', message = 'المبلغ أكبر من الرصيد المستحق';
  end if;
  insert into public.payments(sale_id, amount, method, reference, received_by)
  values (p_sale_id, p_amount, p_method, nullif(btrim(coalesce(p_reference,'')), ''), (select auth.uid()));
  v_paid := v_sale.amount_paid + p_amount;
  v_status := case when v_paid = v_sale.total then 'paid' else 'partial' end;
  update public.sales set amount_paid = v_paid, payment_status = v_status, updated_at = now()
  where id = p_sale_id;
  return jsonb_build_object('sale_id', p_sale_id, 'amount_paid', v_paid, 'balance_due', v_sale.total - v_paid, 'payment_status', v_status);
end;
$$;

revoke all on function public.record_sale_payment(uuid,numeric,text,text) from public, anon;
grant execute on function public.record_sale_payment(uuid,numeric,text,text) to authenticated;

alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.payments enable row level security;
alter table public.stock_movements enable row level security;

create policy sales_read_authorized on public.sales
for select to authenticated using (public.can_manage_sales());
create policy sale_items_read_authorized on public.sale_items
for select to authenticated using (public.can_manage_sales());
create policy payments_read_authorized on public.payments
for select to authenticated using (public.can_manage_sales());
create policy stock_movements_read_authorized on public.stock_movements
for select to authenticated using (public.can_manage_sales() or public.has_any_role(array['manager','owner','admin']::public.app_role[]));

revoke all on public.sales, public.sale_items, public.payments, public.stock_movements from anon, authenticated;
grant select on public.sales, public.sale_items, public.payments, public.stock_movements to authenticated;

commit;
