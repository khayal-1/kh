-- Source recovered from the applied production migration ledger.
insert into public.accounting_accounts(code,name,account_type,parent_code,is_system) values
('1250','سلف الموظفين','asset','1000',true),('2030','رواتب مستحقة','liability','2000',true),
('2040','تأمينات مستحقة','liability','2000',true),('2050','استقطاعات أخرى مستحقة','liability','2000',true),
('6080','مصروف حصة الشركة في التأمينات','expense','6000',true)
on conflict(code) do nothing;

create table if not exists public.employees(
 id uuid primary key default gen_random_uuid(), employee_code text not null unique,
 auth_user_id uuid unique references auth.users(id) on delete set null,
 full_name text not null, phone text, email text, job_title text, hire_date date not null,
 base_salary numeric(14,2) not null default 0 check(base_salary>=0),
 employment_status text not null default 'active' check(employment_status in ('active','terminated','suspended')),
 termination_date date, clearance_status text not null default 'pending' check(clearance_status in ('pending','cleared')),
 notes text, created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 check((employment_status='active' and termination_date is null) or (employment_status<>'active' and termination_date is not null))
);
create index if not exists employees_status_idx on public.employees(employment_status,full_name);

create table if not exists public.attendance_records(
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete restrict,
 attendance_date date not null, check_in timestamptz, check_out timestamptz,
 attendance_status text not null default 'present' check(attendance_status in ('present','absent','late','leave','holiday')),
 notes text, recorded_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 unique(employee_id,attendance_date), check(check_out is null or (check_in is not null and check_out>=check_in))
);
create table if not exists public.employee_leave_requests(
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete restrict,
 leave_type text not null check(leave_type in ('annual','sick','unpaid','emergency','other')),
 start_date date not null,end_date date not null,days numeric(6,2) not null check(days>0),reason text,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 reviewed_by uuid references auth.users(id) on delete restrict,reviewed_at timestamptz,
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),
 check(end_date>=start_date),
 check((status='pending' and reviewed_by is null and reviewed_at is null) or (status<>'pending' and reviewed_by is not null and reviewed_at is not null))
);
create table if not exists public.employee_custody(
 id uuid primary key default gen_random_uuid(), custody_number bigint generated always as identity unique,
 employee_id uuid not null references public.employees(id) on delete restrict,item_name text not null,description text,
 assigned_date date not null default current_date,estimated_value numeric(14,2) check(estimated_value is null or estimated_value>=0),
 status text not null default 'assigned' check(status in ('assigned','returned','lost','damaged')),
 returned_at timestamptz,return_notes text,created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),
 check((status='returned' and returned_at is not null) or (status<>'returned' and returned_at is null))
);
create table if not exists public.employee_advances(
 id uuid primary key default gen_random_uuid(),advance_number bigint generated always as identity unique,
 employee_id uuid not null references public.employees(id) on delete restrict,advance_date date not null,
 amount numeric(14,2) not null check(amount>0),repaid_amount numeric(14,2) not null default 0 check(repaid_amount>=0 and repaid_amount<=amount),
 cash_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 notes text,created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now()
);
create table if not exists public.sales_commissions(
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.employees(id) on delete restrict,
 sale_id uuid not null references public.sales(id) on delete restrict,amount numeric(14,2) not null check(amount>0),
 status text not null default 'pending' check(status in ('pending','included','paid','cancelled')),
 payroll_item_id uuid,notes text,created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),
 unique(employee_id,sale_id)
);
create table if not exists public.payroll_runs(
 id uuid primary key default gen_random_uuid(),payroll_number bigint generated always as identity unique,
 period_id uuid not null references public.fiscal_periods(id) on delete restrict,payroll_name text not null,payroll_date date not null,
 status text not null default 'draft' check(status in ('draft','posted')),
 journal_entry_id uuid unique references public.journal_entries(id) on delete restrict,
 total_gross numeric(14,2) not null default 0,total_net numeric(14,2) not null default 0,
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),
 posted_by uuid references auth.users(id) on delete restrict,posted_at timestamptz,
 check((status='draft' and journal_entry_id is null and posted_by is null and posted_at is null) or (status='posted' and journal_entry_id is not null and posted_by is not null and posted_at is not null))
);
create table if not exists public.payroll_items(
 id uuid primary key default gen_random_uuid(),payroll_run_id uuid not null references public.payroll_runs(id) on delete restrict,
 employee_id uuid not null references public.employees(id) on delete restrict,
 base_salary numeric(14,2) not null default 0 check(base_salary>=0),allowances numeric(14,2) not null default 0 check(allowances>=0),
 commission numeric(14,2) not null default 0 check(commission>=0),employee_insurance numeric(14,2) not null default 0 check(employee_insurance>=0),
 tax_deduction numeric(14,2) not null default 0 check(tax_deduction>=0),other_deductions numeric(14,2) not null default 0 check(other_deductions>=0),
 advance_deduction numeric(14,2) not null default 0 check(advance_deduction>=0),employer_insurance numeric(14,2) not null default 0 check(employer_insurance>=0),
 net_pay numeric(14,2) not null check(net_pay>=0),unique(payroll_run_id,employee_id)
);
create table if not exists public.employee_advance_repayments(
 id uuid primary key default gen_random_uuid(),employee_advance_id uuid not null references public.employee_advances(id) on delete restrict,
 payroll_item_id uuid not null references public.payroll_items(id) on delete restrict,amount numeric(14,2) not null check(amount>0),
 created_at timestamptz not null default now(),unique(employee_advance_id,payroll_item_id)
);
create table if not exists public.payroll_payments(
 id uuid primary key default gen_random_uuid(),payroll_run_id uuid not null references public.payroll_runs(id) on delete restrict,
 amount numeric(14,2) not null check(amount>0),cash_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 payment_date date not null default current_date,reference text,
 journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now()
);

