create schema if not exists private;
grant usage on schema private to authenticated;

create table if not exists public.accounting_accounts (
 id uuid primary key default gen_random_uuid(), code text not null unique, name text not null,
 account_type text not null check(account_type in ('asset','liability','equity','revenue','expense')),
 parent_code text references public.accounting_accounts(code), is_system boolean not null default false,
 is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.cash_accounts (
 id uuid primary key default gen_random_uuid(), name text not null,
 account_id uuid not null unique references public.accounting_accounts(id),
 account_kind text not null default 'cash' check(account_kind in ('cash','bank')),
 currency char(3) not null default 'EGP', is_active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.journal_entries (
 id uuid primary key default gen_random_uuid(), entry_number bigint generated always as identity unique,
 entry_date date not null default current_date, description text not null, source_type text not null,
 source_id uuid, status text not null default 'posted' check(status in ('posted','reversed')),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(source_type,source_id)
);
create table if not exists public.journal_entry_lines (
 id uuid primary key default gen_random_uuid(), journal_entry_id uuid not null references public.journal_entries(id) on delete cascade,
 account_id uuid not null references public.accounting_accounts(id),
 debit numeric(14,2) not null default 0 check(debit>=0), credit numeric(14,2) not null default 0 check(credit>=0),
 memo text, created_at timestamptz not null default now(),
 check((debit>0 and credit=0) or (credit>0 and debit=0))
);
create table if not exists public.expenses (
 id uuid primary key default gen_random_uuid(), expense_number bigint generated always as identity unique,
 expense_date date not null default current_date, description text not null, vendor_name text,
 reference_number text, expense_account_id uuid not null references public.accounting_accounts(id),
 amount numeric(14,2) not null check(amount>0), paid_amount numeric(14,2) not null default 0 check(paid_amount>=0 and paid_amount<=amount),
 due_date date, notes text, journal_entry_id uuid references public.journal_entries(id),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.expense_payments (
 id uuid primary key default gen_random_uuid(), payment_number bigint generated always as identity unique,
 expense_id uuid not null references public.expenses(id), cash_account_id uuid not null references public.cash_accounts(id),
 amount numeric(14,2) not null check(amount>0),
 payment_method text not null check(payment_method in ('cash','bank_transfer','card','instapay','cheque','other')),
 reference_number text, paid_at timestamptz not null default now(), journal_entry_id uuid references public.journal_entries(id),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);

insert into public.accounting_accounts(code,name,account_type,parent_code,is_system) values
('1000','الأصول','asset',null,true),('1010','الخزينة الرئيسية','asset','1000',true),
('1020','البنوك','asset','1000',true),('1100','العملاء / الذمم المدينة','asset','1000',true),
('1200','مخزون الدراجات','asset','1000',true),('1500','الأصول الثابتة','asset','1000',true),
('2000','الالتزامات','liability',null,true),('2010','الموردون والمصروفات المستحقة','liability','2000',true),
('2020','ضرائب مستحقة','liability','2000',true),('3000','حقوق الملكية','equity',null,true),
('3010','رأس المال','equity','3000',true),('4000','الإيرادات','revenue',null,true),
('4010','إيرادات بيع الدراجات','revenue','4000',true),('5000','تكلفة البضاعة المباعة','expense',null,true),
('6000','المصروفات التشغيلية','expense',null,true),('6010','الإيجارات','expense','6000',true),
('6020','الكهرباء والمرافق','expense','6000',true),('6030','الصيانة والإصلاحات','expense','6000',true),
('6040','الأجور والرواتب','expense','6000',true),('6050','النقل والشحن','expense','6000',true),
('6060','التسويق والإعلانات','expense','6000',true),('6090','مصروفات أخرى','expense','6000',true)
on conflict(code) do nothing;
insert into public.cash_accounts(name,account_id,account_kind,currency)
select 'الخزينة الرئيسية',id,'cash','EGP' from public.accounting_accounts where code='1010'
on conflict(account_id) do nothing;

create index if not exists journal_entries_date_idx on public.journal_entries(entry_date desc);
create index if not exists journal_lines_entry_idx on public.journal_entry_lines(journal_entry_id);
create index if not exists journal_lines_account_idx on public.journal_entry_lines(account_id);
create index if not exists expenses_date_idx on public.expenses(expense_date desc);
create index if not exists expense_payments_expense_idx on public.expense_payments(expense_id,paid_at desc);

alter table public.accounting_accounts enable row level security;
alter table public.cash_accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_entry_lines enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_payments enable row level security;

drop policy if exists accounting_accounts_read on public.accounting_accounts;
create policy accounting_accounts_read on public.accounting_accounts for select to authenticated using (
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('accounting_view') or public.has_employee_permission('expenses_manage'));
drop policy if exists cash_accounts_read on public.cash_accounts;
create policy cash_accounts_read on public.cash_accounts for select to authenticated using (
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('accounting_view') or public.has_employee_permission('expenses_manage'));
drop policy if exists journal_entries_read on public.journal_entries;
create policy journal_entries_read on public.journal_entries for select to authenticated using (
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('accounting_view'));
drop policy if exists journal_lines_read on public.journal_entry_lines;
create policy journal_lines_read on public.journal_entry_lines for select to authenticated using (
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('accounting_view'));
drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses for select to authenticated using (
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('accounting_view') or public.has_employee_permission('expenses_manage'));
drop policy if exists expense_payments_read on public.expense_payments;
create policy expense_payments_read on public.expense_payments for select to authenticated using (
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('accounting_view') or public.has_employee_permission('expenses_manage'));
grant select on public.accounting_accounts,public.cash_accounts,public.journal_entries,public.journal_entry_lines,public.expenses,public.expense_payments to authenticated;

create or replace function private.create_expense(
 p_expense_date date,p_description text,p_expense_account_id uuid,p_amount numeric,p_paid_amount numeric default 0,
 p_cash_account_id uuid default null,p_payment_method text default 'cash',p_vendor_name text default null,
 p_reference_number text default null,p_due_date date default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=(select auth.uid()); v_expense_id uuid; v_entry_id uuid;
 v_amount numeric(14,2):=round(p_amount,2); v_paid numeric(14,2):=round(coalesce(p_paid_amount,0),2);
 v_expense_name text; v_cash_account uuid; v_payable_account uuid;
begin
 if v_user is null or not (public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('expenses_manage')) then
  raise exception 'غير مصرح بتسجيل المصروفات' using errcode='42501';
 end if;
 if p_expense_date is null or nullif(btrim(coalesce(p_description,'')),'') is null or p_expense_account_id is null
  or v_amount is null or v_amount<=0 or v_paid<0 or v_paid>v_amount then
  raise exception 'بيانات المصروف غير صحيحة' using errcode='22023';
 end if;
 select name into v_expense_name from public.accounting_accounts where id=p_expense_account_id and account_type='expense' and is_active;
 if not found then raise exception 'اختر بند مصروف فعال' using errcode='22023'; end if;
 if v_paid>0 then
  if p_cash_account_id is null then raise exception 'اختر الخزينة أو البنك للمبلغ المدفوع' using errcode='22023'; end if;
  select account_id into v_cash_account from public.cash_accounts where id=p_cash_account_id and is_active;
  if not found then raise exception 'حساب الخزينة أو البنك غير فعال' using errcode='22023'; end if;
  if coalesce(p_payment_method,'') not in ('cash','bank_transfer','card','instapay','cheque','other') then raise exception 'طريقة الدفع غير صحيحة' using errcode='22023'; end if;
 end if;
 select id into v_payable_account from public.accounting_accounts where code='2010' and is_active;
 insert into public.expenses(expense_date,description,vendor_name,reference_number,expense_account_id,amount,paid_amount,due_date,notes,created_by)
 values(p_expense_date,btrim(p_description),nullif(btrim(coalesce(p_vendor_name,'')),''),nullif(btrim(coalesce(p_reference_number,'')),''),p_expense_account_id,v_amount,v_paid,p_due_date,nullif(btrim(coalesce(p_notes,'')),''),v_user)
 returning id into v_expense_id;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
 values(p_expense_date,'مصروف: '||btrim(p_description),'expense',v_expense_id,v_user) returning id into v_entry_id;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry_id,p_expense_account_id,v_amount,0,v_expense_name);
 if v_paid>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry_id,v_cash_account,0,v_paid,'المدفوع من الخزينة / البنك'); end if;
 if v_amount>v_paid then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry_id,v_payable_account,0,v_amount-v_paid,'المتبقي المستحق'); end if;
 update public.expenses set journal_entry_id=v_entry_id where id=v_expense_id;
 if v_paid>0 then
  insert into public.expense_payments(expense_id,cash_account_id,amount,payment_method,reference_number,journal_entry_id,created_by)
  values(v_expense_id,p_cash_account_id,v_paid,coalesce(p_payment_method,'cash'),nullif(btrim(coalesce(p_reference_number,'')),''),v_entry_id,v_user);
 end if;
 return jsonb_build_object('expense_id',v_expense_id,'journal_entry_id',v_entry_id,'amount',v_amount,'paid_amount',v_paid,'balance_due',v_amount-v_paid);
end; $$;

create or replace function private.record_expense_payment(p_expense_id uuid,p_cash_account_id uuid,p_amount numeric,p_payment_method text default 'cash',p_reference_number text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=(select auth.uid()); v_expense public.expenses%rowtype; v_cash_account uuid;
 v_payable_account uuid; v_entry_id uuid; v_payment_id uuid; v_due numeric(14,2); v_amount numeric(14,2):=round(p_amount,2);
begin
 if v_user is null or not (public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('expenses_manage')) then
  raise exception 'غير مصرح بتسجيل سداد المصروفات' using errcode='42501';
 end if;
 if p_expense_id is null or p_cash_account_id is null or v_amount is null or v_amount<=0
  or coalesce(p_payment_method,'') not in ('cash','bank_transfer','card','instapay','cheque','other') then raise exception 'بيانات السداد غير صحيحة' using errcode='22023'; end if;
 select * into v_expense from public.expenses where id=p_expense_id for update;
 if not found then raise exception 'المصروف غير موجود' using errcode='P0002'; end if;
 v_due:=v_expense.amount-v_expense.paid_amount;
 if v_amount>v_due then raise exception 'قيمة السداد تتجاوز المبلغ المستحق' using errcode='23514'; end if;
 select account_id into v_cash_account from public.cash_accounts where id=p_cash_account_id and is_active;
 if not found then raise exception 'حساب الخزينة أو البنك غير فعال' using errcode='22023'; end if;
 select id into v_payable_account from public.accounting_accounts where code='2010' and is_active;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
 values(current_date,'سداد مصروف رقم '||v_expense.expense_number,'expense_payment',gen_random_uuid(),v_user) returning id into v_entry_id;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry_id,v_payable_account,v_amount,0,'تخفيض المصروفات المستحقة');
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry_id,v_cash_account,0,v_amount,'سداد من الخزينة / البنك');
 insert into public.expense_payments(expense_id,cash_account_id,amount,payment_method,reference_number,journal_entry_id,created_by)
 values(p_expense_id,p_cash_account_id,v_amount,p_payment_method,nullif(btrim(coalesce(p_reference_number,'')),''),v_entry_id,v_user) returning id into v_payment_id;
 update public.expenses set paid_amount=paid_amount+v_amount,updated_at=now() where id=p_expense_id;
 return jsonb_build_object('payment_id',v_payment_id,'expense_id',p_expense_id,'paid_amount',v_expense.paid_amount+v_amount,'balance_due',v_due-v_amount);
