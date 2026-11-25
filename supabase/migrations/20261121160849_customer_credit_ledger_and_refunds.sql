create table if not exists public.customer_credit_transactions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.clients(id) on delete restrict,
  sale_id uuid references public.sales(id) on delete restrict,
  sale_return_id uuid references public.sale_returns(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('return_credit','cash_refund')),
  amount numeric(12,2) not null check (
    (transaction_type='return_credit' and amount>0) or
    (transaction_type='cash_refund' and amount<0)
  ),
  method text check (method is null or method in ('cash','bank_transfer','card','other')),
  reference text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists customer_credit_one_return_credit_idx
  on public.customer_credit_transactions(sale_return_id)
  where transaction_type='return_credit';
create index if not exists customer_credit_customer_created_idx
  on public.customer_credit_transactions(customer_id,created_at desc);
create index if not exists customer_credit_sale_id_idx
  on public.customer_credit_transactions(sale_id)
  where sale_id is not null;

alter table public.customer_credit_transactions enable row level security;
drop policy if exists customer_credit_transactions_manager_select on public.customer_credit_transactions;
create policy customer_credit_transactions_manager_select
  on public.customer_credit_transactions for select to authenticated
  using (public.can_manage_sales());

grant select on public.customer_credit_transactions to authenticated;
revoke insert, update, delete, truncate, references, trigger on public.customer_credit_transactions from anon, authenticated;

create or replace function public.add_sale_return_customer_credit()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.customer_id is not null and new.total_amount > 0 then
    insert into public.customer_credit_transactions(
      customer_id,sale_id,sale_return_id,transaction_type,amount,notes,created_by
    ) values (
      new.customer_id,new.sale_id,new.id,'return_credit',new.total_amount,
      'رصيد ناتج عن مرتجع بيع رقم '||new.return_number::text,new.created_by
    )
    on conflict (sale_return_id) where transaction_type='return_credit' do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.add_sale_return_customer_credit() from public, anon, authenticated;

drop trigger if exists sale_return_customer_credit_ledger on public.sale_returns;
create trigger sale_return_customer_credit_ledger
after insert on public.sale_returns
for each row execute function public.add_sale_return_customer_credit();

insert into public.customer_credit_transactions(
  customer_id,sale_id,sale_return_id,transaction_type,amount,notes,created_by
)
select r.customer_id,r.sale_id,r.id,'return_credit',r.total_amount,
       'رصيد مرحّل من مرتجع بيع رقم '||r.return_number::text,r.created_by
from public.sale_returns r
where r.customer_id is not null and r.total_amount>0
on conflict (sale_return_id) where transaction_type='return_credit' do nothing;

create or replace function public.record_customer_credit_refund(
  p_customer_id uuid,p_amount numeric,p_method text,
  p_reference text default null,p_notes text default null
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_balance numeric(12,2); v_tx_id uuid;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception using errcode='42501',message='ليس لديك صلاحية تسجيل رد أموال العملاء';
  end if;
  if p_customer_id is null or p_amount is null or p_amount<=0
     or coalesce(p_method,'') not in ('cash','bank_transfer','card','other') then
    raise exception using errcode='22023',message='بيانات رد المبلغ غير صحيحة';
  end if;
  perform 1 from public.clients where id=p_customer_id for update;
  if not found then raise exception using errcode='P0002',message='العميل غير موجود'; end if;
  select coalesce(sum(amount),0)::numeric(12,2) into v_balance
  from public.customer_credit_transactions where customer_id=p_customer_id;
  if p_amount>v_balance then
    raise exception using errcode='23514',message='قيمة الرد تتجاوز رصيد العميل المتاح';
  end if;
  insert into public.customer_credit_transactions(
    customer_id,transaction_type,amount,method,reference,notes,created_by
  ) values (
    p_customer_id,'cash_refund',-p_amount,p_method,
    nullif(btrim(coalesce(p_reference,'')),''),
    nullif(btrim(coalesce(p_notes,'')),''),
    (select auth.uid())
  ) returning id into v_tx_id;
  return jsonb_build_object('transaction_id',v_tx_id,'customer_id',p_customer_id,
    'refunded_amount',p_amount,'remaining_credit',v_balance-p_amount);
end;
$$;
revoke all on function public.record_customer_credit_refund(uuid,numeric,text,text,text) from public, anon;
grant execute on function public.record_customer_credit_refund(uuid,numeric,text,text,text) to authenticated, postgres;