-- Source recovered from the applied production migration ledger.
insert into public.accounting_accounts(code,name,account_type,parent_code,is_system) values
('1030','متحصلات غير موزعة على خزينة/بنك','asset','1000',true),('2060','بضائع مستلمة غير مفوترة','liability','2000',true),
('2070','أرصدة العملاء الدائنة','liability','2000',true),('4020','مردودات ومسموحات المبيعات','expense','4000',true)
on conflict(code) do nothing;
alter table public.payments add column if not exists cash_account_id uuid references public.cash_accounts(id) on delete restrict;
alter table public.payments add column if not exists journal_entry_id uuid unique references public.journal_entries(id) on delete restrict;
alter table public.customer_credit_transactions add column if not exists cash_account_id uuid references public.cash_accounts(id) on delete restrict;
alter table public.sale_items add column if not exists unit_cost numeric(14,2) check(unit_cost is null or unit_cost>=0);
alter table public.sales add column if not exists costing_status text not null default 'incomplete' check(costing_status in ('complete','incomplete'));

create or replace function private.post_sale_invoice_journal() returns trigger language plpgsql security definer set search_path='' as $$
declare a uuid;r uuid;j uuid;
begin if new.status<>'posted' then return new;end if;
 select id into a from public.accounting_accounts where code='1100' and is_active;select id into r from public.accounting_accounts where code='4010' and is_active;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(new.created_at::date,'فاتورة بيع رقم '||new.invoice_number,'sale_invoice',new.id,new.created_by) returning id into j;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,a,new.total,0,'إثبات ذمم العميل'),(j,r,0,new.total,'إيراد بيع دراجات');return new;end $$;

create or replace function private.capture_sale_item_cost() returns trigger language plpgsql security definer set search_path='' as $$
begin if new.unit_cost is null then select unit_cost into new.unit_cost from public.motorcycle_inventory_costs where motorcycle_id=new.motorcycle_id;end if;return new;end $$;

create or replace function private.post_sale_item_cogs() returns trigger language plpgsql security definer set search_path='' as $$
declare c uuid;i uuid;j uuid;v numeric(14,2);
begin if new.unit_cost is not null and new.unit_cost>0 then
 select id into c from public.accounting_accounts where code='5000' and is_active;select id into i from public.accounting_accounts where code='1200' and is_active;v:=round(new.unit_cost*new.quantity,2);
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) select s.created_at::date,'تكلفة بضاعة فاتورة '||s.invoice_number,'sale_cogs',new.id,s.created_by from public.sales s where s.id=new.sale_id returning id into j;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,c,v,0,'تكلفة البضاعة المباعة'),(j,i,0,v,'تخفيض قيمة المخزون');end if;
 update public.sales s set costing_status=case when exists(select 1 from public.sale_items si where si.sale_id=new.sale_id and si.unit_cost is null) then 'incomplete' else 'complete' end where s.id=new.sale_id;return new;end $$;

create or replace function private.post_sale_payment_journal() returns trigger language plpgsql security definer set search_path='' as $$
declare cash_id uuid;ar_id uuid;j uuid;
begin select id into cash_id from public.accounting_accounts where code='1030' and is_active;select id into ar_id from public.accounting_accounts where code='1100' and is_active;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(new.paid_at::date,'تحصيل دفعة بيع غير موزعة على خزينة/بنك','sale_payment',new.id,new.received_by) returning id into j;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,cash_id,new.amount,0,'متحصلات بانتظار تحديد الخزينة أو البنك'),(j,ar_id,0,new.amount,'تخفيض رصيد العميل');
 update public.payments set journal_entry_id=j where id=new.id;return new;end $$;

create or replace function private.post_purchase_receipt_journal() returns trigger language plpgsql security definer set search_path='' as $$
declare inv uuid;grni uuid;j uuid;v numeric(14,2);d date;u uuid;
begin select id into inv from public.accounting_accounts where code='1200' and is_active;select id into grni from public.accounting_accounts where code='2060' and is_active;
 select received_at::date,received_by into d,u from public.purchase_receipts where id=new.receipt_id;v:=round(new.quantity*new.unit_cost,2);
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(d,'استلام بضاعة من أمر شراء','purchase_receipt',new.id,u) returning id into j;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,inv,v,0,'إضافة مخزون مستلم'),(j,grni,0,v,'بضاعة مستلمة غير مفوترة');return new;end $$;

create or replace function private.post_supplier_bill_journal() returns trigger language plpgsql security definer set search_path='' as $$
declare ap uuid;grni uuid;inv uuid;j uuid;received numeric(14,2);clear_grni numeric(14,2);direct_amount numeric(14,2);
begin select id into ap from public.accounting_accounts where code='2010' and is_active;select id into grni from public.accounting_accounts where code='2060' and is_active;select id into inv from public.accounting_accounts where code='1200' and is_active;
 if new.purchase_order_id is not null then select coalesce(sum(pri.quantity*pri.unit_cost),0) into received from public.purchase_receipt_items pri join public.purchase_receipts pr on pr.id=pri.receipt_id where pr.purchase_order_id=new.purchase_order_id;clear_grni:=least(new.total_amount,received);direct_amount:=new.total_amount-clear_grni;
 else clear_grni:=0;direct_amount:=new.total_amount;end if;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(new.bill_date,'فاتورة مورد رقم '||new.bill_number,'supplier_bill',new.id,new.created_by) returning id into j;
 if clear_grni>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,grni,clear_grni,0,'تسوية بضاعة مستلمة غير مفوترة');end if;
 if direct_amount>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,inv,direct_amount,0,'مشتريات مباشرة غير مرتبطة باستلام');end if;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,ap,0,new.total_amount,'إثبات مستحق المورد');return new;end $$;

