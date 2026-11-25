-- Source recovered from the applied production migration ledger.
alter table public.payroll_runs drop constraint if exists payroll_runs_status_check;
alter table public.payroll_runs add constraint payroll_runs_status_check check(status in ('draft','posted','cancelled'));
alter table public.payroll_runs drop constraint if exists payroll_runs_check;
alter table public.payroll_runs add constraint payroll_runs_state_check check(
 (status='draft' and journal_entry_id is null and posted_by is null and posted_at is null)
 or (status='posted' and journal_entry_id is not null and posted_by is not null and posted_at is not null)
 or (status='cancelled' and journal_entry_id is null and posted_by is not null and posted_at is not null)
);
create unique index if not exists one_active_payroll_per_period on public.payroll_runs(period_id) where status<>'cancelled';

create or replace function private.create_payroll_run(p_period_id uuid,p_name text,p_date date,p_items jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_run uuid;v_item jsonb;v_employee uuid;v_base numeric(14,2);v_allow numeric(14,2);v_comm numeric(14,2);v_emp_ins numeric(14,2);v_tax numeric(14,2);v_other numeric(14,2);v_advance numeric(14,2);v_employer numeric(14,2);v_net numeric(14,2);v_period public.fiscal_periods%rowtype;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإعداد الرواتب' using errcode='42501'; end if;
 select * into v_period from public.fiscal_periods where id=p_period_id and status='open';
 if not found or p_date is null or p_date not between v_period.start_date and v_period.end_date or nullif(btrim(coalesce(p_name,'')),'') is null or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>200 then raise exception 'بيانات كشف الرواتب أو الفترة غير صحيحة' using errcode='22023'; end if;
 if exists(select 1 from public.payroll_runs where period_id=p_period_id and status<>'cancelled') then raise exception 'يوجد كشف رواتب قائم لهذه الفترة' using errcode='23505'; end if;
 insert into public.payroll_runs(period_id,payroll_name,payroll_date,created_by) values(p_period_id,btrim(p_name),p_date,(select auth.uid())) returning id into v_run;
 for v_item in select value from jsonb_array_elements(p_items) loop
  begin
   v_employee:=(v_item->>'employee_id')::uuid;v_base:=round(coalesce((v_item->>'base_salary')::numeric,0),2);v_allow:=round(coalesce((v_item->>'allowances')::numeric,0),2);
   v_emp_ins:=round(coalesce((v_item->>'employee_insurance')::numeric,0),2);v_tax:=round(coalesce((v_item->>'tax_deduction')::numeric,0),2);
   v_other:=round(coalesce((v_item->>'other_deductions')::numeric,0),2);v_advance:=round(coalesce((v_item->>'advance_deduction')::numeric,0),2);v_employer:=round(coalesce((v_item->>'employer_insurance')::numeric,0),2);
  exception when others then raise exception 'بيانات بند راتب غير صحيحة' using errcode='22023'; end;
  if not exists(select 1 from public.employees where id=v_employee and employment_status='active') or least(v_base,v_allow,v_emp_ins,v_tax,v_other,v_advance,v_employer)<0 then raise exception 'الموظف غير نشط أو توجد قيمة راتب سالبة' using errcode='22023'; end if;
  perform 1 from public.sales_commissions sc join public.sales s on s.id=sc.sale_id
   where sc.employee_id=v_employee and sc.status='pending' and s.created_at::date between v_period.start_date and v_period.end_date for update of sc;
  select coalesce(sum(sc.amount),0) into v_comm from public.sales_commissions sc join public.sales s on s.id=sc.sale_id
   where sc.employee_id=v_employee and sc.status='pending' and s.created_at::date between v_period.start_date and v_period.end_date;
  v_net:=v_base+v_allow+v_comm-v_emp_ins-v_tax-v_other-v_advance;
  if v_net<0 then raise exception 'استقطاعات الموظف تتجاوز مستحقاته' using errcode='23514'; end if;
  insert into public.payroll_items(payroll_run_id,employee_id,base_salary,allowances,commission,employee_insurance,tax_deduction,other_deductions,advance_deduction,employer_insurance,net_pay)
  values(v_run,v_employee,v_base,v_allow,v_comm,v_emp_ins,v_tax,v_other,v_advance,v_employer,v_net);
 end loop;
 return v_run;
end $$;

create or replace function private.post_payroll_run(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_run public.payroll_runs%rowtype;v_item public.payroll_items%rowtype;v_entry uuid:=gen_random_uuid();
 v_gross numeric(14,2);v_employer numeric(14,2);v_emp_ins numeric(14,2);v_tax numeric(14,2);v_other numeric(14,2);v_adv numeric(14,2);v_net numeric(14,2);
 v_wages uuid;v_ins_exp uuid;v_salary_payable uuid;v_ins_payable uuid;v_tax_payable uuid;v_other_payable uuid;v_adv_account uuid;
 v_advance public.employee_advances%rowtype;v_remaining numeric(14,2);v_apply numeric(14,2);v_period public.fiscal_periods%rowtype;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بترحيل الرواتب' using errcode='42501'; end if;
 select * into v_run from public.payroll_runs where id=p_run_id for update;if not found or v_run.status<>'draft' then raise exception 'كشف الرواتب غير موجود أو مرحل بالفعل' using errcode='P0002';end if;
 select * into v_period from public.fiscal_periods where id=v_run.period_id and status='open';if not found then raise exception 'الفترة المحاسبية مقفلة' using errcode='23514';end if;
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
  update public.sales_commissions sc set status='included',payroll_item_id=v_item.id
  from public.sales s where s.id=sc.sale_id and sc.employee_id=v_item.employee_id and sc.status='pending'
   and s.created_at::date between v_period.start_date and v_period.end_date;
 end loop;
 update public.payroll_runs set status='posted',journal_entry_id=v_entry,posted_by=(select auth.uid()),posted_at=now(),total_gross=v_gross+v_employer,total_net=v_net where id=p_run_id;
 return jsonb_build_object('payroll_run_id',p_run_id,'journal_entry_id',v_entry,'gross',v_gross+v_employer,'net',v_net);
end $$;

create or replace function private.cancel_payroll_run(p_run_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإلغاء كشف الرواتب' using errcode='42501'; end if;
 delete from public.payroll_items where payroll_run_id=p_run_id and exists(select 1 from public.payroll_runs where id=p_run_id and status='draft');
 update public.payroll_runs set status='cancelled',posted_by=(select auth.uid()),posted_at=now() where id=p_run_id and status='draft';
 if not found then raise exception 'كشف الرواتب غير موجود أو تم ترحيله بالفعل' using errcode='P0002';end if;
end $$;
create or replace function public.cancel_payroll_run(uuid) returns void language sql security invoker set search_path='' as $$ select private.cancel_payroll_run($1) $$;
revoke all on function public.cancel_payroll_run(uuid) from public,anon;
grant execute on function public.cancel_payroll_run(uuid) to authenticated;
revoke all on function private.guard_payroll_period() from public,anon,authenticated;
revoke all on function private.guard_journal_period() from public,anon,authenticated;

