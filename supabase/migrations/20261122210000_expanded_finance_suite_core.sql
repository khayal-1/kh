-- Expanded finance suite: periods, opening balances, cost centres, supplier advances,
-- fixed assets, depreciation, bank reconciliation, cheques, recurring journals and tax setup.
create table if not exists public.fiscal_periods (
 id uuid primary key default gen_random_uuid(), period_code text not null unique, period_name text not null,
 start_date date not null, end_date date not null, status text not null default 'open' check(status in ('open','closed')),
 closed_at timestamptz, closed_by uuid references auth.users(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 check(end_date>=start_date),
 check((status='open' and closed_at is null and closed_by is null) or (status='closed' and closed_at is not null and closed_by is not null))
);
create index if not exists fiscal_periods_dates_idx on public.fiscal_periods(start_date,end_date);
create table if not exists public.cost_centers (
 id uuid primary key default gen_random_uuid(), code text not null unique, name text not null, description text,
 is_active boolean not null default true, created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);
alter table public.journal_entry_lines add column if not exists cost_center_id uuid references public.cost_centers(id) on delete restrict;
create index if not exists journal_lines_cost_center_idx on public.journal_entry_lines(cost_center_id);
create table if not exists public.opening_balance_batches (
 id uuid primary key default gen_random_uuid(), batch_number bigint generated always as identity unique,
 effective_date date not null, description text not null, journal_entry_id uuid unique references public.journal_entries(id) on delete restrict,
 status text not null default 'posted' check(status='posted'), created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);
insert into public.accounting_accounts(code,name,account_type,parent_code,is_system) values
 ('1300','سلف الموردين','asset','1000',true),('1510','مجمع إهلاك الأصول الثابتة','asset','1500',true),
 ('6070','مصروف إهلاك الأصول','expense','6000',true) on conflict(code) do nothing;
create table if not exists public.supplier_advances (
 id uuid primary key default gen_random_uuid(), advance_number bigint generated always as identity unique,
 supplier_id uuid not null references public.suppliers(id) on delete restrict, advance_date date not null default current_date,
 amount numeric(14,2) not null check(amount>0), allocated_amount numeric(14,2) not null default 0 check(allocated_amount>=0 and allocated_amount<=amount),
 cash_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 payment_method text not null check(payment_method in ('cash','bank_transfer','instapay','cheque','other')),
 reference_number text, notes text, journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now()
);
create index if not exists supplier_advances_supplier_date_idx on public.supplier_advances(supplier_id,advance_date desc);
create table if not exists public.supplier_advance_allocations (
 id uuid primary key default gen_random_uuid(), advance_id uuid not null references public.supplier_advances(id) on delete restrict,
 supplier_bill_id uuid not null references public.supplier_bills(id) on delete restrict,
 amount numeric(14,2) not null check(amount>0), journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now()
);
create index if not exists supplier_advance_allocations_bill_idx on public.supplier_advance_allocations(supplier_bill_id);
create table if not exists public.fixed_assets (
 id uuid primary key default gen_random_uuid(), asset_number bigint generated always as identity unique, asset_name text not null, description text,
 asset_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 accumulated_depreciation_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 depreciation_expense_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 acquisition_date date not null, depreciation_start_date date not null, cost numeric(14,2) not null check(cost>0),
 salvage_value numeric(14,2) not null default 0 check(salvage_value>=0 and salvage_value<cost),
 useful_life_months integer not null check(useful_life_months>0), accumulated_depreciation numeric(14,2) not null default 0 check(accumulated_depreciation>=0),
 cash_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 status text not null default 'active' check(status in ('active','disposed')),
 acquisition_journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now()
);
create index if not exists fixed_assets_status_idx on public.fixed_assets(status,depreciation_start_date);
create table if not exists public.fixed_asset_depreciations (
 id uuid primary key default gen_random_uuid(), fixed_asset_id uuid not null references public.fixed_assets(id) on delete restrict,
 period_date date not null, amount numeric(14,2) not null check(amount>0),
 journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 unique(fixed_asset_id,period_date)
);
create table if not exists public.bank_reconciliations (
 id uuid primary key default gen_random_uuid(), reconciliation_number bigint generated always as identity unique,
 cash_account_id uuid not null references public.cash_accounts(id) on delete restrict, period_start date not null, period_end date not null,
 statement_ending_balance numeric(14,2) not null, status text not null default 'open' check(status in ('open','completed')),
 notes text, created_by uuid not null references auth.users(id) on delete restrict, completed_at timestamptz,
 completed_by uuid references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 check(period_end>=period_start),
 check((status='open' and completed_at is null and completed_by is null) or (status='completed' and completed_at is not null and completed_by is not null))
);
create index if not exists bank_reconciliations_account_date_idx on public.bank_reconciliations(cash_account_id,period_end desc);
create table if not exists public.bank_reconciliation_lines (
 id uuid primary key default gen_random_uuid(), reconciliation_id uuid not null references public.bank_reconciliations(id) on delete restrict,
 statement_date date not null, description text not null, amount numeric(14,2) not null, reference_number text,
 matched_journal_line_id uuid references public.journal_entry_lines(id) on delete restrict, matched_at timestamptz,
 created_at timestamptz not null default now(),
 check((matched_journal_line_id is null and matched_at is null) or (matched_journal_line_id is not null and matched_at is not null))
);
create unique index if not exists bank_reconciliation_lines_matched_unique_idx on public.bank_reconciliation_lines(matched_journal_line_id) where matched_journal_line_id is not null;
create table if not exists public.cheques (
 id uuid primary key default gen_random_uuid(), cheque_number bigint generated always as identity unique,
 cheque_type text not null check(cheque_type in ('issued','received')), cheque_reference text not null, bank_name text,
 party_name text not null, cash_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 amount numeric(14,2) not null check(amount>0), issue_date date not null, due_date date not null,
 status text not null default 'pending' check(status in ('pending','under_collection','cleared','bounced','cancelled')),
 notes text, created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 cleared_at timestamptz, check(due_date>=issue_date)
);
create index if not exists cheques_due_date_idx on public.cheques(status,due_date);
create table if not exists public.recurring_journal_templates (
 id uuid primary key default gen_random_uuid(), template_name text not null, description text,
 frequency text not null check(frequency in ('monthly','quarterly','yearly')), start_date date not null, end_date date,
 next_run_date date not null, is_active boolean not null default true, created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(), check(end_date is null or end_date>=start_date)
);
create table if not exists public.recurring_journal_template_lines (
 id uuid primary key default gen_random_uuid(), template_id uuid not null references public.recurring_journal_templates(id) on delete cascade,
 account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 debit numeric(14,2) not null default 0 check(debit>=0), credit numeric(14,2) not null default 0 check(credit>=0),
 memo text, check((debit>0 and credit=0) or (credit>0 and debit=0))
);
create table if not exists public.recurring_journal_runs (
 id uuid primary key default gen_random_uuid(), template_id uuid not null references public.recurring_journal_templates(id) on delete restrict,
 run_date date not null, journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 unique(template_id,run_date)
);
alter table public.clients add column if not exists tax_id text;
alter table public.suppliers add column if not exists tax_id text;
create table if not exists public.tax_rates (
 id uuid primary key default gen_random_uuid(), tax_code text not null unique, tax_name text not null,
 rate numeric(7,4) not null check(rate>=0 and rate<=100), tax_account_id uuid references public.accounting_accounts(id) on delete restrict,
 is_active boolean not null default true, effective_from date not null, effective_to date,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 check(effective_to is null or effective_to>=effective_from)
);
alter table public.employee_permissions drop constraint if exists employee_permissions_permission_key_check;
alter table public.employee_permissions add constraint employee_permissions_permission_key_check
 check(permission_key=any(array['catalog_view','catalog_manage','requests_view','requests_manage','customer_data_view','sales_manage','expenses_manage','accounting_view','finance_manage']::text[]));
create or replace function private.can_manage_finance() returns boolean language sql stable security definer set search_path=''
as $$ select (select auth.uid()) is not null and (public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage')) $$;
revoke all on function private.can_manage_finance() from public,anon; grant execute on function private.can_manage_finance() to authenticated;
do $$ declare t text; begin foreach t in array array['fiscal_periods','cost_centers','opening_balance_batches','supplier_advances','supplier_advance_allocations','fixed_assets','fixed_asset_depreciations','bank_reconciliations','bank_reconciliation_lines','cheques','recurring_journal_templates','recurring_journal_template_lines','recurring_journal_runs','tax_rates'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t); execute format('grant select on public.%I to authenticated',t);
 execute format('create policy %I on public.%I for select to authenticated using (public.has_any_role(array[''manager'',''owner'',''admin'']::public.app_role[]) or public.has_employee_permission(''accounting_view'') or public.has_employee_permission(''finance_manage''))',t||'_finance_read',t);
end loop; end $$;
create or replace function private.create_fiscal_period(p_period_code text,p_period_name text,p_start_date date,p_end_date date) returns uuid language plpgsql security definer set search_path='' as $$ declare v_id uuid; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإدارة الفترات المالية' using errcode='42501'; end if;
 if nullif(btrim(coalesce(p_period_code,'')),'') is null or nullif(btrim(coalesce(p_period_name,'')),'') is null or p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'بيانات الفترة غير صحيحة' using errcode='22023'; end if;
 if exists(select 1 from public.fiscal_periods where daterange(start_date,end_date,'[]') && daterange(p_start_date,p_end_date,'[]')) then raise exception 'توجد فترة محاسبية متداخلة مع التواريخ المحددة' using errcode='23505'; end if;
 insert into public.fiscal_periods(period_code,period_name,start_date,end_date,created_by) values(btrim(p_period_code),btrim(p_period_name),p_start_date,p_end_date,(select auth.uid())) returning id into v_id; return v_id; end $$;
create or replace function private.close_fiscal_period(p_period_id uuid) returns void language plpgsql security definer set search_path='' as $$ declare v_period public.fiscal_periods%rowtype; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإقفال الفترة' using errcode='42501'; end if;
 select * into v_period from public.fiscal_periods where id=p_period_id for update; if not found then raise exception 'الفترة غير موجودة' using errcode='P0002'; end if;
 if v_period.status='closed' then raise exception 'الفترة مقفلة بالفعل' using errcode='23514'; end if;
 if exists(select 1 from public.journal_entries where entry_date between v_period.start_date and v_period.end_date and status not in ('posted','reversed')) then raise exception 'توجد قيود غير مرحلة داخل الفترة' using errcode='23514'; end if;
 update public.fiscal_periods set status='closed',closed_at=now(),closed_by=(select auth.uid()) where id=p_period_id; end $$;
create or replace function private.guard_journal_period() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if exists(select 1 from public.fiscal_periods p where p.status='closed' and new.entry_date between p.start_date and p.end_date) then raise exception 'لا يمكن إنشاء أو تعديل قيد داخل فترة محاسبية مقفلة' using errcode='23514'; end if; return new; end $$;
drop trigger if exists journal_entry_fiscal_period_guard on public.journal_entries;
create trigger journal_entry_fiscal_period_guard before insert or update of entry_date on public.journal_entries for each row execute function private.guard_journal_period();
create or replace function private.create_cost_center(p_code text,p_name text,p_description text default null) returns uuid language plpgsql security definer set search_path='' as $$ declare v_id uuid; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإدارة مراكز التكلفة' using errcode='42501'; end if;
 if nullif(btrim(coalesce(p_code,'')),'') is null or nullif(btrim(coalesce(p_name,'')),'') is null then raise exception 'كود واسم مركز التكلفة مطلوبان' using errcode='22023'; end if;
 insert into public.cost_centers(code,name,description,created_by) values(btrim(p_code),btrim(p_name),nullif(btrim(coalesce(p_description,'')),''),(select auth.uid())) returning id into v_id; return v_id; end $$;
create or replace function private.post_opening_balance(p_date date,p_description text,p_lines jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_batch uuid; v_entry uuid; v_item jsonb; v_account uuid; v_debit numeric(14,2):=0; v_credit numeric(14,2):=0; v_count integer:=0; v_d numeric(14,2); v_c numeric(14,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بترحيل الأرصدة الافتتاحية' using errcode='42501'; end if;
 if p_date is null or nullif(btrim(coalesce(p_description,'')),'') is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)<2 or jsonb_array_length(p_lines)>100 then raise exception 'بيانات الأرصدة الافتتاحية غير صحيحة' using errcode='22023'; end if;
 if exists(select 1 from public.fiscal_periods where status='closed' and p_date between start_date and end_date) then raise exception 'تاريخ الأرصدة يقع داخل فترة مقفلة' using errcode='23514'; end if;
 insert into public.opening_balance_batches(effective_date,description,created_by) values(p_date,btrim(p_description),(select auth.uid())) returning id into v_batch;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(p_date,'أرصدة افتتاحية: '||btrim(p_description),'opening_balance',v_batch,(select auth.uid())) returning id into v_entry;
 for v_item in select value from jsonb_array_elements(p_lines) loop
  begin v_account:=(v_item->>'account_id')::uuid; v_d:=round(coalesce((v_item->>'debit')::numeric,0),2); v_c:=round(coalesce((v_item->>'credit')::numeric,0),2); exception when others then raise exception 'يوجد سطر افتتاحي غير صحيح' using errcode='22023'; end;
  if (v_d>0 and v_c>0) or (v_d<=0 and v_c<=0) then raise exception 'كل سطر يجب أن يكون مدينًا أو دائنًا فقط' using errcode='22023'; end if;
  if not exists(select 1 from public.accounting_accounts where id=v_account and is_active) then raise exception 'الحساب المحدد غير نشط أو غير موجود' using errcode='22023'; end if;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_account,v_d,v_c,'رصيد افتتاحي');
  v_debit:=v_debit+v_d; v_credit:=v_credit+v_c; v_count:=v_count+1;
 end loop;
 if v_count<2 or v_debit<=0 or abs(v_debit-v_credit)>0.005 then raise exception 'الأرصدة الافتتاحية غير متوازنة: المدين % والدائن %',v_debit,v_credit using errcode='23514'; end if;
 update public.opening_balance_batches set journal_entry_id=v_entry where id=v_batch; return jsonb_build_object('batch_id',v_batch,'journal_entry_id',v_entry,'debit',v_debit,'credit',v_credit); end $$;
create or replace function private.record_supplier_advance(p_supplier_id uuid,p_date date,p_amount numeric,p_cash_account_id uuid,p_method text,p_reference text default null,p_notes text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid(); v_entry uuid:=gen_random_uuid(); v_cash uuid; v_adv uuid; v_amount numeric(14,2):=round(p_amount,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسجيل سلف الموردين' using errcode='42501'; end if;
 if p_supplier_id is null or p_date is null or v_amount is null or v_amount<=0 or p_cash_account_id is null or coalesce(p_method,'') not in ('cash','bank_transfer','instapay','cheque','other') then raise exception 'بيانات سلفة المورد غير صحيحة' using errcode='22023'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and is_active) then raise exception 'المورد غير موجود أو غير نشط' using errcode='22023'; end if;
 select account_id into v_cash from public.cash_accounts where id=p_cash_account_id and is_active; select id into v_adv from public.accounting_accounts where code='1300' and is_active;
 if v_cash is null or v_adv is null then raise exception 'حساب الخزينة أو حساب سلف الموردين غير جاهز' using errcode='22023'; end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_date,'سلفة مورد','supplier_advance',v_id,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_adv,v_amount,0,'سلفة مورد'),(v_entry,v_cash,0,v_amount,'صرف سلفة من الخزينة / البنك');
 insert into public.supplier_advances(id,supplier_id,advance_date,amount,cash_account_id,payment_method,reference_number,notes,journal_entry_id,created_by)
 values(v_id,p_supplier_id,p_date,v_amount,p_cash_account_id,p_method,nullif(btrim(coalesce(p_reference,'')),''),nullif(btrim(coalesce(p_notes,'')),''),v_entry,(select auth.uid()));
 return jsonb_build_object('advance_id',v_id,'journal_entry_id',v_entry,'amount',v_amount,'remaining',v_amount); end $$;
create or replace function private.allocate_supplier_advance(p_advance_id uuid,p_bill_id uuid,p_amount numeric) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_a public.supplier_advances%rowtype; v_b public.supplier_bills%rowtype; v_amount numeric(14,2):=round(p_amount,2); v_adv uuid; v_ap uuid; v_entry uuid:=gen_random_uuid(); v_alloc uuid:=gen_random_uuid(); v_paid numeric(14,2); v_credits numeric(14,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسوية سلفة المورد' using errcode='42501'; end if;
 select * into v_a from public.supplier_advances where id=p_advance_id for update; if not found then raise exception 'سلفة المورد غير موجودة' using errcode='P0002'; end if;
 select * into v_b from public.supplier_bills where id=p_bill_id and supplier_id=v_a.supplier_id for update; if not found then raise exception 'فاتورة المورد لا تخص المورد صاحب السلفة' using errcode='23503'; end if;
 if v_amount is null or v_amount<=0 or v_amount>v_a.amount-v_a.allocated_amount then raise exception 'المبلغ يتجاوز رصيد السلفة المتاح' using errcode='23514'; end if;
 select coalesce(sum(amount),0) into v_paid from public.supplier_payments where supplier_bill_id=p_bill_id;
 select coalesce(sum(sri.line_total),0) into v_credits from public.supplier_return_items sri join public.supplier_returns sr on sr.id=sri.supplier_return_id where sr.supplier_bill_id=p_bill_id;
 if v_amount>v_b.total_amount-v_paid-v_credits-coalesce((select sum(amount) from public.supplier_advance_allocations where supplier_bill_id=p_bill_id),0) then raise exception 'المبلغ يتجاوز مستحق فاتورة المورد' using errcode='23514'; end if;
 select id into v_adv from public.accounting_accounts where code='1300'; select id into v_ap from public.accounting_accounts where code='2010';
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,current_date,'تسوية سلفة مورد على فاتورة '||v_b.bill_number,'supplier_advance_allocation',v_alloc,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_ap,v_amount,0,'تخفيض مستحق المورد'),(v_entry,v_adv,0,v_amount,'استخدام سلفة المورد');
 insert into public.supplier_advance_allocations(id,advance_id,supplier_bill_id,amount,journal_entry_id,created_by) values(v_alloc,p_advance_id,p_bill_id,v_amount,v_entry,(select auth.uid()));
 update public.supplier_advances set allocated_amount=allocated_amount+v_amount where id=p_advance_id;
 return jsonb_build_object('allocation_id',v_alloc,'amount',v_amount,'advance_remaining',v_a.amount-v_a.allocated_amount-v_amount); end $$;
create or replace function private.create_fixed_asset(p_name text,p_description text,p_asset_account_id uuid,p_accum_account_id uuid,p_expense_account_id uuid,p_acquisition_date date,p_depreciation_start date,p_cost numeric,p_salvage numeric,p_life_months integer,p_cash_account_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid(); v_entry uuid:=gen_random_uuid(); v_cash uuid; v_cost numeric(14,2):=round(p_cost,2); v_salvage numeric(14,2):=round(coalesce(p_salvage,0),2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإضافة أصل ثابت' using errcode='42501'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null or p_acquisition_date is null or p_depreciation_start is null or v_cost is null or v_cost<=0 or v_salvage<0 or v_salvage>=v_cost or p_life_months is null or p_life_months<1 then raise exception 'بيانات الأصل الثابت غير صحيحة' using errcode='22023'; end if;
 if not exists(select 1 from public.accounting_accounts where id=p_asset_account_id and account_type='asset' and is_active) or not exists(select 1 from public.accounting_accounts where id=p_accum_account_id and account_type='asset' and is_active) or not exists(select 1 from public.accounting_accounts where id=p_expense_account_id and account_type='expense' and is_active) then raise exception 'اختر حساب أصل ومجمع إهلاك ومصروف إهلاك فعالاً' using errcode='22023'; end if;
 select account_id into v_cash from public.cash_accounts where id=p_cash_account_id and is_active; if v_cash is null then raise exception 'اختر خزينة أو بنك فعال' using errcode='22023'; end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_acquisition_date,'اقتناء أصل ثابت: '||btrim(p_name),'fixed_asset_acquisition',v_id,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,p_asset_account_id,v_cost,0,'تكلفة الأصل الثابت'),(v_entry,v_cash,0,v_cost,'سداد قيمة الأصل');
 insert into public.fixed_assets(id,asset_name,description,asset_account_id,accumulated_depreciation_account_id,depreciation_expense_account_id,acquisition_date,depreciation_start_date,cost,salvage_value,useful_life_months,cash_account_id,acquisition_journal_entry_id,created_by)
 values(v_id,btrim(p_name),nullif(btrim(coalesce(p_description,'')),''),p_asset_account_id,p_accum_account_id,p_expense_account_id,p_acquisition_date,p_depreciation_start,p_cost,p_salvage,p_life_months,p_cash_account_id,v_entry,(select auth.uid()));
 return jsonb_build_object('fixed_asset_id',v_id,'journal_entry_id',v_entry); end $$;
create or replace function private.run_fixed_asset_depreciation(p_period_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.fixed_assets%rowtype; v_amount numeric(14,2); v_entry uuid; v_count integer:=0; v_total numeric(14,2):=0; v_period date:=date_trunc('month',p_period_date)::date;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بترحيل الإهلاك' using errcode='42501'; end if;
 if p_period_date is null or exists(select 1 from public.fiscal_periods where status='closed' and v_period between start_date and end_date) then raise exception 'تاريخ الإهلاك غير صالح أو يقع داخل فترة مقفلة' using errcode='23514'; end if;
 for a in select * from public.fixed_assets where status='active' and depreciation_start_date<=v_period order by id for update loop
  if exists(select 1 from public.fixed_asset_depreciations where fixed_asset_id=a.id and period_date=v_period) then continue; end if;
  v_amount:=least(round((a.cost-a.salvage_value)/a.useful_life_months,2),a.cost-a.salvage_value-a.accumulated_depreciation); if v_amount<=0 then continue; end if;
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values((v_period+interval '1 month - 1 day')::date,'إهلاك أصل ثابت رقم '||a.asset_number,'fixed_asset_depreciation',gen_random_uuid(),(select auth.uid())) returning id into v_entry;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,a.depreciation_expense_account_id,v_amount,0,'مصروف إهلاك شهري'),(v_entry,a.accumulated_depreciation_account_id,0,v_amount,'مجمع الإهلاك');
  insert into public.fixed_asset_depreciations(fixed_asset_id,period_date,amount,journal_entry_id,created_by) values(a.id,v_period,v_amount,v_entry,(select auth.uid()));
  update public.fixed_assets set accumulated_depreciation=accumulated_depreciation+v_amount where id=a.id;
  v_count:=v_count+1; v_total:=v_total+v_amount;
 end loop; return jsonb_build_object('period_date',v_period,'assets_count',v_count,'total_depreciation',v_total); end $$;
create or replace function private.create_bank_reconciliation(p_cash_account_id uuid,p_start date,p_end date,p_statement_balance numeric,p_notes text default null) returns uuid language plpgsql security definer set search_path='' as $$ declare v_id uuid; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسوية البنك' using errcode='42501'; end if;
 if p_cash_account_id is null or p_start is null or p_end is null or p_end<p_start or p_statement_balance is null then raise exception 'بيانات التسوية البنكية غير صحيحة' using errcode='22023'; end if;
 if not exists(select 1 from public.cash_accounts where id=p_cash_account_id and account_kind='bank' and is_active) then raise exception 'اختر حساباً بنكياً فعالاً' using errcode='22023'; end if;
 insert into public.bank_reconciliations(cash_account_id,period_start,period_end,statement_ending_balance,notes,created_by) values(p_cash_account_id,p_start,p_end,p_statement_balance,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning id into v_id; return v_id; end $$;
create or replace function private.add_bank_statement_line(p_reconciliation_id uuid,p_date date,p_description text,p_amount numeric,p_reference text default null) returns uuid language plpgsql security definer set search_path='' as $$ declare v_id uuid; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإضافة حركة كشف البنك' using errcode='42501'; end if;
 if p_date is null or nullif(btrim(coalesce(p_description,'')),'') is null or p_amount is null or p_amount=0 then raise exception 'بيانات حركة كشف البنك غير صحيحة' using errcode='22023'; end if;
 if not exists(select 1 from public.bank_reconciliations where id=p_reconciliation_id and status='open') then raise exception 'التسوية غير موجودة أو مكتملة' using errcode='P0002'; end if;
 insert into public.bank_reconciliation_lines(reconciliation_id,statement_date,description,amount,reference_number) values(p_reconciliation_id,p_date,btrim(p_description),p_amount,nullif(btrim(coalesce(p_reference,'')),'')) returning id into v_id; return v_id; end $$;
create or replace function private.match_bank_statement_line(p_line_id uuid,p_journal_line_id uuid) returns void language plpgsql security definer set search_path='' as $$ declare v_line public.bank_reconciliation_lines%rowtype; v_rec public.bank_reconciliations%rowtype; v_journal public.journal_entry_lines%rowtype; v_cash uuid; v_jdate date; v_jamount numeric(14,2); begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بمطابقة حركات البنك' using errcode='42501'; end if;
 select * into v_line from public.bank_reconciliation_lines where id=p_line_id for update; if not found then raise exception 'حركة كشف البنك غير موجودة' using errcode='P0002'; end if;
 select * into v_rec from public.bank_reconciliations where id=v_line.reconciliation_id and status='open' for update; if not found then raise exception 'التسوية البنكية غير مفتوحة' using errcode='23514'; end if;
 select * into v_journal from public.journal_entry_lines where id=p_journal_line_id; if not found then raise exception 'سطر القيد غير موجود' using errcode='P0002'; end if;
 select account_id into v_cash from public.cash_accounts where id=v_rec.cash_account_id;
 if v_journal.account_id<>v_cash then raise exception 'الحركة المحاسبية لا تخص الحساب البنكي المحدد' using errcode='23514'; end if;
 select entry_date into v_jdate from public.journal_entries where id=v_journal.journal_entry_id;
 if v_jdate not between v_rec.period_start and v_rec.period_end then raise exception 'تاريخ الحركة خارج فترة التسوية' using errcode='23514'; end if;
 v_jamount:=v_journal.debit-v_journal.credit; if abs(v_jamount-v_line.amount)>0.005 then raise exception 'قيمة الحركة لا تطابق قيمة السطر المحاسبي' using errcode='23514'; end if;
 update public.bank_reconciliation_lines set matched_journal_line_id=p_journal_line_id,matched_at=now() where id=p_line_id; end $$;
create or replace function private.complete_bank_reconciliation(p_reconciliation_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ declare v_rec public.bank_reconciliations%rowtype; v_unmatched integer; v_balance numeric(14,2); begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإكمال التسوية البنكية' using errcode='42501'; end if;
 select * into v_rec from public.bank_reconciliations where id=p_reconciliation_id for update; if not found or v_rec.status<>'open' then raise exception 'التسوية غير مفتوحة' using errcode='P0002'; end if;
 select count(*) into v_unmatched from public.bank_reconciliation_lines where reconciliation_id=p_reconciliation_id and matched_journal_line_id is null; if v_unmatched>0 then raise exception 'توجد حركات كشف غير مطابقة' using errcode='23514'; end if;
 select coalesce(sum(jel.debit-jel.credit),0) into v_balance from public.journal_entry_lines jel join public.journal_entries je on je.id=jel.journal_entry_id join public.cash_accounts ca on ca.account_id=jel.account_id where ca.id=v_rec.cash_account_id and je.entry_date<=v_rec.period_end and je.status='posted';
 if abs(v_balance-v_rec.statement_ending_balance)>0.005 then raise exception 'رصيد الدفاتر % لا يطابق رصيد كشف البنك %',v_balance,v_rec.statement_ending_balance using errcode='23514'; end if;
 update public.bank_reconciliations set status='completed',completed_at=now(),completed_by=(select auth.uid()) where id=p_reconciliation_id; return jsonb_build_object('status','completed','book_balance',v_balance,'statement_balance',v_rec.statement_ending_balance); end $$;
create or replace function private.create_cheque(p_type text,p_reference text,p_party text,p_cash_account_id uuid,p_amount numeric,p_issue date,p_due date,p_bank text default null,p_notes text default null) returns uuid language plpgsql security definer set search_path='' as $$ declare v_id uuid; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإدارة الشيكات' using errcode='42501'; end if;
 if p_type not in ('issued','received') or nullif(btrim(coalesce(p_reference,'')),'') is null or nullif(btrim(coalesce(p_party,'')),'') is null or p_cash_account_id is null or p_amount is null or p_amount<=0 or p_issue is null or p_due is null or p_due<p_issue then raise exception 'بيانات الشيك غير صحيحة' using errcode='22023'; end if;
 insert into public.cheques(cheque_type,cheque_reference,party_name,cash_account_id,amount,issue_date,due_date,bank_name,notes,created_by) values(p_type,btrim(p_reference),btrim(p_party),p_cash_account_id,round(p_amount,2),p_issue,p_due,nullif(btrim(coalesce(p_bank,'')),''),nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning id into v_id; return v_id; end $$;
create or replace function private.update_cheque_status(p_cheque_id uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$ declare v_cheque public.cheques%rowtype; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتحديث حالة الشيك' using errcode='42501'; end if;
 if p_status not in ('under_collection','cleared','bounced','cancelled') then raise exception 'حالة الشيك غير صحيحة' using errcode='22023'; end if;
 select * into v_cheque from public.cheques where id=p_cheque_id for update; if not found then raise exception 'الشيك غير موجود' using errcode='P0002'; end if;
 if v_cheque.status in ('cleared','bounced','cancelled') then raise exception 'لا يمكن تغيير حالة شيك نهائية' using errcode='23514'; end if;
 if v_cheque.cheque_type='issued' and p_status='under_collection' then raise exception 'الشيك الصادر لا يدخل تحت التحصيل' using errcode='23514'; end if;
 update public.cheques set status=p_status,cleared_at=case when p_status='cleared' then now() else null end where id=p_cheque_id; end $$;
create or replace function private.save_recurring_journal_template(p_name text,p_description text,p_frequency text,p_start date,p_end date,p_lines jsonb) returns uuid language plpgsql security definer set search_path='' as $$ declare v_id uuid; v_item jsonb; v_account uuid; v_d numeric(14,2); v_c numeric(14,2); v_debit numeric(14,2):=0; v_credit numeric(14,2):=0; v_count integer:=0; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإدارة القيود المتكررة' using errcode='42501'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null or p_frequency not in ('monthly','quarterly','yearly') or p_start is null or (p_end is not null and p_end<p_start) or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)<2 or jsonb_array_length(p_lines)>50 then raise exception 'بيانات القيد المتكرر غير صحيحة' using errcode='22023'; end if;
 insert into public.recurring_journal_templates(template_name,description,frequency,start_date,end_date,next_run_date,created_by) values(btrim(p_name),nullif(btrim(coalesce(p_description,'')),''),p_frequency,p_start,p_end,p_start,(select auth.uid())) returning id into v_id;
 for v_item in select value from jsonb_array_elements(p_lines) loop begin v_account:=(v_item->>'account_id')::uuid; v_d:=round(coalesce((v_item->>'debit')::numeric,0),2); v_c:=round(coalesce((v_item->>'credit')::numeric,0),2); exception when others then raise exception 'سطر القيد المتكرر غير صحيح' using errcode='22023'; end;
  if (v_d>0 and v_c>0) or (v_d<=0 and v_c<=0) or not exists(select 1 from public.accounting_accounts where id=v_account and is_active) then raise exception 'تحقق من الحساب والمدين والدائن في كل سطر' using errcode='22023'; end if;
  insert into public.recurring_journal_template_lines(template_id,account_id,debit,credit,memo) values(v_id,v_account,v_d,v_c,nullif(v_item->>'memo','')); v_debit:=v_debit+v_d; v_credit:=v_credit+v_c; v_count:=v_count+1; end loop;
 if v_count<2 or abs(v_debit-v_credit)>0.005 then raise exception 'القيد المتكرر غير متوازن' using errcode='23514'; end if; return v_id; end $$;
create or replace function private.generate_recurring_journal(p_template_id uuid,p_run_date date) returns jsonb language plpgsql security definer set search_path='' as $$ declare v_template public.recurring_journal_templates%rowtype; v_run uuid:=gen_random_uuid(); v_entry uuid:=gen_random_uuid(); v_next date; v_line record; begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بترحيل القيد المتكرر' using errcode='42501'; end if;
 select * into v_template from public.recurring_journal_templates where id=p_template_id and is_active for update; if not found then raise exception 'القيد المتكرر غير موجود أو غير نشط' using errcode='P0002'; end if;
 if p_run_date is null or p_run_date<v_template.start_date or (v_template.end_date is not null and p_run_date>v_template.end_date) or p_run_date<v_template.next_run_date then raise exception 'تاريخ الترحيل لا يطابق موعد القيد' using errcode='22023'; end if;
 if exists(select 1 from public.fiscal_periods where status='closed' and p_run_date between start_date and end_date) then raise exception 'الفترة المحاسبية مقفلة' using errcode='23514'; end if;
 if exists(select 1 from public.recurring_journal_runs where template_id=p_template_id and run_date=p_run_date) then raise exception 'تم ترحيل هذا الموعد بالفعل' using errcode='23505'; end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_run_date,v_template.template_name,'recurring_journal',v_run,(select auth.uid()));
 for v_line in select * from public.recurring_journal_template_lines where template_id=p_template_id loop insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_line.account_id,v_line.debit,v_line.credit,v_line.memo); end loop;
 insert into public.recurring_journal_runs(id,template_id,run_date,journal_entry_id,created_by) values(v_run,p_template_id,p_run_date,v_entry,(select auth.uid()));
 v_next:=case v_template.frequency when 'monthly' then (p_run_date+interval '1 month')::date when 'quarterly' then (p_run_date+interval '3 months')::date else (p_run_date+interval '1 year')::date end;
 update public.recurring_journal_templates set next_run_date=v_next,is_active=(v_template.end_date is null or v_next<=v_template.end_date) where id=p_template_id;
 return jsonb_build_object('run_id',v_run,'journal_entry_id',v_entry,'next_run_date',v_next); end $$;
create or replace function public.create_fiscal_period(text,text,date,date) returns uuid language sql security invoker set search_path='' as $$ select private.create_fiscal_period($1,$2,$3,$4) $$;
create or replace function public.close_fiscal_period(uuid) returns void language sql security invoker set search_path='' as $$ select private.close_fiscal_period($1) $$;
create or replace function public.create_cost_center(text,text,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_cost_center($1,$2,$3) $$;
create or replace function public.post_opening_balance(date,text,jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.post_opening_balance($1,$2,$3) $$;
create or replace function public.record_supplier_advance(uuid,date,numeric,uuid,text,text default null,text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.record_supplier_advance($1,$2,$3,$4,$5,$6,$7) $$;
create or replace function public.allocate_supplier_advance(uuid,uuid,numeric) returns jsonb language sql security invoker set search_path='' as $$ select private.allocate_supplier_advance($1,$2,$3) $$;
create or replace function public.create_fixed_asset(text,text,uuid,uuid,uuid,date,date,numeric,numeric,integer,uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.create_fixed_asset($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) $$;
create or replace function public.run_fixed_asset_depreciation(date) returns jsonb language sql security invoker set search_path='' as $$ select private.run_fixed_asset_depreciation($1) $$;
create or replace function public.create_bank_reconciliation(uuid,date,date,numeric,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_bank_reconciliation($1,$2,$3,$4,$5) $$;
create or replace function public.add_bank_statement_line(uuid,date,text,numeric,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.add_bank_statement_line($1,$2,$3,$4,$5) $$;
create or replace function public.match_bank_statement_line(uuid,uuid) returns void language sql security invoker set search_path='' as $$ select private.match_bank_statement_line($1,$2) $$;
create or replace function public.complete_bank_reconciliation(uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.complete_bank_reconciliation($1) $$;
create or replace function public.create_cheque(text,text,text,uuid,numeric,date,date,text default null,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_cheque($1,$2,$3,$4,$5,$6,$7,$8,$9) $$;
create or replace function public.update_cheque_status(uuid,text) returns void language sql security invoker set search_path='' as $$ select private.update_cheque_status($1,$2) $$;
create or replace function public.save_recurring_journal_template(text,text,text,date,date,jsonb) returns uuid language sql security invoker set search_path='' as $$ select private.save_recurring_journal_template($1,$2,$3,$4,$5,$6) $$;
create or replace function public.generate_recurring_journal(uuid,date) returns jsonb language sql security invoker set search_path='' as $$ select private.generate_recurring_journal($1,$2) $$;
do $$ declare sig text; begin for sig in select unnest(array[
 'public.create_fiscal_period(text,text,date,date)','public.close_fiscal_period(uuid)','public.create_cost_center(text,text,text)',
 'public.post_opening_balance(date,text,jsonb)','public.record_supplier_advance(uuid,date,numeric,uuid,text,text,text)','public.allocate_supplier_advance(uuid,uuid,numeric)',
 'public.create_fixed_asset(text,text,uuid,uuid,uuid,date,date,numeric,numeric,integer,uuid)','public.run_fixed_asset_depreciation(date)',
 'public.create_bank_reconciliation(uuid,date,date,numeric,text)','public.add_bank_statement_line(uuid,date,text,numeric,text)','public.match_bank_statement_line(uuid,uuid)',
 'public.complete_bank_reconciliation(uuid)','public.create_cheque(text,text,text,uuid,numeric,date,date,text,text)','public.update_cheque_status(uuid,text)',
 'public.save_recurring_journal_template(text,text,text,date,date,jsonb)','public.generate_recurring_journal(uuid,date)'
 ]) loop execute format('revoke all on function %s from public,anon',sig); execute format('grant execute on function %s to authenticated',sig); end loop; end $$;