alter table public.employees enable row level security;
alter table public.attendance_records enable row level security;
alter table public.employee_leave_requests enable row level security;
alter table public.employee_custody enable row level security;
alter table public.employee_advances enable row level security;
alter table public.sales_commissions enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_items enable row level security;
alter table public.employee_advance_repayments enable row level security;
alter table public.payroll_payments enable row level security;

revoke all on public.employees,public.attendance_records,public.employee_leave_requests,public.employee_custody,public.employee_advances,public.sales_commissions,public.payroll_runs,public.payroll_items,public.employee_advance_repayments,public.payroll_payments from anon,authenticated;
grant select on public.employees,public.attendance_records,public.employee_leave_requests,public.employee_custody,public.employee_advances,public.sales_commissions,public.payroll_runs,public.payroll_items,public.employee_advance_repayments,public.payroll_payments to authenticated;

create policy employees_hr_read on public.employees for select to authenticated using(
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage') or auth_user_id=(select auth.uid())
);
create policy attendance_hr_read on public.attendance_records for select to authenticated using(
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage')
 or exists(select 1 from public.employees e where e.id=attendance_records.employee_id and e.auth_user_id=(select auth.uid()))
);
create policy employee_leave_hr_read on public.employee_leave_requests for select to authenticated using(
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage')
 or exists(select 1 from public.employees e where e.id=employee_leave_requests.employee_id and e.auth_user_id=(select auth.uid()))
);
create policy employee_custody_hr_read on public.employee_custody for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));
create policy employee_advances_hr_read on public.employee_advances for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));
create policy sales_commissions_hr_read on public.sales_commissions for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));
create policy payroll_runs_hr_read on public.payroll_runs for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));
create policy payroll_items_hr_read on public.payroll_items for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage') or exists(select 1 from public.employees e where e.id=payroll_items.employee_id and e.auth_user_id=(select auth.uid())));
create policy employee_advance_repayments_hr_read on public.employee_advance_repayments for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));
create policy payroll_payments_hr_read on public.payroll_payments for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage'));

