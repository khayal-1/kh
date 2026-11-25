create or replace function public.add_sale_return_customer_credit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_paid numeric(12,2);
  v_sale_total numeric(12,2);
  v_returns_total numeric(12,2);
  v_previously_issued numeric(12,2);
  v_incremental_credit numeric(12,2);
begin
  if new.customer_id is null or new.total_amount<=0 then return new; end if;
  perform 1 from public.clients where id=new.customer_id for update;
  if not found then raise exception using errcode='23503',message='العميل المرتبط بالمرتجع غير موجود'; end if;
  select amount_paid,total into v_paid,v_sale_total
  from public.sales where id=new.sale_id for update;
  if not found then raise exception using errcode='23503',message='فاتورة البيع المرتبطة بالمرتجع غير موجودة'; end if;
  select coalesce(sum(total_amount),0)::numeric(12,2) into v_returns_total
  from public.sale_returns where sale_id=new.sale_id;
  select coalesce(sum(amount),0)::numeric(12,2) into v_previously_issued
  from public.customer_credit_transactions
  where sale_id=new.sale_id and transaction_type='return_credit';
  v_incremental_credit:=greatest(0,v_paid+v_returns_total-v_sale_total)-v_previously_issued;
  if v_incremental_credit>0 then
    insert into public.customer_credit_transactions(
      customer_id,sale_id,sale_return_id,transaction_type,amount,notes,created_by
    ) values (
      new.customer_id,new.sale_id,new.id,'return_credit',v_incremental_credit,
      'رصيد مستحق فعليًا من مرتجع بيع رقم '||new.return_number::text,new.created_by
    ) on conflict (sale_return_id) where transaction_type='return_credit' do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.add_sale_return_customer_credit() from public,anon,authenticated;

with cumulative_returns as (
 select r.id return_id,r.sale_id,r.created_at,r.customer_id,s.amount_paid,s.total,
  sum(r.total_amount) over(partition by r.sale_id order by r.created_at,r.id rows between unbounded preceding and current row) running_returns,
  coalesce(sum(r.total_amount) over(partition by r.sale_id order by r.created_at,r.id rows between unbounded preceding and 1 preceding),0) previous_returns
 from public.sale_returns r join public.sales s on s.id=r.sale_id
), expected_credits as (
 select return_id,greatest(0,amount_paid+running_returns-total)-greatest(0,amount_paid+previous_returns-total) credit_amount
 from cumulative_returns
)
update public.customer_credit_transactions t
set amount=e.credit_amount,notes='رصيد مستحق فعليًا بعد تسوية مديونية فاتورة البيع'
from expected_credits e
where t.sale_return_id=e.return_id and t.transaction_type='return_credit' and e.credit_amount>0;

with cumulative_returns as (
 select r.id return_id,r.sale_id,r.created_at,r.customer_id,s.amount_paid,s.total,
  sum(r.total_amount) over(partition by r.sale_id order by r.created_at,r.id rows between unbounded preceding and current row) running_returns,
  coalesce(sum(r.total_amount) over(partition by r.sale_id order by r.created_at,r.id rows between unbounded preceding and 1 preceding),0) previous_returns
 from public.sale_returns r join public.sales s on s.id=r.sale_id
), expected_credits as (
 select return_id,greatest(0,amount_paid+running_returns-total)-greatest(0,amount_paid+previous_returns-total) credit_amount
 from cumulative_returns
)
delete from public.customer_credit_transactions t using expected_credits e
where t.sale_return_id=e.return_id and t.transaction_type='return_credit' and e.credit_amount<=0;

with cumulative_returns as (
 select r.id return_id,r.sale_id,r.created_at,r.customer_id,r.created_by,r.return_number,s.amount_paid,s.total,
  sum(r.total_amount) over(partition by r.sale_id order by r.created_at,r.id rows between unbounded preceding and current row) running_returns,
  coalesce(sum(r.total_amount) over(partition by r.sale_id order by r.created_at,r.id rows between unbounded preceding and 1 preceding),0) previous_returns
 from public.sale_returns r join public.sales s on s.id=r.sale_id
), expected_credits as (
 select *,greatest(0,amount_paid+running_returns-total)-greatest(0,amount_paid+previous_returns-total) credit_amount
 from cumulative_returns
)
insert into public.customer_credit_transactions(customer_id,sale_id,sale_return_id,transaction_type,amount,notes,created_by)
select customer_id,sale_id,return_id,'return_credit',credit_amount,'رصيد مستحق فعليًا من مرتجع بيع رقم '||return_number::text,created_by
from expected_credits e
where credit_amount>0 and not exists (
 select 1 from public.customer_credit_transactions t where t.sale_return_id=e.return_id and t.transaction_type='return_credit'
);

