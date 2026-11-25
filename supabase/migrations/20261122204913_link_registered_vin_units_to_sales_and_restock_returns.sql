-- Source recovered from the applied production migration ledger.
create or replace function private.post_sale_item_cogs()
returns trigger language plpgsql security definer set search_path=''
as $$
declare c uuid;i uuid;j uuid;v numeric(14,2);
begin
 if new.unit_cost is not null and new.unit_cost>0 then
  select id into c from public.accounting_accounts where code='5000' and is_active;
  select id into i from public.accounting_accounts where code='1200' and is_active;
  v:=round(new.unit_cost*new.quantity,2);
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
  select s.created_at::date,'تكلفة بضاعة فاتورة '||s.invoice_number,'sale_cogs',new.id,s.created_by from public.sales s where s.id=new.sale_id returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,c,v,0,'تكلفة البضاعة المباعة'),(j,i,0,v,'تخفيض قيمة المخزون');
 end if;
 with picked as (
  select id from public.motorcycle_units where motorcycle_id=new.motorcycle_id and unit_status='available'
  order by registered_at,id limit new.quantity for update skip locked
 )
 update public.motorcycle_units u set unit_status='sold',sale_item_id=new.id from picked where u.id=picked.id;
 update public.sales s set costing_status=case when exists(select 1 from public.sale_items si where si.sale_id=new.sale_id and si.unit_cost is null) then 'incomplete' else 'complete' end where s.id=new.sale_id;
 return new;
end $$;

create or replace function private.post_sale_return_cogs()
returns trigger language plpgsql security definer set search_path=''
as $$
declare si public.sale_items%rowtype;inv uuid;cogs uuid;j uuid;v numeric(14,2);r public.sale_returns%rowtype;
begin
 if new.disposition<>'restock' then return new;end if;
 select * into si from public.sale_items where id=new.sale_item_id;
 if si.unit_cost is not null and si.unit_cost>0 then
  select * into r from public.sale_returns where id=new.sale_return_id;
  select id into inv from public.accounting_accounts where code='1200' and is_active;
  select id into cogs from public.accounting_accounts where code='5000' and is_active;
  v:=round(si.unit_cost*new.quantity,2);
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(r.created_at::date,'إعادة تكلفة بضاعة مرتجعة','sale_return_cogs',new.id,r.created_by) returning id into j;
  insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(j,inv,v,0,'إعادة مخزون مرتجع'),(j,cogs,0,v,'عكس تكلفة البضاعة المرتجعة');
 end if;
 with picked as (
  select id from public.motorcycle_units where sale_item_id=new.sale_item_id and unit_status='sold'
  order by registered_at desc,id desc limit new.quantity for update skip locked
 )
 update public.motorcycle_units u set unit_status='available',sale_item_id=null from picked where u.id=picked.id;
 return new;
end $$;
