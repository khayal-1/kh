-- Source recovered from the applied production migration ledger.
create or replace function private.record_supplier_advance(
 p_supplier_id uuid,p_date date,p_amount numeric,p_cash_account_id uuid,p_method text,p_reference text default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_id uuid:=gen_random_uuid(); v_entry uuid:=gen_random_uuid(); v_cash uuid; v_kind text; v_advance_account uuid; v_amount numeric(14,2):=round(p_amount,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسجيل سلف الموردين' using errcode='42501'; end if;
 if p_supplier_id is null or p_date is null or v_amount is null or v_amount<=0 or p_cash_account_id is null
  or coalesce(p_method,'') not in ('cash','bank_transfer','instapay','cheque','other') then raise exception 'بيانات سلفة المورد غير صحيحة' using errcode='22023'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and is_active) then raise exception 'المورد غير موجود أو غير نشط' using errcode='22023'; end if;
 select account_id,account_kind into v_cash,v_kind from public.cash_accounts where id=p_cash_account_id and is_active;
 select id into v_advance_account from public.accounting_accounts where code='1300' and is_active;
 if v_cash is null or v_advance_account is null then raise exception 'حساب الخزينة أو حساب سلف الموردين غير جاهز' using errcode='22023'; end if;
 if (p_method='cash' and v_kind<>'cash') or (p_method in ('bank_transfer','instapay') and v_kind<>'bank') then raise exception 'نوع الحساب المالي لا يتوافق مع طريقة الدفع' using errcode='22023'; end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by)
 values(v_entry,p_date,'سلفة مورد','supplier_advance',v_id,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
 values(v_entry,v_advance_account,v_amount,0,'سلفة مورد'),(v_entry,v_cash,0,v_amount,'صرف سلفة من الخزينة / البنك');
 insert into public.supplier_advances(id,supplier_id,advance_date,amount,cash_account_id,payment_method,reference_number,notes,journal_entry_id,created_by)
 values(v_id,p_supplier_id,p_date,v_amount,p_cash_account_id,p_method,nullif(btrim(coalesce(p_reference,'')),''),nullif(btrim(coalesce(p_notes,'')),''),v_entry,(select auth.uid()));
 return jsonb_build_object('advance_id',v_id,'journal_entry_id',v_entry,'amount',v_amount,'remaining',v_amount);
end $$;

create or replace function private.allocate_supplier_advance(p_advance_id uuid,p_bill_id uuid,p_amount numeric)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_a public.supplier_advances%rowtype; v_b public.supplier_bills%rowtype;
 v_amount numeric(14,2):=round(p_amount,2); v_adv uuid; v_ap uuid; v_entry uuid:=gen_random_uuid(); v_alloc uuid:=gen_random_uuid();
 v_paid numeric(14,2); v_credits numeric(14,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسوية سلفة المورد' using errcode='42501'; end if;
 select * into v_a from public.supplier_advances where id=p_advance_id for update; if not found then raise exception 'سلفة المورد غير موجودة' using errcode='P0002'; end if;
 select * into v_b from public.supplier_bills where id=p_bill_id and supplier_id=v_a.supplier_id for update; if not found then raise exception 'فاتورة المورد لا تخص المورد صاحب السلفة' using errcode='23503'; end if;
 if v_amount is null or v_amount<=0 or v_amount>v_a.amount-v_a.allocated_amount then raise exception 'المبلغ يتجاوز رصيد السلفة المتاح' using errcode='23514'; end if;
 select coalesce(sum(amount),0) into v_paid from public.supplier_payments where supplier_bill_id=p_bill_id;
 select coalesce(sum(sri.line_total),0) into v_credits from public.supplier_return_items sri join public.supplier_returns sr on sr.id=sri.supplier_return_id where sr.supplier_bill_id=p_bill_id;
 if v_amount>v_b.total_amount-v_paid-v_credits-coalesce((select sum(amount) from public.supplier_advance_allocations where supplier_bill_id=p_bill_id),0) then raise exception 'المبلغ يتجاوز مستحق فاتورة المورد' using errcode='23514'; end if;
 select id into v_adv from public.accounting_accounts where code='1300' and is_active;
 select id into v_ap from public.accounting_accounts where code='2010' and is_active;
 if v_adv is null or v_ap is null then raise exception 'حساب سلف الموردين أو حساب الموردين غير مهيأ' using errcode='22023'; end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by)
 values(v_entry,current_date,'تسوية سلفة مورد على فاتورة '||v_b.bill_number,'supplier_advance_allocation',v_alloc,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
 values(v_entry,v_ap,v_amount,0,'تخفيض مستحق المورد'),(v_entry,v_adv,0,v_amount,'استخدام سلفة المورد');
 insert into public.supplier_advance_allocations(id,advance_id,supplier_bill_id,amount,journal_entry_id,created_by)
 values(v_alloc,p_advance_id,p_bill_id,v_amount,v_entry,(select auth.uid()));
 update public.supplier_advances set allocated_amount=allocated_amount+v_amount where id=p_advance_id;
 return jsonb_build_object('allocation_id',v_alloc,'amount',v_amount,'advance_remaining',v_a.amount-v_a.allocated_amount-v_amount);
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
 return jsonb_build_object('reversal_id',v_link,'reversal_journal_entry_id',v_reversal,'original_entry_number',v_original.entry_number);
end $$;

