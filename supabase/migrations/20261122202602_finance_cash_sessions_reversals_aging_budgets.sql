-- Source recovered from the applied production migration ledger.
insert into public.accounting_accounts(code,name,account_type,parent_code,is_system)
values ('4090','إيرادات وفروق أخرى','revenue','4000',true),('6095','عجز الخزينة وفروق النقدية','expense','6000',true)
on conflict(code) do nothing;

create table if not exists public.cash_sessions (
 id uuid primary key default gen_random_uuid(), session_number bigint generated always as identity unique,
 cash_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 opened_by uuid not null references auth.users(id) on delete restrict, opened_at timestamptz not null default now(),
 opening_balance numeric(14,2) not null, expected_closing numeric(14,2), actual_closing numeric(14,2),
 difference numeric(14,2), status text not null default 'open' check(status in ('open','closed')),
 closed_by uuid references auth.users(id) on delete restrict, closed_at timestamptz,
 opening_note text, closing_note text,
 check((status='open' and closed_at is null and closed_by is null and actual_closing is null)
  or (status='closed' and closed_at is not null and closed_by is not null and actual_closing is not null))
);
create unique index if not exists one_open_cash_session_per_account on public.cash_sessions(cash_account_id) where status='open';
create index if not exists cash_sessions_opened_at_idx on public.cash_sessions(opened_at desc);

create table if not exists public.cash_handovers (
 id uuid primary key default gen_random_uuid(), handover_number bigint generated always as identity unique,
 cash_session_id uuid not null references public.cash_sessions(id) on delete restrict,
 from_user_id uuid not null references auth.users(id) on delete restrict,
 to_user_id uuid not null references auth.users(id) on delete restrict,
 amount numeric(14,2) not null check(amount>0), notes text,
 status text not null default 'pending' check(status in ('pending','accepted','rejected')),
 created_at timestamptz not null default now(), responded_at timestamptz,
 check(from_user_id<>to_user_id),
 check((status='pending' and responded_at is null) or (status<>'pending' and responded_at is not null))
);

create table if not exists public.finance_settings (
 id boolean primary key default true check(id),
 petty_cash_limit numeric(14,2) check(petty_cash_limit is null or petty_cash_limit>0),
 updated_by uuid references auth.users(id) on delete restrict,
 updated_at timestamptz not null default now()
);
insert into public.finance_settings(id,petty_cash_limit) values(true,null) on conflict(id) do nothing;

create table if not exists public.petty_cash_transactions (
 id uuid primary key default gen_random_uuid(), transaction_number bigint generated always as identity unique,
 transaction_date date not null, description text not null,
 expense_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 cash_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 amount numeric(14,2) not null check(amount>0), recipient text, reference text,
 journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now()
);

create table if not exists public.journal_entry_reversals (
 id uuid primary key default gen_random_uuid(),
 original_journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 reversal_journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 reason text not null, created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);

create table if not exists public.finance_budgets (
 id uuid primary key default gen_random_uuid(), budget_number bigint generated always as identity unique,
 period_id uuid not null references public.fiscal_periods(id) on delete restrict,
 budget_name text not null, status text not null default 'draft' check(status in ('draft','approved')),
 approved_by uuid references auth.users(id) on delete restrict, approved_at timestamptz,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 check((status='draft' and approved_by is null and approved_at is null) or (status='approved' and approved_by is not null and approved_at is not null))
);
create table if not exists public.finance_budget_lines (
 id uuid primary key default gen_random_uuid(), budget_id uuid not null references public.finance_budgets(id) on delete cascade,
 account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 cost_center_id uuid references public.cost_centers(id) on delete restrict,
 budget_amount numeric(14,2) not null check(budget_amount>=0),
 unique(budget_id,account_id,cost_center_id)
);

create table if not exists public.accrual_schedules (
 id uuid primary key default gen_random_uuid(), schedule_number bigint generated always as identity unique,
 schedule_name text not null, description text,
 debit_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 credit_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 monthly_amount numeric(14,2) not null check(monthly_amount>0),
 start_date date not null, end_date date,
 next_run_date date not null, is_active boolean not null default true,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 check(end_date is null or end_date>=start_date), check(debit_account_id<>credit_account_id)
);
create table if not exists public.accrual_runs (
 id uuid primary key default gen_random_uuid(), schedule_id uuid not null references public.accrual_schedules(id) on delete restrict,
 run_date date not null, amount numeric(14,2) not null check(amount>0),
 journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
 unique(schedule_id,run_date)
);

