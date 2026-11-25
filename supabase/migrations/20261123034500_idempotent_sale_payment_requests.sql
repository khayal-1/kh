begin;

alter table public.payments
  add column if not exists idempotency_key uuid;

create unique index if not exists payments_idempotency_key_uidx
  on public.payments(idempotency_key)
  where idempotency_key is not null;

create or replace function private.record_sale_payment_idempotent_impl(
  p_sale_id uuid,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_sale public.sales%rowtype;
  v_payment public.payments%rowtype;
  v_paid numeric(12,2);
  v_returns numeric(12,2);
  v_due numeric(12,2);
  v_status text;
  v_inserted integer:=0;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception 'ليس لديك صلاحية تسجيل المدفوعات' using errcode='42501';
  end if;
  if p_sale_id is null or p_amount is null or p_amount<=0
     or coalesce(p_method,'') not in ('cash','bank_transfer','card','other')
     or p_idempotency_key is null then
    raise exception 'بيانات الدفعة أو مفتاح منع التكرار غير صحيحة' using errcode='22023';
  end if;

  -- Serialize attempts for the same invoice before checking the idempotency key.
  select * into v_sale from public.sales where id=p_sale_id for update;
  if not found or v_sale.status<>'posted' then
    raise exception 'الفاتورة غير موجودة أو غير قابلة للتحصيل' using errcode='P0002';
  end if;

  select * into v_payment from public.payments
   where idempotency_key=p_idempotency_key for update;
  if found then
    if v_payment.sale_id<>p_sale_id or v_payment.amount<>p_amount or v_payment.method<>p_method then
      raise exception 'مفتاح العملية مستخدم مسبقًا لدفعة مختلفة' using errcode='23505';
    end if;
    select * into v_sale from public.sales where id=p_sale_id;
    select coalesce(sum(total_amount),0) into v_returns
      from public.sale_returns where sale_id=p_sale_id;
    return jsonb_build_object(
      'sale_id',p_sale_id,'payment_id',v_payment.id,'amount_paid',v_sale.amount_paid,
      'credit_applied',v_sale.credit_applied,'returns_total',v_returns,
      'balance_due',greatest(0,v_sale.total-v_returns-v_sale.amount_paid-v_sale.credit_applied),
      'payment_status',v_sale.payment_status,'replayed',true
    );
  end if;

  select coalesce(sum(total_amount),0) into v_returns
    from public.sale_returns where sale_id=p_sale_id;
  v_due:=greatest(0,v_sale.total-v_returns-v_sale.amount_paid-v_sale.credit_applied);
  if p_amount>v_due then
    raise exception 'المبلغ أكبر من الرصيد المستحق بعد احتساب المرتجعات والأرصدة المستخدمة'
      using errcode='23514';
  end if;

  insert into public.payments(
    sale_id,amount,method,reference,received_by,idempotency_key
  ) values (
    p_sale_id,p_amount,p_method,nullif(btrim(coalesce(p_reference,'')),''),(select auth.uid()),p_idempotency_key
  ) on conflict (idempotency_key) where idempotency_key is not null do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted=0 then
    select * into v_payment from public.payments
     where idempotency_key=p_idempotency_key for update;
    if not found or v_payment.sale_id<>p_sale_id
       or v_payment.amount<>p_amount or v_payment.method<>p_method then
      raise exception 'مفتاح العملية مستخدم مسبقًا لدفعة مختلفة' using errcode='23505';
    end if;
    select * into v_sale from public.sales where id=p_sale_id;
    return jsonb_build_object(
      'sale_id',p_sale_id,'payment_id',v_payment.id,'amount_paid',v_sale.amount_paid,
      'credit_applied',v_sale.credit_applied,'returns_total',v_returns,
      'balance_due',greatest(0,v_sale.total-v_returns-v_sale.amount_paid-v_sale.credit_applied),
      'payment_status',v_sale.payment_status,'replayed',true
    );
  end if;

  v_paid:=v_sale.amount_paid+p_amount;
  v_status:=case
    when v_paid+v_sale.credit_applied>=greatest(0,v_sale.total-v_returns) then 'paid'
    when v_paid+v_sale.credit_applied>0 then 'partial'
    else 'unpaid' end;
  update public.sales
     set amount_paid=v_paid,payment_status=v_status,updated_at=now()
   where id=p_sale_id;

  return jsonb_build_object(
    'sale_id',p_sale_id,'payment_id',(select id from public.payments where idempotency_key=p_idempotency_key),
    'amount_paid',v_paid,'credit_applied',v_sale.credit_applied,'returns_total',v_returns,
    'balance_due',greatest(0,v_sale.total-v_returns-v_paid-v_sale.credit_applied),
    'payment_status',v_status,'replayed',false
  );
end;
$$;

revoke all on function private.record_sale_payment_idempotent_impl(uuid,numeric,text,text,uuid) from public,anon;
grant execute on function private.record_sale_payment_idempotent_impl(uuid,numeric,text,text,uuid) to authenticated;

create or replace function public.record_sale_payment(
  p_sale_id uuid,p_amount numeric,p_method text,p_reference text,p_idempotency_key uuid
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select private.record_sale_payment_idempotent_impl($1,$2,$3,$4,$5);
$$;
revoke all on function public.record_sale_payment(uuid,numeric,text,text,uuid) from public,anon;
grant execute on function public.record_sale_payment(uuid,numeric,text,text,uuid) to authenticated;

commit;