create or replace function private.post_supplier_return_journal() returns trigger language plpgsql security definer set search_path='' as $$
declare ap uuid;inv uuid;j uuid;r public.supplier_returns%rowtype;v numeric(14,2);
begin select * into r from public.supplier_returns where id=new.supplier_return_id;select id into ap from public.accounting_accounts where code='2010' and is_active;select id into inv from public.accounting_accounts where code='1200' and is_active;v:=coalesce(new.line_total,new.quantity*new.unit_cost);
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.created_at::date,'مرتجع مورد رقم '||r.return_number,'supplier_return',new.id,r.created_by) returning id into j;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,ap,v,0,'تخفيض مستحق المورد'),(j,inv,0,v,'إخراج بضاعة مرتجعة');return new;end $$;

create or replace function private.post_sale_return_journal() returns trigger language plpgsql security definer set search_path='' as $$
declare ar uuid;retacct uuid;j uuid;
begin select id into ar from public.accounting_accounts where code='1100' and is_active;select id into retacct from public.accounting_accounts where code='4020' and is_active;
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(new.created_at::date,'مرتجع مبيعات رقم '||new.return_number,'sale_return',new.id,new.created_by) returning id into j;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,retacct,new.total_amount,0,'مردودات مبيعات'),(j,ar,0,new.total_amount,'تخفيض ذمم العميل');return new;end $$;

create or replace function private.post_sale_return_cogs() returns trigger language plpgsql security definer set search_path='' as $$
declare si public.sale_items%rowtype;inv uuid;cogs uuid;j uuid;v numeric(14,2);r public.sale_returns%rowtype;
begin if new.disposition<>'restock' then return new;end if;select * into si from public.sale_items where id=new.sale_item_id;if si.unit_cost is null or si.unit_cost<=0 then return new;end if;
 select * into r from public.sale_returns where id=new.sale_return_id;select id into inv from public.accounting_accounts where code='1200' and is_active;select id into cogs from public.accounting_accounts where code='5000' and is_active;v:=round(si.unit_cost*new.quantity,2);
 insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.created_at::date,'إعادة تكلفة بضاعة مرتجعة','sale_return_cogs',new.id,r.created_by) returning id into j;
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,inv,v,0,'إعادة مخزون مرتجع'),(j,cogs,0,v,'عكس تكلفة البضاعة المرتجعة');return new;end $$;

create or replace function private.post_customer_credit_journal() returns trigger language plpgsql security definer set search_path='' as $$
declare ar uuid;credit_acct uuid;cash_acct uuid;j uuid;v numeric(14,2);
begin select id into ar from public.accounting_accounts where code='1100' and is_active;select id into credit_acct from public.accounting_accounts where code='2070' and is_active;
 if new.transaction_type='return_credit' then v:=new.amount;
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(new.created_at::date,'إصدار رصيد دائن للعميل','customer_credit',new.id,coalesce(new.created_by,(select auth.uid()))) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,ar,v,0,'إثبات رصيد العميل'),(j,credit_acct,0,v,'التزام رصيد دائن للعميل');
 elsif new.transaction_type='invoice_credit_application' then v:=abs(new.amount);
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(new.created_at::date,'استخدام رصيد دائن على فاتورة','customer_credit',new.id,coalesce(new.created_by,(select auth.uid()))) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,credit_acct,v,0,'تخفيض رصيد دائن'),(j,ar,0,v,'تخفيض مستحق العميل');
 elsif new.transaction_type='cash_refund' then v:=abs(new.amount);select id into cash_acct from public.accounting_accounts where code='1030' and is_active;
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(new.created_at::date,'رد رصيد دائن للعميل غير موزع','customer_credit',new.id,coalesce(new.created_by,(select auth.uid()))) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,credit_acct,v,0,'تخفيض التزام رصيد العميل'),(j,cash_acct,0,v,'رد نقدي غير موزع');
 end if;return new;end $$;

create trigger sales_post_revenue after insert on public.sales for each row execute function private.post_sale_invoice_journal();
create trigger sale_items_capture_cost before insert on public.sale_items for each row execute function private.capture_sale_item_cost();
create trigger sale_items_post_cogs after insert on public.sale_items for each row execute function private.post_sale_item_cogs();
create trigger payments_post_journal after insert on public.payments for each row execute function private.post_sale_payment_journal();
create trigger purchase_receipt_items_post_journal after insert on public.purchase_receipt_items for each row execute function private.post_purchase_receipt_journal();
create trigger supplier_bills_post_journal after insert on public.supplier_bills for each row execute function private.post_supplier_bill_journal();
create trigger supplier_return_items_post_journal after insert on public.supplier_return_items for each row execute function private.post_supplier_return_journal();
create trigger sale_returns_post_journal after insert on public.sale_returns for each row execute function private.post_sale_return_journal();
create trigger sale_return_items_post_cogs after insert on public.sale_return_items for each row execute function private.post_sale_return_cogs();
create trigger customer_credit_transactions_post_journal after insert on public.customer_credit_transactions for each row execute function private.post_customer_credit_journal();