do $$ declare t text; begin
 foreach t in array array['cash_sessions','cash_handovers','finance_settings','petty_cash_transactions','journal_entry_reversals','finance_budgets','finance_budget_lines','accrual_schedules','accrual_runs'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy %I on public.%I for select to authenticated using (public.has_any_role(array[''manager'',''owner'',''admin'']::public.app_role[]) or public.has_employee_permission(''accounting_view'') or public.has_employee_permission(''finance_manage''))',t||'_finance_read',t);
 end loop;
end $$;

create or replace function private.open_cash_session(p_cash_account_id uuid,p_opening_balance numeric,p_note text default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_system_balance numeric(14,2); v_kind text;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بفتح جلسة خزينة' using errcode='42501'; end if;
 if p_cash_account_id is null or p_opening_balance is null or p_opening_balance<0 then raise exception 'بيانات فتح الجلسة غير صحيحة' using errcode='22023'; end if;
 select account_kind into v_kind from public.cash_accounts where id=p_cash_account_id and is_active;
 if v_kind is null then raise exception 'الخزينة غير موجودة أو غير نشطة' using errcode='22023'; end if;
 if v_kind<>'cash' then raise exception 'جلسات الفتح والإقفال اليومية مخصصة للخزائن النقدية' using errcode='22023'; end if;
 select coalesce(balance,0) into v_system_balance from public.accounting_cash_balances where cash_account_id=p_cash_account_id;
 if abs(coalesce(p_opening_balance,0)-coalesce(v_system_balance,0))>0.005 then
  raise exception 'الرصيد الفعلي الافتتاحي % لا يطابق رصيد النظام %؛ سوّ الفرق قبل فتح الجلسة',p_opening_balance,v_system_balance using errcode='23514';
 end if;
 insert into public.cash_sessions(cash_account_id,opened_by,opening_balance,opening_note)
 values(p_cash_account_id,(select auth.uid()),p_opening_balance,nullif(btrim(coalesce(p_note,'')),'')) returning id into v_id;
 return v_id;
end $$;

create or replace function private.close_cash_session(p_session_id uuid,p_actual_closing numeric,p_note text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_session public.cash_sessions%rowtype; v_account uuid; v_expected numeric(14,2); v_diff numeric(14,2); v_entry uuid; v_cash uuid; v_offset uuid;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإقفال جلسة الخزينة' using errcode='42501'; end if;
 if p_actual_closing is null or p_actual_closing<0 then raise exception 'الرصيد الفعلي غير صحيح' using errcode='22023'; end if;
 select * into v_session from public.cash_sessions where id=p_session_id for update;
 if not found or v_session.status<>'open' then raise exception 'جلسة الخزينة غير مفتوحة' using errcode='P0002'; end if;
 select account_id into v_account from public.cash_accounts where id=v_session.cash_account_id;
 select coalesce(v_session.opening_balance,0)+coalesce(sum(jel.debit-jel.credit),0)
 into v_expected from public.journal_entry_lines jel join public.journal_entries je on je.id=jel.journal_entry_id
 where jel.account_id=v_account and je.status='posted' and je.created_at>=v_session.opened_at;
 v_diff:=round(p_actual_closing-v_expected,2);
 if abs(v_diff)>0.005 then
  select id into v_cash from public.accounting_accounts where code='1010';
  select id into v_offset from public.accounting_accounts where code=case when v_diff<0 then '6095' else '4090' end;
  if v_cash is null or v_offset is null then raise exception 'حساب فروق النقدية غير مهيأ' using errcode='22023'; end if;
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
  values(current_date,'تسوية فرق إقفال جلسة خزينة #'||v_session.session_number,'cash_session_adjustment',p_session_id,(select auth.uid())) returning id into v_entry;
  if v_diff<0 then
   insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_offset,abs(v_diff),0,'عجز نقدي عند إقفال الخزينة'),(v_entry,v_account,0,abs(v_diff),'تخفيض رصيد الخزينة الفعلي');
  else
   insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_account,v_diff,0,'زيادة نقدية عند إقفال الخزينة'),(v_entry,v_offset,0,v_diff,'إيراد فرق جرد نقدي');
  end if;
 end if;
 update public.cash_sessions set expected_closing=v_expected,actual_closing=p_actual_closing,difference=v_diff,status='closed',closed_by=(select auth.uid()),closed_at=now(),closing_note=nullif(btrim(coalesce(p_note,'')),'') where id=p_session_id;
 return jsonb_build_object('session_id',p_session_id,'expected_closing',v_expected,'actual_closing',p_actual_closing,'difference',v_diff,'journal_entry_id',v_entry);
end $$;

create or replace function private.create_cash_handover(p_session_id uuid,p_to_user_id uuid,p_amount numeric,p_notes text default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if (select auth.uid()) is null or not private.can_manage_finance() then raise exception 'غير مصرح بتسليم النقدية' using errcode='42501'; end if;
 if p_to_user_id is null or p_amount is null or p_amount<=0 then raise exception 'بيانات التسليم غير صحيحة' using errcode='22023'; end if;
 if not exists(select 1 from public.cash_sessions where id=p_session_id and status='open') then raise exception 'جلسة الخزينة غير مفتوحة' using errcode='23514'; end if;
 insert into public.cash_handovers(cash_session_id,from_user_id,to_user_id,amount,notes)
 values(p_session_id,(select auth.uid()),p_to_user_id,p_amount,nullif(btrim(coalesce(p_notes,'')),'')) returning id into v_id;
 return v_id;
end $$;

create or replace function private.respond_cash_handover(p_handover_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path=''
as $$
begin
 update public.cash_handovers set status=case when p_accept then 'accepted' else 'rejected' end,responded_at=now()
 where id=p_handover_id and to_user_id=(select auth.uid()) and status='pending';
 if not found then raise exception 'التسليم غير موجود أو لا يخص حسابك أو تمت معالجته' using errcode='P0002'; end if;
end $$;

create or replace function private.set_petty_cash_limit(p_limit numeric)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بضبط حد المصروفات النثرية' using errcode='42501'; end if;
 if p_limit is null or p_limit<=0 then raise exception 'يجب إدخال حد موجب للمصروفات النثرية' using errcode='22023'; end if;
 insert into public.finance_settings(id,petty_cash_limit,updated_by,updated_at) values(true,p_limit,(select auth.uid()),now())
 on conflict(id) do update set petty_cash_limit=excluded.petty_cash_limit,updated_by=excluded.updated_by,updated_at=now();
end $$;

create or replace function private.create_petty_cash(p_date date,p_description text,p_expense_account_id uuid,p_cash_account_id uuid,p_amount numeric,p_recipient text default null,p_reference text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_limit numeric(14,2); v_cash uuid; v_id uuid:=gen_random_uuid(); v_entry uuid:=gen_random_uuid(); v_amount numeric(14,2):=round(p_amount,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسجيل المصروفات النثرية' using errcode='42501'; end if;
 select petty_cash_limit into v_limit from public.finance_settings where id=true;
 if v_limit is null then raise exception 'اضبط حد المصروفات النثرية قبل تسجيل أول حركة' using errcode='23514'; end if;
 if v_amount is null or v_amount<=0 or v_amount>v_limit or p_date is null or nullif(btrim(coalesce(p_description,'')),'') is null then raise exception 'المبلغ أو بيانات المصروف النثري غير صحيحة أو تتجاوز الحد' using errcode='22023'; end if;
 if not exists(select 1 from public.accounting_accounts where id=p_expense_account_id and account_type='expense' and is_active) then raise exception 'اختر حساب مصروف فعالاً' using errcode='22023'; end if;
 select account_id into v_cash from public.cash_accounts where id=p_cash_account_id and account_kind='cash' and is_active;
 if v_cash is null then raise exception 'اختر خزينة نقدية فعالة' using errcode='22023'; end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_date,btrim(p_description),'petty_cash',v_id,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,p_expense_account_id,v_amount,0,'مصروف نثري'),(v_entry,v_cash,0,v_amount,'صرف من الخزينة النثرية');
 insert into public.petty_cash_transactions(id,transaction_date,description,expense_account_id,cash_account_id,amount,recipient,reference,journal_entry_id,created_by)
 values(v_id,p_date,btrim(p_description),p_expense_account_id,p_cash_account_id,v_amount,nullif(btrim(coalesce(p_recipient,'')),''),nullif(btrim(coalesce(p_reference,'')),''),v_entry,(select auth.uid()));
 return jsonb_build_object('id',v_id,'journal_entry_id',v_entry,'amount',v_amount);
end $$;

create or replace function private.reverse_journal_entry(p_original_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_original public.journal_entries%rowtype; v_reversal uuid:=gen_random_uuid(); v_link uuid:=gen_random_uuid(); v_line record;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بعكس القيود' using errcode='42501'; end if;
 select * into v_original from public.journal_entries where id=p_original_id for update;
 if not found or v_original.status<>'posted' then raise exception 'القيد الأصلي غير موجود أو غير مرحل' using errcode='P0002'; end if;
 if exists(select 1 from public.journal_entry_reversals where original_journal_entry_id=p_original_id) then raise exception 'تم عكس هذا القيد من قبل' using errcode='23505'; end if;
 if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'سبب العكس مطلوب' using errcode='22023'; end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by)
 values(v_reversal,current_date,'عكس القيد #'||v_original.entry_number||': '||btrim(p_reason),'journal_reversal',v_link,(select auth.uid()));
 for v_line in select * from public.journal_entry_lines where journal_entry_id=p_original_id order by id loop
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo,cost_center_id)
  values(v_reversal,v_line.account_id,v_line.credit,v_line.debit,'عكس: '||coalesce(v_line.memo,''),v_line.cost_center_id);
 end loop;
 insert into public.journal_entry_reversals(id,original_journal_entry_id,reversal_journal_entry_id,reason,created_by)
 values(v_link,p_original_id,v_reversal,btrim(p_reason),(select auth.uid()));
 update public.journal_entries set source_id=v_link where id=v_reversal;
 return jsonb_build_object('reversal_id',v_link,'reversal_journal_entry_id',v_reversal,'original_entry_number',v_original.entry_number);
end $$;

create or replace function private.create_finance_budget(p_period_id uuid,p_name text,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_budget uuid; v_item jsonb; v_account uuid; v_center uuid; v_amount numeric(14,2); v_count integer:=0;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإنشاء الموازنة' using errcode='42501'; end if;
 if not exists(select 1 from public.fiscal_periods where id=p_period_id and status='open') then raise exception 'اختر فترة مالية مفتوحة' using errcode='23514'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>100 then raise exception 'بيانات الموازنة غير صحيحة' using errcode='22023'; end if;
 insert into public.finance_budgets(period_id,budget_name,created_by) values(p_period_id,btrim(p_name),(select auth.uid())) returning id into v_budget;
 for v_item in select value from jsonb_array_elements(p_lines) loop
  begin v_account:=(v_item->>'account_id')::uuid; v_center:=nullif(v_item->>'cost_center_id','')::uuid; v_amount:=round((v_item->>'budget_amount')::numeric,2); exception when others then raise exception 'سطر الموازنة غير صحيح' using errcode='22023'; end;
  if v_amount is null or v_amount<0 or not exists(select 1 from public.accounting_accounts where id=v_account and is_active and account_type in ('expense','revenue')) then raise exception 'الموازنة تقبل حسابات الإيرادات والمصروفات الفعالة فقط' using errcode='22023'; end if;
  insert into public.finance_budget_lines(budget_id,account_id,cost_center_id,budget_amount) values(v_budget,v_account,v_center,v_amount);
  v_count:=v_count+1;
 end loop;
 return v_budget;
end $$;

create or replace function private.approve_finance_budget(p_budget_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح باعتماد الموازنة' using errcode='42501'; end if;
 update public.finance_budgets set status='approved',approved_by=(select auth.uid()),approved_at=now()
 where id=p_budget_id and status='draft';
 if not found then raise exception 'الموازنة غير موجودة أو معتمدة بالفعل' using errcode='P0002'; end if;
end $$;

create or replace function private.create_accrual_schedule(p_name text,p_description text,p_debit_account_id uuid,p_credit_account_id uuid,p_monthly_amount numeric,p_start date,p_end date default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإدارة الاستحقاقات' using errcode='42501'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null or p_monthly_amount is null or p_monthly_amount<=0 or p_start is null or (p_end is not null and p_end<p_start) or p_debit_account_id=p_credit_account_id then raise exception 'بيانات الاستحقاق غير صحيحة' using errcode='22023'; end if;
 if not exists(select 1 from public.accounting_accounts where id=p_debit_account_id and is_active) or not exists(select 1 from public.accounting_accounts where id=p_credit_account_id and is_active) then raise exception 'الحساب المحدد غير فعال' using errcode='22023'; end if;
 insert into public.accrual_schedules(schedule_name,description,debit_account_id,credit_account_id,monthly_amount,start_date,end_date,next_run_date,created_by)
 values(btrim(p_name),nullif(btrim(coalesce(p_description,'')),''),p_debit_account_id,p_credit_account_id,p_monthly_amount,p_start,p_end,p_start,(select auth.uid())) returning id into v_id;
 return v_id;
end $$;

create or replace function private.run_accrual_schedule(p_schedule_id uuid,p_run_date date)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_s public.accrual_schedules%rowtype; v_run uuid:=gen_random_uuid(); v_entry uuid:=gen_random_uuid(); v_amount numeric(14,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بترحيل الاستحقاق' using errcode='42501'; end if;
 select * into v_s from public.accrual_schedules where id=p_schedule_id and is_active for update;
 if not found then raise exception 'جدول الاستحقاق غير موجود أو غير نشط' using errcode='P0002'; end if;
 if p_run_date is null or p_run_date<v_s.next_run_date or p_run_date<v_s.start_date or (v_s.end_date is not null and p_run_date>v_s.end_date) then raise exception 'تاريخ الترحيل لا يطابق موعد الاستحقاق' using errcode='22023'; end if;
 if exists(select 1 from public.fiscal_periods where status='closed' and p_run_date between start_date and end_date) then raise exception 'الفترة المحاسبية مقفلة' using errcode='23514'; end if;
 if exists(select 1 from public.accrual_runs where schedule_id=p_schedule_id and run_date=p_run_date) then raise exception 'تم ترحيل هذا الموعد من قبل' using errcode='23505'; end if;
 v_amount:=v_s.monthly_amount;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_run_date,v_s.schedule_name,'accrual_run',v_run,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_s.debit_account_id,v_amount,0,'قيد استحقاق دوري'),(v_entry,v_s.credit_account_id,0,v_amount,'قيد استحقاق دوري');
 insert into public.accrual_runs(id,schedule_id,run_date,amount,journal_entry_id,created_by) values(v_run,p_schedule_id,p_run_date,v_amount,v_entry,(select auth.uid()));
 update public.accrual_schedules set next_run_date=(p_run_date+interval '1 month')::date,is_active=(end_date is null or (p_run_date+interval '1 month')::date<=end_date) where id=p_schedule_id;
 return jsonb_build_object('run_id',v_run,'journal_entry_id',v_entry,'amount',v_amount);
end $$;

create or replace view public.accounting_aging_report as
select 'customer'::text as party_type,s.customer_id as party_id,s.customer_name as party_name,s.invoice_number as document_number,
 s.created_at::date as document_date,(s.created_at::date+30) as due_date,
 greatest(0,s.total-s.amount_paid-s.credit_applied-coalesce(r.returns_total,0))::numeric(14,2) as balance_due,
 greatest(0,current_date-(s.created_at::date+30))::integer as days_overdue
from public.sales s left join (select sale_id,sum(total_amount) returns_total from public.sale_returns group by sale_id) r on r.sale_id=s.id
where s.status='posted' and s.total-s.amount_paid-s.credit_applied-coalesce(r.returns_total,0)>0
union all
select 'supplier'::text,sb.supplier_id,sp.name,sb.bill_number,sb.bill_date,coalesce(sb.due_date,sb.bill_date),
 greatest(0,sb.total_amount-coalesce(p.paid,0)-coalesce(r.returned,0)-coalesce(a.allocated,0))::numeric(14,2),
 greatest(0,current_date-coalesce(sb.due_date,sb.bill_date))::integer
from public.supplier_bills sb join public.suppliers sp on sp.id=sb.supplier_id
left join (select supplier_bill_id,sum(amount) paid from public.supplier_payments group by supplier_bill_id) p on p.supplier_bill_id=sb.id
left join (select sr.supplier_bill_id,sum(sri.line_total) returned from public.supplier_returns sr join public.supplier_return_items sri on sri.supplier_return_id=sr.id group by sr.supplier_bill_id) r on r.supplier_bill_id=sb.id
left join (select supplier_bill_id,sum(amount) allocated from public.supplier_advance_allocations group by supplier_bill_id) a on a.supplier_bill_id=sb.id
where sb.total_amount-coalesce(p.paid,0)-coalesce(r.returned,0)-coalesce(a.allocated,0)>0;

create or replace view public.accounting_cash_book as
select ca.id as cash_account_id,ca.name as cash_account_name,ca.account_kind,ca.currency,
 je.id as journal_entry_id,je.entry_number,je.entry_date,je.description,jel.debit,jel.credit,(jel.debit-jel.credit) as movement,
 sum(jel.debit-jel.credit) over(partition by ca.id order by je.entry_date,je.created_at,jel.id rows unbounded preceding) as running_balance
from public.cash_accounts ca join public.journal_entry_lines jel on jel.account_id=ca.account_id
join public.journal_entries je on je.id=jel.journal_entry_id and je.status='posted';

create or replace view public.finance_budget_vs_actual as
select b.id as budget_id,b.budget_name,b.status,p.period_code,p.start_date,p.end_date,
 a.id as account_id,a.code as account_code,a.name as account_name,a.account_type,
 bl.cost_center_id,coalesce(bl.budget_amount,0) as budget_amount,
 coalesce(sum(case when a.account_type='expense' then jel.debit-jel.credit else jel.credit-jel.debit end),0)::numeric(14,2) as actual_amount,
 (coalesce(bl.budget_amount,0)-coalesce(sum(case when a.account_type='expense' then jel.debit-jel.credit else jel.credit-jel.debit end),0))::numeric(14,2) as variance
from public.finance_budgets b join public.fiscal_periods p on p.id=b.period_id
join public.finance_budget_lines bl on bl.budget_id=b.id
join public.accounting_accounts a on a.id=bl.account_id
left join public.journal_entry_lines jel on jel.account_id=a.id and (bl.cost_center_id is null or jel.cost_center_id=bl.cost_center_id)
left join public.journal_entries je on je.id=jel.journal_entry_id and je.status='posted' and je.entry_date between p.start_date and p.end_date
group by b.id,b.budget_name,b.status,p.period_code,p.start_date,p.end_date,a.id,a.code,a.name,a.account_type,bl.cost_center_id,bl.budget_amount;

grant select on public.accounting_aging_report,public.accounting_cash_book,public.finance_budget_vs_actual to authenticated;

create or replace function public.open_cash_session(uuid,numeric,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.open_cash_session($1,$2,$3) $$;
create or replace function public.close_cash_session(uuid,numeric,text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.close_cash_session($1,$2,$3) $$;
create or replace function public.create_cash_handover(uuid,uuid,numeric,text default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_cash_handover($1,$2,$3,$4) $$;
create or replace function public.respond_cash_handover(uuid,boolean) returns void language sql security invoker set search_path='' as $$ select private.respond_cash_handover($1,$2) $$;
create or replace function public.set_petty_cash_limit(numeric) returns void language sql security invoker set search_path='' as $$ select private.set_petty_cash_limit($1) $$;
create or replace function public.create_petty_cash(date,text,uuid,uuid,numeric,text,text) returns jsonb language sql security invoker set search_path='' as $$ select private.create_petty_cash($1,$2,$3,$4,$5,$6,$7) $$;
create or replace function public.reverse_journal_entry(uuid,text) returns jsonb language sql security invoker set search_path='' as $$ select private.reverse_journal_entry($1,$2) $$;
create or replace function public.create_finance_budget(uuid,text,jsonb) returns uuid language sql security invoker set search_path='' as $$ select private.create_finance_budget($1,$2,$3) $$;
create or replace function public.approve_finance_budget(uuid) returns void language sql security invoker set search_path='' as $$ select private.approve_finance_budget($1) $$;
create or replace function public.create_accrual_schedule(text,text,uuid,uuid,numeric,date,date default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_accrual_schedule($1,$2,$3,$4,$5,$6,$7) $$;
create or replace function public.run_accrual_schedule(uuid,date) returns jsonb language sql security invoker set search_path='' as $$ select private.run_accrual_schedule($1,$2) $$;

do $$ declare sig text; begin
 for sig in select unnest(array[
 'public.open_cash_session(uuid,numeric,text)','public.close_cash_session(uuid,numeric,text)','public.create_cash_handover(uuid,uuid,numeric,text)',
 'public.respond_cash_handover(uuid,boolean)','public.set_petty_cash_limit(numeric)','public.create_petty_cash(date,text,uuid,uuid,numeric,text,text)',
 'public.reverse_journal_entry(uuid,text)','public.create_finance_budget(uuid,text,jsonb)','public.approve_finance_budget(uuid)',
 'public.create_accrual_schedule(text,text,uuid,uuid,numeric,date,date)','public.run_accrual_schedule(uuid,date)'
 ]) loop execute format('revoke all on function %s from public,anon',sig); execute format('grant execute on function %s to authenticated',sig); end loop;
end $$;

