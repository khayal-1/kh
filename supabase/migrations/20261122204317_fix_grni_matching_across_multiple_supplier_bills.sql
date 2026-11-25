-- Source recovered from the applied production migration ledger.
create or replace function private.post_supplier_bill_journal()
returns trigger language plpgsql security definer set search_path=''
as $$
declare ap uuid;grni uuid;inv uuid;j uuid;received numeric(14,2);billed numeric(14,2);clear_grni numeric(14,2);direct_amount numeric(14,2);
begin
 select id into ap from public.accounting_accounts where code='2010' and is_active;
 select id into grni from public.accounting_accounts where code='2060' and is_active;
 select id into inv from public.accounting_accounts where code='1200' and is_active;
 if new.purchase_order_id is not null then
  select coalesce(sum(pri.quantity*pri.unit_cost),0) into received
  from public.purchase_receipt_items pri join public.purchase_receipts pr on pr.id=pri.receipt_id
  where pr.purchase_order_id=new.purchase_order_id;
  select coalesce(sum(b.total_amount),0) into billed from public.supplier_bills b
  where b.purchase_order_id=new.purchase_order_id and b.id<>new.id
   and exists(select 1 from public.journal_entries je where je.source_type='supplier_bill' and je.source_id=b.id);
  clear_grni:=least(new.total_amount,greatest(0,received-billed));direct_amount:=new.total_amount-clear_grni;
 else clear_grni:=0;direct_amount:=new.total_amount;end if;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
 values(new.bill_date,'فاتورة مورد رقم '||new.bill_number,'supplier_bill',new.id,new.created_by) returning id into j;
 if clear_grni>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,grni,clear_grni,0,'تسوية بضاعة مستلمة غير مفوترة');end if;
 if direct_amount>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,inv,direct_amount,0,'مشتريات مباشرة أو فرق فاتورة');end if;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,ap,0,new.total_amount,'إثبات مستحق المورد');
 return new;
end $$;
