alter table public.sales
  add column if not exists credit_applied numeric(12,2) not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid='public.sales'::regclass and conname='sales_credit_applied_nonnegative') then
    alter table public.sales add constraint sales_credit_applied_nonnegative check (credit_applied>=0);
  end if;
end $$;

alter table public.customer_credit_transactions drop constraint if exists customer_credit_transactions_check;
alter table public.customer_credit_transactions add constraint customer_credit_transactions_check check (
  (transaction_type='return_credit' and amount>0) or
  (transaction_type in ('cash_refund','invoice_credit_application') and amount<0)
);
alter table public.customer_credit_transactions drop constraint if exists customer_credit_transactions_transaction_type_check;
alter table public.customer_credit_transactions add constraint customer_credit_transactions_transaction_type_check
check (transaction_type in ('return_credit','cash_refund','invoice_credit_application'));

create or replace function public.apply_customer_credit_to_sale(p_sale_id uuid,p_amount numeric,p_reference text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_sale public.sales%rowtype;
  v_available numeric(12,2);
  v_returns numeric(12,2);
  v_due numeric(12,2);
  v_tx_id uuid;
  v_new_applied numeric(12,2);
  v_status text;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception using errcode='42501',message='ليس لديك صلاحية استخدام رصيد العملاء';
  end if;
  if p_sale_id is null or p_amount is null or p_amount<=0 then
    raise exception using errcode='22023',message='قيمة استخدام الرصيد غير صحيحة';
  end if;
  select * into v_sale from public.sales where id=p_sale_id for update;
  if not found or v_sale.status<>'posted' or v_sale.customer_id is null then
    raise exception using errcode='P0002',message='الفاتورة غير موجودة أو لا ترتبط بعميل';
  end if;
  perform 1 from public.clients where id=v_sale.customer_id for update;
  if not found then raise exception using errcode='P0002',message='العميل المرتبط بالفاتورة غير موجود'; end if;
  select coalesce(sum(amount),0)::numeric(12,2) into v_available
    from public.customer_credit_transactions where customer_id=v_sale.customer_id;
  select coalesce(sum(total_amount),0)::numeric(12,2) into v_returns
    from public.sale_returns where sale_id=p_sale_id;
  v_due:=greatest(0,v_sale.total-v_sale.amount_paid-v_sale.credit_applied-v_returns);
  if p_amount>v_available then raise exception using errcode='23514',message='المبلغ يتجاوز الرصيد الدائن المتاح للعميل'; end if;
  if p_amount>v_due then raise exception using errcode='23514',message='المبلغ يتجاوز المتبقي من الفاتورة'; end if;
  insert into public.customer_credit_transactions(customer_id,sale_id,transaction_type,amount,reference,notes,created_by)
  values(v_sale.customer_id,p_sale_id,'invoice_credit_application',-p_amount,
    nullif(btrim(coalesce(p_reference,'')),''),
    'استخدام رصيد عميل في الفاتورة '||v_sale.invoice_number,(select auth.uid()))
  returning id into v_tx_id;
  v_new_applied:=v_sale.credit_applied+p_amount;
  v_status:=case when v_sale.amount_paid+v_new_applied>=greatest(0,v_sale.total-v_returns) then 'paid'
    when v_sale.amount_paid+v_new_applied>0 then 'partial' else 'unpaid' end;
  update public.sales set credit_applied=v_new_applied,payment_status=v_status,updated_at=now() where id=p_sale_id;
  return jsonb_build_object('transaction_id',v_tx_id,'sale_id',p_sale_id,'applied_amount',p_amount,
    'credit_applied',v_new_applied,'remaining_due',greatest(0,v_due-p_amount),
    'remaining_customer_credit',v_available-p_amount,'payment_status',v_status);
end;
$$;
revoke all on function public.apply_customer_credit_to_sale(uuid,numeric,text) from public,anon;
grant execute on function public.apply_customer_credit_to_sale(uuid,numeric,text) to authenticated,postgres;

create or replace function public.record_sale_payment(p_sale_id uuid,p_amount numeric,p_method text,p_reference text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_sale public.sales%rowtype;
  v_paid numeric(12,2);
  v_returns numeric(12,2);
  v_due numeric(12,2);
  v_status text;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception using errcode='42501',message='ليس لديك صلاحية تسجيل المدفوعات';
  end if;
  if p_amount is null or p_amount<=0 or coalesce(p_method,'') not in ('cash','bank_transfer','card','other') then
    raise exception using errcode='22023',message='قيمة أو طريقة الدفع غير صحيحة';
  end if;
  select * into v_sale from public.sales where id=p_sale_id for update;
  if not found or v_sale.status<>'posted' then
    raise exception using errcode='P0002',message='الفاتورة غير موجودة أو غير قابلة للتحصيل';
  end if;
  select coalesce(sum(total_amount),0) into v_returns from public.sale_returns where sale_id=p_sale_id;
  v_due:=greatest(0,v_sale.total-v_returns-v_sale.amount_paid-v_sale.credit_applied);
  if p_amount>v_due then raise exception using errcode='23514',message='المبلغ أكبر من الرصيد المستحق بعد احتساب المرتجعات والأرصدة المستخدمة'; end if;
  insert into public.payments(sale_id,amount,method,reference,received_by)
  values(p_sale_id,p_amount,p_method,nullif(btrim(coalesce(p_reference,'')),''),(select auth.uid()));
  v_paid:=v_sale.amount_paid+p_amount;
  v_status:=case when v_paid+v_sale.credit_applied>=greatest(0,v_sale.total-v_returns) then 'paid'
    when v_paid+v_sale.credit_applied>0 then 'partial' else 'unpaid' end;
  update public.sales set amount_paid=v_paid,payment_status=v_status,updated_at=now() where id=p_sale_id;
  return jsonb_build_object('sale_id',p_sale_id,'amount_paid',v_paid,'credit_applied',v_sale.credit_applied,
    'returns_total',v_returns,'balance_due',greatest(0,v_sale.total-v_returns-v_paid-v_sale.credit_applied),'payment_status',v_status);
end;
$$;
revoke all on function public.record_sale_payment(uuid,numeric,text,text) from public,anon;
grant execute on function public.record_sale_payment(uuid,numeric,text,text) to authenticated,postgres;

create or replace function public.add_sale_return_customer_credit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_paid numeric(12,2);
  v_credit_applied numeric(12,2);
  v_sale_total numeric(12,2);
  v_returns_total numeric(12,2);
  v_previously_issued numeric(12,2);
  v_incremental_credit numeric(12,2);
begin
  if new.customer_id is null or new.total_amount<=0 then return new; end if;
  perform 1 from public.clients where id=new.customer_id for update;
  if not found then raise exception using errcode='23503',message='العميل المرتبط بالمرتجع غير موجود'; end if;
  select amount_paid,credit_applied,total into v_paid,v_credit_applied,v_sale_total
    from public.sales where id=new.sale_id for update;
  if not found then raise exception using errcode='23503',message='فاتورة البيع المرتبطة بالمرتجع غير موجودة'; end if;
  select coalesce(sum(total_amount),0)::numeric(12,2) into v_returns_total from public.sale_returns where sale_id=new.sale_id;
  select coalesce(sum(amount),0)::numeric(12,2) into v_previously_issued
    from public.customer_credit_transactions where sale_id=new.sale_id and transaction_type='return_credit';
  v_incremental_credit:=greatest(0,v_paid+v_credit_applied+v_returns_total-v_sale_total)-v_previously_issued;
  if v_incremental_credit>0 then
    insert into public.customer_credit_transactions(customer_id,sale_id,sale_return_id,transaction_type,amount,notes,created_by)
    values(new.customer_id,new.sale_id,new.id,'return_credit',v_incremental_credit,
      'رصيد مستحق فعليًا من مرتجع بيع رقم '||new.return_number::text,new.created_by)
    on conflict (sale_return_id) where transaction_type='return_credit' do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.add_sale_return_customer_credit() from public,anon,authenticated;

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.create_sale_return(uuid,jsonb,text)'::regprocedure) into v_definition;
  v_definition:=replace(v_definition,
    'when amount_paid>=greatest(0,total-v_returns_total)',
    'when amount_paid+credit_applied>=greatest(0,total-v_returns_total)');
  execute v_definition;
end $$;