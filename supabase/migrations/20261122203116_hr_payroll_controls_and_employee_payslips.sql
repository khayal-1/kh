-- Source recovered from the applied production migration ledger.
alter table public.employees drop constraint if exists employees_check;
alter table public.employees add constraint employees_termination_date_check
check((employment_status='terminated' and termination_date is not null) or (employment_status<>'terminated' and termination_date is null));

alter table public.sales_commissions
 add constraint sales_commissions_payroll_item_fk foreign key(payroll_item_id) references public.payroll_items(id) on delete restrict;

drop policy if exists payroll_runs_hr_read on public.payroll_runs;
create policy payroll_runs_hr_read on public.payroll_runs for select to authenticated using(
 public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('finance_manage')
 or exists(select 1 from public.payroll_items pi join public.employees e on e.id=pi.employee_id where pi.payroll_run_id=payroll_runs.id and e.auth_user_id=(select auth.uid()))
);

create or replace function private.guard_payroll_period()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if not exists(select 1 from public.fiscal_periods where id=new.period_id and status='open' and new.payroll_date between start_date and end_date) then
  raise exception 'تاريخ كشف الرواتب يجب أن يقع داخل فترة محاسبية مفتوحة' using errcode='23514';
 end if;
 return new;
end $$;
drop trigger if exists payroll_period_guard on public.payroll_runs;
create trigger payroll_period_guard before insert or update of period_id,payroll_date on public.payroll_runs
for each row execute function private.guard_payroll_period();

create or replace view public.employee_payslips
with (security_invoker=true) as
select e.id as employee_id,e.employee_code,e.full_name,pr.id as payroll_run_id,pr.payroll_number,pr.payroll_name,pr.payroll_date,
 pr.status as payroll_status,pi.base_salary,pi.allowances,pi.commission,pi.employee_insurance,pi.tax_deduction,
 pi.other_deductions,pi.advance_deduction,pi.employer_insurance,pi.net_pay
from public.payroll_items pi join public.employees e on e.id=pi.employee_id
join public.payroll_runs pr on pr.id=pi.payroll_run_id;
grant select on public.employee_payslips to authenticated;
revoke all on public.employee_payslips from anon;

