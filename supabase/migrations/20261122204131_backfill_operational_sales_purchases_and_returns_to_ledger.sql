-- Source recovered from the applied production migration ledger.
update public.sale_items si set unit_cost=ic.unit_cost from public.motorcycle_inventory_costs ic where ic.motorcycle_id=si.motorcycle_id and si.unit_cost is null;

do $$
declare r record;j uuid;ar uuid;rev uuid;inv uuid;cogs uuid;grni uuid;ap uuid;retacct uuid;cash uuid;cred uuid;v numeric(14,2);received_total numeric(14,2);billed_before numeric(14,2);grni_used numeric(14,2);direct_value numeric(14,2);
begin
 select id into ar from public.accounting_accounts where code='1100';select id into rev from public.accounting_accounts where code='4010';
 select id into inv from public.accounting_accounts where code='1200';select id into cogs from public.accounting_accounts where code='5000';
 select id into grni from public.accounting_accounts where code='2060';select id into ap from public.accounting_accounts where code='2010';
 select id into retacct from public.accounting_accounts where code='4020';select id into cash from public.accounting_accounts where code='1030';select id into cred from public.accounting_accounts where code='2070';

 for r in select * from public.sales s where s.status='posted' and not exists(select 1 from public.journal_entries je where je.source_type='sale_invoice' and je.source_id=s.id) loop
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.created_at::date,'فاتورة بيع رقم '||r.invoice_number,'sale_invoice',r.id,r.created_by) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,ar,r.total,0,'إثبات ذمم العميل'),(j,rev,0,r.total,'إيراد بيع دراجات');
 end loop;

 for r in select * from public.sale_items si where si.unit_cost is not null and si.unit_cost>0 and not exists(select 1 from public.journal_entries je where je.source_type='sale_cogs' and je.source_id=si.id) loop
  v:=round(r.unit_cost*r.quantity,2);
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
  select s.created_at::date,'تكلفة بضاعة فاتورة '||s.invoice_number,'sale_cogs',r.id,s.created_by from public.sales s where s.id=r.sale_id returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,cogs,v,0,'تكلفة البضاعة المباعة'),(j,inv,0,v,'تخفيض قيمة المخزون');
 end loop;
 update public.sales s set costing_status=case when exists(select 1 from public.sale_items si where si.sale_id=s.id and si.unit_cost is null) then 'incomplete' else 'complete' end;

 for r in select * from public.payments p where p.journal_entry_id is null loop
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.paid_at::date,'دفعة بيع تاريخية غير موزعة على خزينة/بنك','sale_payment',r.id,r.received_by) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,cash,r.amount,0,'متحصلات تاريخية غير موزعة'),(j,ar,0,r.amount,'تخفيض رصيد العميل');
  update public.payments set journal_entry_id=j where id=r.id;
 end loop;

 for r in select pri.*,pr.received_at,pr.received_by from public.purchase_receipt_items pri join public.purchase_receipts pr on pr.id=pri.receipt_id
  where not exists(select 1 from public.journal_entries je where je.source_type='purchase_receipt' and je.source_id=pri.id) loop
  v:=round(r.quantity*r.unit_cost,2);
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.received_at::date,'استلام بضاعة تاريخي','purchase_receipt',r.id,r.received_by) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,inv,v,0,'إضافة مخزون مستلم'),(j,grni,0,v,'بضاعة مستلمة غير مفوترة');
 end loop;

 for r in select * from public.supplier_bills b where not exists(select 1 from public.journal_entries je where je.source_type='supplier_bill' and je.source_id=b.id) order by b.bill_date,b.id loop
  if r.purchase_order_id is not null then
   select coalesce(sum(pri.quantity*pri.unit_cost),0) into received_total from public.purchase_receipt_items pri join public.purchase_receipts pr on pr.id=pri.receipt_id where pr.purchase_order_id=r.purchase_order_id;
   select coalesce(sum(b2.total_amount),0) into billed_before from public.supplier_bills b2 where b2.purchase_order_id=r.purchase_order_id and (b2.bill_date,b2.id)<(r.bill_date,r.id);
   grni_used:=least(r.total_amount,greatest(0,received_total-billed_before));direct_value:=r.total_amount-grni_used;
  else grni_used:=0;direct_value:=r.total_amount;end if;
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.bill_date,'فاتورة مورد رقم '||r.bill_number,'supplier_bill',r.id,r.created_by) returning id into j;
  if grni_used>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,grni,grni_used,0,'تسوية استلام بضاعة');end if;
  if direct_value>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,inv,direct_value,0,'مشتريات مباشرة / فرق فاتورة');end if;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,ap,0,r.total_amount,'إثبات مستحق المورد');
 end loop;

 for r in select sri.*,sr.created_at,sr.created_by,sr.return_number from public.supplier_return_items sri join public.supplier_returns sr on sr.id=sri.supplier_return_id
  where not exists(select 1 from public.journal_entries je where je.source_type='supplier_return' and je.source_id=sri.id) loop
  v:=coalesce(r.line_total,r.quantity*r.unit_cost);
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.created_at::date,'مرتجع مورد رقم '||r.return_number,'supplier_return',r.id,r.created_by) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,ap,v,0,'تخفيض مستحق المورد'),(j,inv,0,v,'إخراج بضاعة مرتجعة');
 end loop;

 for r in select * from public.sale_returns sr where not exists(select 1 from public.journal_entries je where je.source_type='sale_return' and je.source_id=sr.id) loop
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.created_at::date,'مرتجع مبيعات رقم '||r.return_number,'sale_return',r.id,r.created_by) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,retacct,r.total_amount,0,'مردودات مبيعات'),(j,ar,0,r.total_amount,'تخفيض ذمم العميل');
 end loop;

 for r in select sri.*,sr.created_at,sr.created_by from public.sale_return_items sri join public.sale_returns sr on sr.id=sri.sale_return_id
  where sri.disposition='restock' and not exists(select 1 from public.journal_entries je where je.source_type='sale_return_cogs' and je.source_id=sri.id) loop
  select unit_cost into v from public.sale_items where id=r.sale_item_id;
  if v is not null and v>0 then
   v:=round(v*r.quantity,2);
   insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.created_at::date,'عكس تكلفة مرتجع','sale_return_cogs',r.id,r.created_by) returning id into j;
   insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,inv,v,0,'إعادة مخزون مرتجع'),(j,cogs,0,v,'عكس تكلفة البضاعة المرتجعة');
  end if;
 end loop;

 for r in select * from public.customer_credit_transactions ct where not exists(select 1 from public.journal_entries je where je.source_type='customer_credit' and je.source_id=ct.id) loop
  v:=abs(r.amount);
  if r.transaction_type='return_credit' then
   insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
   values(r.created_at::date,'رصيد دائن تاريخي للعميل','customer_credit',r.id,coalesce(r.created_by,(select created_by from public.sales where id=r.sale_id limit 1))) returning id into j;
   insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,ar,v,0,'رصيد العميل'),(j,cred,0,v,'التزام رصيد العميل');
  elsif r.transaction_type='invoice_credit_application' then
   insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
   values(r.created_at::date,'استخدام رصيد عميل تاريخي','customer_credit',r.id,coalesce(r.created_by,(select created_by from public.sales where id=r.sale_id limit 1))) returning id into j;
   insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,cred,v,0,'تخفيض رصيد العميل'),(j,ar,0,v,'تخفيض الذمم');
  elsif r.transaction_type='cash_refund' then
   insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
   values(r.created_at::date,'رد رصيد عميل تاريخي غير موزع','customer_credit',r.id,coalesce(r.created_by,(select created_by from public.sales where id=r.sale_id limit 1))) returning id into j;
   insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,cred,v,0,'تخفيض التزام رصيد العميل'),(j,cash,0,v,'رد نقدي تاريخي غير موزع');
  end if;
 end loop;
end $$;