create or replace function private.create_employee(p_code text,p_user_id uuid,p_name text,p_phone text,p_email text,p_job text,p_hire_date date,p_salary numeric,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإدارة ملفات الموظفين' using errcode='42501'; end if;
 if nullif(btrim(coalesce(p_code,'')),'') is null or nullif(btrim(coalesce(p_name,'')),'') is null or p_hire_date is null or p_salary is null or p_salary<0 then raise exception 'بيانات الموظف غير صحيحة' using errcode='22023'; end if;
 if p_user_id is not null and not exists(select 1 from public.user_roles where user_id=p_user_id and role='employee') then raise exception 'حساب الدخول المختار ليس حساب موظف' using errcode='22023'; end if;
 insert into public.employees(employee_code,auth_user_id,full_name,phone,email,job_title,hire_date,base_salary,notes,created_by)
 values(btrim(p_code),p_user_id,btrim(p_name),nullif(btrim(coalesce(p_phone,'')),''),nullif(btrim(coalesce(p_email,'')),''),nullif(btrim(coalesce(p_job,'')),''),p_hire_date,p_salary,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning id into v_id;
 return v_id;
end $$;

create or replace function private.record_attendance(p_employee_id uuid,p_date date,p_status text,p_check_in timestamptz,p_check_out timestamptz,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not exists(select 1 from public.employees where id=p_employee_id and auth_user_id=(select auth.uid())) and not private.can_manage_finance() then raise exception 'غير مصرح بتسجيل الحضور لهذا الموظف' using errcode='42501'; end if;
 if p_date is null or p_status not in ('present','absent','late','leave','holiday') or (p_check_out is not null and (p_check_in is null or p_check_out<p_check_in)) then raise exception 'بيانات الحضور غير صحيحة' using errcode='22023'; end if;
 insert into public.attendance_records(employee_id,attendance_date,attendance_status,check_in,check_out,notes,recorded_by)
 values(p_employee_id,p_date,p_status,p_check_in,p_check_out,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()))
 on conflict(employee_id,attendance_date) do update set attendance_status=excluded.attendance_status,check_in=excluded.check_in,check_out=excluded.check_out,notes=excluded.notes,recorded_by=excluded.recorded_by returning id into v_id;
 return v_id;
end $$;

create or replace function private.create_employee_leave(p_employee_id uuid,p_type text,p_start date,p_end date,p_days numeric,p_reason text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not exists(select 1 from public.employees where id=p_employee_id and auth_user_id=(select auth.uid())) and not private.can_manage_finance() then raise exception 'غير مصرح بطلب إجازة لهذا الموظف' using errcode='42501'; end if;
 if p_type not in ('annual','sick','unpaid','emergency','other') or p_start is null or p_end is null or p_end<p_start or p_days is null or p_days<=0 then raise exception 'بيانات الإجازة غير صحيحة' using errcode='22023'; end if;
 insert into public.employee_leave_requests(employee_id,leave_type,start_date,end_date,days,reason,created_by) values(p_employee_id,p_type,p_start,p_end,p_days,nullif(btrim(coalesce(p_reason,'')),''),(select auth.uid())) returning id into v_id;
 return v_id;
end $$;

create or replace function private.review_employee_leave(p_leave_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بمراجعة الإجازات' using errcode='42501'; end if;
 if p_status not in ('approved','rejected') then raise exception 'حالة المراجعة غير صحيحة' using errcode='22023'; end if;
 update public.employee_leave_requests set status=p_status,reviewed_by=(select auth.uid()),reviewed_at=now() where id=p_leave_id and status='pending';
 if not found then raise exception 'طلب الإجازة غير موجود أو تمت مراجعته' using errcode='P0002'; end if;
end $$;

create or replace function private.create_employee_custody(p_employee_id uuid,p_item text,p_description text,p_date date,p_value numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإدارة عهد الموظفين' using errcode='42501'; end if;
 if not exists(select 1 from public.employees where id=p_employee_id and employment_status='active') or nullif(btrim(coalesce(p_item,'')),'') is null or p_date is null or (p_value is not null and p_value<0) then raise exception 'بيانات العهدة غير صحيحة' using errcode='22023'; end if;
 insert into public.employee_custody(employee_id,item_name,description,assigned_date,estimated_value,created_by) values(p_employee_id,btrim(p_item),nullif(btrim(coalesce(p_description,'')),''),p_date,p_value,(select auth.uid())) returning id into v_id;
 return v_id;
end $$;

create or replace function private.return_employee_custody(p_custody_id uuid,p_notes text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإثبات رد العهدة' using errcode='42501'; end if;
 update public.employee_custody set status='returned',returned_at=now(),return_notes=nullif(btrim(coalesce(p_notes,'')),'') where id=p_custody_id and status='assigned';
 if not found then raise exception 'العهدة غير موجودة أو ليست في حالة تسليم' using errcode='P0002'; end if;
end $$;

create or replace function private.terminate_employee(p_employee_id uuid,p_date date)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإنهاء ملف الموظف' using errcode='42501'; end if;
 if exists(select 1 from public.employee_custody where employee_id=p_employee_id and status='assigned') then raise exception 'لا يمكن إغلاق ملف الموظف قبل رد جميع العهد' using errcode='23514'; end if;
 if exists(select 1 from public.employee_advances where employee_id=p_employee_id and amount>repaid_amount) then raise exception 'لا يمكن إغلاق ملف الموظف قبل تسوية سلفه' using errcode='23514'; end if;
 update public.employees set employment_status='terminated',termination_date=p_date,clearance_status='cleared' where id=p_employee_id and employment_status='active';
 if not found then raise exception 'الموظف غير موجود أو غير نشط' using errcode='P0002'; end if;
end $$;

create or replace function private.record_employee_advance(p_employee_id uuid,p_date date,p_amount numeric,p_cash_account_id uuid,p_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid();v_entry uuid:=gen_random_uuid();v_adv uuid;v_cash uuid;v_amount numeric(14,2):=round(p_amount,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسجيل سلف الموظفين' using errcode='42501'; end if;
 if p_date is null or v_amount is null or v_amount<=0 or not exists(select 1 from public.employees where id=p_employee_id and employment_status='active') then raise exception 'بيانات سلفة الموظف غير صحيحة' using errcode='22023'; end if;
 select id into v_adv from public.accounting_accounts where code='1250' and is_active; select account_id into v_cash from public.cash_accounts where id=p_cash_account_id and is_active;
 if v_adv is null or v_cash is null then raise exception 'حساب سلف الموظفين أو الخزينة غير مهيأ' using errcode='22023'; end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_date,'سلفة موظف','employee_advance',v_id,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_adv,v_amount,0,'سلفة موظف'),(v_entry,v_cash,0,v_amount,'صرف سلفة موظف');
 insert into public.employee_advances(id,employee_id,advance_date,amount,cash_account_id,journal_entry_id,notes,created_by) values(v_id,p_employee_id,p_date,v_amount,p_cash_account_id,v_entry,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()));
 return jsonb_build_object('advance_id',v_id,'journal_entry_id',v_entry,'amount',v_amount);
end $$;

create or replace function private.create_sales_commission(p_employee_id uuid,p_sale_id uuid,p_amount numeric,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسجيل عمولات البيع' using errcode='42501'; end if;
 if p_amount is null or p_amount<=0 or not exists(select 1 from public.employees where id=p_employee_id and employment_status='active') or not exists(select 1 from public.sales where id=p_sale_id and status='posted') then raise exception 'بيانات عمولة البيع غير صحيحة' using errcode='22023'; end if;
 insert into public.sales_commissions(employee_id,sale_id,amount,notes,created_by) values(p_employee_id,p_sale_id,p_amount,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning id into v_id;
 return v_id;
end $$;

create or replace function private.create_payroll_run(p_period_id uuid,p_name text,p_date date,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_run uuid;v_item jsonb;v_employee uuid;v_base numeric(14,2);v_allow numeric(14,2);v_comm numeric(14,2);v_emp_ins numeric(14,2);v_tax numeric(14,2);v_other numeric(14,2);v_advance numeric(14,2);v_employer numeric(14,2);v_net numeric(14,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإعداد الرواتب' using errcode='42501'; end if;
 if not exists(select 1 from public.fiscal_periods where id=p_period_id and status='open') or p_date is null or nullif(btrim(coalesce(p_name,'')),'') is null or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>200 then raise exception 'بيانات كشف الرواتب غير صحيحة' using errcode='22023'; end if;
 insert into public.payroll_runs(period_id,payroll_name,payroll_date,created_by) values(p_period_id,btrim(p_name),p_date,(select auth.uid())) returning id into v_run;
 for v_item in select value from jsonb_array_elements(p_items) loop
  begin
   v_employee:=(v_item->>'employee_id')::uuid;v_base:=round(coalesce((v_item->>'base_salary')::numeric,0),2);v_allow:=round(coalesce((v_item->>'allowances')::numeric,0),2);
   v_emp_ins:=round(coalesce((v_item->>'employee_insurance')::numeric,0),2);v_tax:=round(coalesce((v_item->>'tax_deduction')::numeric,0),2);
   v_other:=round(coalesce((v_item->>'other_deductions')::numeric,0),2);v_advance:=round(coalesce((v_item->>'advance_deduction')::numeric,0),2);v_employer:=round(coalesce((v_item->>'employer_insurance')::numeric,0),2);
  exception when others then raise exception 'بيانات بند راتب غير صحيحة' using errcode='22023'; end;
  if not exists(select 1 from public.employees where id=v_employee and employment_status='active') or least(v_base,v_allow,v_emp_ins,v_tax,v_other,v_advance,v_employer)<0 then raise exception 'الموظف غير نشط أو توجد قيمة راتب سالبة' using errcode='22023'; end if;
  select coalesce(sum(amount),0) into v_comm from public.sales_commissions where employee_id=v_employee and status='pending';
  v_net:=v_base+v_allow+v_comm-v_emp_ins-v_tax-v_other-v_advance;
  if v_net<0 then raise exception 'استقطاعات الموظف تتجاوز مستحقاته' using errcode='23514'; end if;
  insert into public.payroll_items(payroll_run_id,employee_id,base_salary,allowances,commission,employee_insurance,tax_deduction,other_deductions,advance_deduction,employer_insurance,net_pay)
  values(v_run,v_employee,v_base,v_allow,v_comm,v_emp_ins,v_tax,v_other,v_advance,v_employer,v_net);
 end loop;
 return v_run;
end $$;

create or replace function private.post_payroll_run(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_run public.payroll_runs%rowtype;v_item public.payroll_items%rowtype;v_entry uuid:=gen_random_uuid();
 v_gross numeric(14,2);v_employer numeric(14,2);v_emp_ins numeric(14,2);v_tax numeric(14,2);v_other numeric(14,2);v_adv numeric(14,2);v_net numeric(14,2);
 v_wages uuid;v_ins_exp uuid;v_salary_payable uuid;v_ins_payable uuid;v_tax_payable uuid;v_other_payable uuid;v_adv_account uuid;
 v_advance public.employee_advances%rowtype;v_remaining numeric(14,2);v_apply numeric(14,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بترحيل الرواتب' using errcode='42501'; end if;
 select * into v_run from public.payroll_runs where id=p_run_id for update;if not found or v_run.status<>'draft' then raise exception 'كشف الرواتب غير موجود أو مرحل بالفعل' using errcode='P0002';end if;
 if exists(select 1 from public.fiscal_periods where id=v_run.period_id and status='closed') then raise exception 'الفترة المحاسبية مقفلة' using errcode='23514';end if;
 select coalesce(sum(base_salary+allowances+commission),0),coalesce(sum(employer_insurance),0),coalesce(sum(employee_insurance),0),coalesce(sum(tax_deduction),0),coalesce(sum(other_deductions),0),coalesce(sum(advance_deduction),0),coalesce(sum(net_pay),0)
 into v_gross,v_employer,v_emp_ins,v_tax,v_other,v_adv,v_net from public.payroll_items where payroll_run_id=p_run_id;
 if v_gross+v_employer<=0 then raise exception 'كشف الرواتب لا يحتوي مبالغ مستحقة' using errcode='23514';end if;
 select id into v_wages from public.accounting_accounts where code='6040';select id into v_ins_exp from public.accounting_accounts where code='6080';
 select id into v_salary_payable from public.accounting_accounts where code='2030';select id into v_ins_payable from public.accounting_accounts where code='2040';
 select id into v_tax_payable from public.accounting_accounts where code='2020';select id into v_other_payable from public.accounting_accounts where code='2050';select id into v_adv_account from public.accounting_accounts where code='1250';
 if v_wages is null or v_ins_exp is null or v_salary_payable is null or v_ins_payable is null or v_tax_payable is null or v_other_payable is null or v_adv_account is null then raise exception 'حسابات الرواتب غير مكتملة' using errcode='22023';end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,v_run.payroll_date,'كشف رواتب: '||v_run.payroll_name,'payroll_run',p_run_id,(select auth.uid()));
 if v_gross>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_wages,v_gross,0,'مصروف الأجور والبدلات والعمولات');end if;
 if v_employer>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_ins_exp,v_employer,0,'حصة الشركة في التأمينات');end if;
 if v_net>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_salary_payable,0,v_net,'صافي الرواتب المستحقة');end if;
 if v_emp_ins+v_employer>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_ins_payable,0,v_emp_ins+v_employer,'التأمينات المستحقة');end if;
 if v_tax>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_tax_payable,0,v_tax,'ضرائب واستقطاعات رواتب');end if;
 if v_other>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_other_payable,0,v_other,'استقطاعات أخرى');end if;
 if v_adv>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_adv_account,0,v_adv,'تسوية سلف الموظفين');end if;
 for v_item in select * from public.payroll_items where payroll_run_id=p_run_id loop
  v_remaining:=v_item.advance_deduction;
  if v_remaining>0 then
   for v_advance in select * from public.employee_advances where employee_id=v_item.employee_id and amount>repaid_amount order by advance_date,id for update loop
    v_apply:=least(v_remaining,v_advance.amount-v_advance.repaid_amount);
    if v_apply>0 then insert into public.employee_advance_repayments(employee_advance_id,payroll_item_id,amount) values(v_advance.id,v_item.id,v_apply);update public.employee_advances set repaid_amount=repaid_amount+v_apply where id=v_advance.id;v_remaining:=v_remaining-v_apply;end if;
    exit when v_remaining<=0;
   end loop;
   if v_remaining>0 then raise exception 'خصم السلفة أكبر من رصيد سلف الموظف: %',v_item.employee_id using errcode='23514';end if;
  end if;
  update public.sales_commissions set status='included',payroll_item_id=v_item.id where employee_id=v_item.employee_id and status='pending';
 end loop;
 update public.payroll_runs set status='posted',journal_entry_id=v_entry,posted_by=(select auth.uid()),posted_at=now(),total_gross=v_gross+v_employer,total_net=v_net where id=p_run_id;
 return jsonb_build_object('payroll_run_id',p_run_id,'journal_entry_id',v_entry,'gross',v_gross+v_employer,'net',v_net);
end $$;

create or replace function private.record_payroll_payment(p_run_id uuid,p_amount numeric,p_cash_account_id uuid,p_date date,p_reference text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_run public.payroll_runs%rowtype;v_paid numeric(14,2);v_due numeric(14,2);v_cash uuid;v_payable uuid;v_entry uuid:=gen_random_uuid();v_id uuid:=gen_random_uuid();
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بصرف الرواتب' using errcode='42501';end if;
 select * into v_run from public.payroll_runs where id=p_run_id and status='posted' for update;if not found then raise exception 'كشف الرواتب غير مرحل أو غير موجود' using errcode='P0002';end if;
 select coalesce(sum(amount),0) into v_paid from public.payroll_payments where payroll_run_id=p_run_id;v_due:=v_run.total_net-v_paid;
 if p_amount is null or p_amount<=0 or p_amount>v_due or p_date is null then raise exception 'قيمة صرف الرواتب تتجاوز الرصيد المستحق أو غير صحيحة' using errcode='23514';end if;
 select account_id into v_cash from public.cash_accounts where id=p_cash_account_id and is_active;select id into v_payable from public.accounting_accounts where code='2030';
 if v_cash is null or v_payable is null then raise exception 'حساب الخزينة أو الرواتب المستحقة غير جاهز' using errcode='22023';end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_date,'صرف رواتب كشف #'||v_run.payroll_number,'payroll_payment',v_id,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_payable,p_amount,0,'تخفيض الرواتب المستحقة'),(v_entry,v_cash,0,p_amount,'صرف الرواتب من الخزينة/البنك');
 insert into public.payroll_payments(id,payroll_run_id,amount,cash_account_id,payment_date,reference,journal_entry_id,created_by) values(v_id,p_run_id,p_amount,p_cash_account_id,p_date,nullif(btrim(coalesce(p_reference,'')),''),v_entry,(select auth.uid()));
 return jsonb_build_object('payment_id',v_id,'journal_entry_id',v_entry,'paid_total',v_paid+p_amount,'remaining_due',v_due-p_amount);
end $$;

create or replace function public.create_employee(text,uuid,text,text,text,text,date,numeric,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_employee($1,$2,$3,$4,$5,$6,$7,$8,$9) $$;
create or replace function public.record_attendance(uuid,date,text,timestamptz,timestamptz,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.record_attendance($1,$2,$3,$4,$5,$6) $$;
create or replace function public.create_employee_leave(uuid,text,date,date,numeric,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_employee_leave($1,$2,$3,$4,$5,$6) $$;
create or replace function public.review_employee_leave(uuid,text) returns void language sql security invoker set search_path='' as $$ select private.review_employee_leave($1,$2) $$;
create or replace function public.create_employee_custody(uuid,text,text,date,numeric) returns uuid language sql security invoker set search_path='' as $$ select private.create_employee_custody($1,$2,$3,$4,$5) $$;
create or replace function public.return_employee_custody(uuid,text default null) returns void language sql security invoker set search_path='' as $$ select private.return_employee_custody($1,$2) $$;
create or replace function public.terminate_employee(uuid,date) returns void language sql security invoker set search_path='' as $$ select private.terminate_employee($1,$2) $$;
create or replace function public.record_employee_advance(uuid,date,numeric,uuid,text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.record_employee_advance($1,$2,$3,$4,$5) $$;
create or replace function public.create_sales_commission(uuid,uuid,numeric,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_sales_commission($1,$2,$3,$4) $$;
create or replace function public.create_payroll_run(uuid,text,date,jsonb) returns uuid language sql security invoker set search_path='' as $$ select private.create_payroll_run($1,$2,$3,$4) $$;
create or replace function public.post_payroll_run(uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.post_payroll_run($1) $$;
create or replace function public.record_payroll_payment(uuid,numeric,uuid,date,text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.record_payroll_payment($1,$2,$3,$4,$5) $$;
do $$ declare sig text; begin
 for sig in select unnest(array[
 'public.create_employee(text,uuid,text,text,text,text,date,numeric,text)','public.record_attendance(uuid,date,text,timestamptz,timestamptz,text)',
 'public.create_employee_leave(uuid,text,date,date,numeric,text)','public.review_employee_leave(uuid,text)','public.create_employee_custody(uuid,text,text,date,numeric)',
 'public.return_employee_custody(uuid,text)','public.terminate_employee(uuid,date)','public.record_employee_advance(uuid,date,numeric,uuid,text)',
 'public.create_sales_commission(uuid,uuid,numeric,text)','public.create_payroll_run(uuid,text,date,jsonb)','public.post_payroll_run(uuid)',
 'public.record_payroll_payment(uuid,numeric,uuid,date,text)'
 ]) loop execute format('revoke all on function %s from public,anon',sig);execute format('grant execute on function %s to authenticated',sig);end loop;
end $$;