create or replace function public.create_sale_return(p_sale_id uuid,p_items jsonb,p_notes text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
 v_sale public.sales%rowtype;
 v_item jsonb;
 v_sale_item public.sale_items%rowtype;
 v_quantity integer;
 v_disposition text;
 v_return_id uuid;
 v_return_number bigint;
 v_total numeric(12,2):=0;
 v_returned integer;
 v_returns_total numeric(12,2);
 v_customer_credit numeric(12,2):=0;
 v_count integer:=0;
begin
 if (select auth.uid()) is null or not public.can_manage_sales() then
  raise exception using errcode='42501',message='ليس لديك صلاحية تسجيل مرتجعات المبيعات';
 end if;
 if p_sale_id is null or jsonb_typeof(p_items) is distinct from 'array'
  or coalesce(jsonb_array_length(p_items),0)<1 or coalesce(jsonb_array_length(p_items),0)>20 then
  raise exception using errcode='22023',message='اختر بندًا واحدًا على الأقل وبحد أقصى 20 بندًا';
 end if;
 select * into v_sale from public.sales where id=p_sale_id for update;
 if not found or v_sale.status<>'posted' then
  raise exception using errcode='P0002',message='فاتورة البيع غير موجودة أو غير قابلة للإرجاع';
 end if;
 if (select count(*) from jsonb_array_elements(p_items))<>
    (select count(distinct value->>'sale_item_id') from jsonb_array_elements(p_items)) then
  raise exception using errcode='22023',message='لا تكرر بند الفاتورة في المرتجع نفسه';
 end if;
 for v_item in select value from jsonb_array_elements(p_items) order by value->>'sale_item_id' loop
  if coalesce(v_item->>'sale_item_id','')='' or coalesce(v_item->>'quantity','') !~ '^[0-9]+$'
   or coalesce(v_item->>'disposition','') not in ('restock','damaged') then
   raise exception using errcode='22023',message='بيانات بند المرتجع غير صحيحة';
  end if;
  begin
   select * into v_sale_item from public.sale_items
   where id=(v_item->>'sale_item_id')::uuid and sale_id=p_sale_id for update;
   v_quantity:=(v_item->>'quantity')::integer;
  exception when invalid_text_representation then
   raise exception using errcode='22023',message='معرّف بند الفاتورة غير صالح';
  end;
  if not found then raise exception using errcode='P0002',message='بند الفاتورة غير موجود'; end if;
  if v_quantity<1 then raise exception using errcode='22023',message='كمية المرتجع يجب أن تكون أكبر من صفر'; end if;
  select coalesce(sum(i.quantity),0)::integer into v_returned
  from public.sale_return_items i where i.sale_item_id=v_sale_item.id;
  if v_quantity>v_sale_item.quantity-v_returned then
   raise exception using errcode='23514',message='كمية الإرجاع تتجاوز الكمية المباعة المتبقية';
  end if;
  v_total:=v_total+(v_quantity*v_sale_item.unit_price);
  v_count:=v_count+1;
 end loop;
 insert into public.sale_returns(sale_id,customer_id,customer_name,total_amount,notes,created_by)
 values(p_sale_id,v_sale.customer_id,v_sale.customer_name,v_total,
  nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()))
 returning id,return_number into v_return_id,v_return_number;
 for v_item in select value from jsonb_array_elements(p_items) order by value->>'sale_item_id' loop
  select * into v_sale_item from public.sale_items where id=(v_item->>'sale_item_id')::uuid;
  v_quantity:=(v_item->>'quantity')::integer;
  v_disposition:=v_item->>'disposition';
  insert into public.sale_return_items(sale_return_id,sale_item_id,motorcycle_id,quantity,disposition,unit_price,line_total)
  values(v_return_id,v_sale_item.id,v_sale_item.motorcycle_id,v_quantity,v_disposition,v_sale_item.unit_price,v_quantity*v_sale_item.unit_price);
  if v_disposition='restock' then
   update public.motorcycles set stock=stock+v_quantity where id=v_sale_item.motorcycle_id;
   insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by)
   values(v_sale_item.motorcycle_id,'sale_return',v_quantity,v_return_id,
    'إعادة مخزون صالح من مرتجع بيع '||v_sale.invoice_number,(select auth.uid()));
  end if;
 end loop;
 select coalesce(sum(total_amount),0) into v_returns_total
 from public.sale_returns where sale_id=p_sale_id;
 update public.sales set payment_status=case
  when amount_paid>=greatest(0,total-v_returns_total) then 'paid'
  when amount_paid>0 then 'partial' else 'unpaid' end,updated_at=now()
 where id=p_sale_id;
 select coalesce(amount,0) into v_customer_credit
 from public.customer_credit_transactions
 where sale_return_id=v_return_id and transaction_type='return_credit';
 return jsonb_build_object('id',v_return_id,'return_number',v_return_number,'sale_id',p_sale_id,
  'total_amount',v_total,'items_count',v_count,'customer_credit',coalesce(v_customer_credit,0));
end;
$function$;