end; $$;

revoke all on function private.create_expense(date,text,uuid,numeric,numeric,uuid,text,text,text,date,text) from public,anon;
revoke all on function private.record_expense_payment(uuid,uuid,numeric,text,text) from public,anon;
grant execute on function private.create_expense(date,text,uuid,numeric,numeric,uuid,text,text,text,date,text) to authenticated;
grant execute on function private.record_expense_payment(uuid,uuid,numeric,text,text) to authenticated;
create or replace function public.create_expense(p_expense_date date,p_description text,p_expense_account_id uuid,p_amount numeric,p_paid_amount numeric default 0,p_cash_account_id uuid default null,p_payment_method text default 'cash',p_vendor_name text default null,p_reference_number text default null,p_due_date date default null,p_notes text default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.create_expense($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11); $$;
create or replace function public.record_expense_payment(p_expense_id uuid,p_cash_account_id uuid,p_amount numeric,p_payment_method text default 'cash',p_reference_number text default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.record_expense_payment($1,$2,$3,$4,$5); $$;
revoke all on function public.create_expense(date,text,uuid,numeric,numeric,uuid,text,text,text,date,text) from public,anon;
revoke all on function public.record_expense_payment(uuid,uuid,numeric,text,text) from public,anon;
grant execute on function public.create_expense(date,text,uuid,numeric,numeric,uuid,text,text,text,date,text) to authenticated;
grant execute on function public.record_expense_payment(uuid,uuid,numeric,text,text) to authenticated;