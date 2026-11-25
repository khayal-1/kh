create or replace function private.create_fixed_asset(
 p_name text,p_description text,p_asset_account_id uuid,p_accum_account_id uuid,p_expense_account_id uuid,
 p_acquisition_date date,p_depreciation_start date,p_cost numeric,p_salvage numeric,p_life_months integer,p_cash_account_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
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
 return jsonb_build_object('fixed_asset_id',v_id,'journal_entry_id',v_entry);
end $$;
create or replace function private.generate_recurring_journal(p_template_id uuid,p_run_date date)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_template public.recurring_journal_templates%rowtype; v_run uuid:=gen_random_uuid(); v_entry uuid:=gen_random_uuid(); v_next date; v_line record;
begin
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
 return jsonb_build_object('run_id',v_run,'journal_entry_id',v_entry,'next_run_date',v_next);
end $$;
