-- Source recovered from the applied production migration ledger.
drop function if exists public.record_supplier_payment(uuid,numeric,text,text,text);
create or replace function public.record_supplier_payment(
 p_supplier_bill_id uuid,p_amount numeric,p_method text,p_reference text default null,p_notes text default null,p_cash_account_id uuid default null
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
 v_bill public.supplier_bills%rowtype; v_paid numeric(14,2); v_credits numeric(14,2); v_advance_allocated numeric(14,2);
 v_balance numeric(14,2); v_payment public.supplier_payments%rowtype; v_entry uuid; v_payable uuid; v_cash uuid;
begin
 if (select auth.uid()) is null or not public.can_manage_purchasing() then raise exception using errcode='42501',message='غير مصرح بتسجيل مدفوعات الموردين'; end if;
 if p_amount is null or p_amount<=0 or p_method not in ('cash','bank_transfer','instapay','cheque','other') or p_cash_account_id is null then
  raise exception using errcode='22023',message='قيمة الدفعة وطريقتها وحساب الخزينة أو البنك مطلوبة';
 end if;
 select * into v_bill from public.supplier_bills where id=p_supplier_bill_id for update;
 if not found then raise exception using errcode='P0002',message='فاتورة المورد غير موجودة'; end if;
 select coalesce(sum(amount),0) into v_paid from public.supplier_payments where supplier_bill_id=v_bill.id;
 select coalesce(sum(sri.line_total),0) into v_credits from public.supplier_return_items sri join public.supplier_returns sr on sr.id=sri.supplier_return_id where sr.supplier_bill_id=v_bill.id;
 select coalesce(sum(amount),0) into v_advance_allocated from public.supplier_advance_allocations where supplier_bill_id=v_bill.id;
 v_balance:=v_bill.total_amount-v_paid-v_credits-v_advance_allocated;
 if round(p_amount,2)>v_balance then raise exception using errcode='23514',message='قيمة الدفعة أكبر من الرصيد المستحق بعد خصم المرتجعات والسلف: '||v_balance; end if;
 select id into v_payable from public.accounting_accounts where code='2010' and is_active;
 select account_id into v_cash from public.cash_accounts where id=p_cash_account_id and is_active;
 if v_payable is null or v_cash is null then raise exception using errcode='22023',message='حساب الموردين أو حساب الخزينة/البنك غير جاهز'; end if;
 insert into public.supplier_payments(supplier_bill_id,supplier_id,amount,method,reference,notes,created_by)
 values(v_bill.id,v_bill.supplier_id,round(p_amount,2),p_method,nullif(btrim(coalesce(p_reference,'')),''),nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()))
 returning * into v_payment;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
 values(current_date,'سداد فاتورة مورد '||v_bill.bill_number,'supplier_payment',v_payment.id,(select auth.uid())) returning id into v_entry;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
 values(v_entry,v_payable,round(p_amount,2),0,'تخفيض مستحق المورد'),(v_entry,v_cash,0,round(p_amount,2),'سداد من الحساب المالي المختار');
 update public.supplier_payments set journal_entry_id=v_entry where id=v_payment.id;
 return jsonb_build_object('payment_number',v_payment.payment_number,'amount',v_payment.amount,'balance_due',v_balance-v_payment.amount,'journal_entry_id',v_entry);
end;
$function$;
revoke all on function public.record_supplier_payment(uuid,numeric,text,text,text,uuid) from public,anon;
grant execute on function public.record_supplier_payment(uuid,numeric,text,text,text,uuid) to authenticated;

