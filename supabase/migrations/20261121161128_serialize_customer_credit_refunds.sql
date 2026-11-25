create or replace function public.add_sale_return_customer_credit()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.customer_id is not null and new.total_amount > 0 then
    perform 1 from public.clients where id=new.customer_id for update;
    if not found then
      raise exception using errcode='23503',message='العميل المرتبط بالمرتجع غير موجود';
    end if;
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