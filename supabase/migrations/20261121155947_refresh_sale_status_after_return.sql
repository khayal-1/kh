-- Refresh invoice payment status after customer returns.
create or replace function public.create_sale_return(p_sale_id uuid,p_items jsonb,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_sale public.sales%rowtype; v_item jsonb; v_sale_item public.sale_items%rowtype;
  v_quantity integer; v_disposition text; v_return_id uuid; v_return_number bigint;
  v_total numeric(12,2):=0; v_returned integer; v_returns_total numeric(12,2); v_count integer:=0;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then raise exception using errcode='42501',message='ليس لديك صلاحية تسجيل مرتجعات المبيعات'; end if;
  if p_sale_id is null or jsonb_typeof(p_items) is distinct from 'array' or coalesce(jsonb_array_length(p_items),0)<1 or coalesce(jsonb_array_length(p_items),0)>20 then raise exception using errcode='22023',message='اختر بندًا واحدًا على الأقل وبحد أقصى 20 بندًا'; end if;
  select * into v_sale from public.sales where id=p_sale_id for update;
  if not found or v_sale.status<>'posted' then raise exception using errcode='P0002',message='فاتورة البيع غير موجودة أو غير قابلة للإرجاع'; end if;
  if (select count(*) from jsonb_array_elements(p_items))<>(select count(distinct value->>'sale_item_id') from jsonb_array_elements(p_items)) then raise exception using errcode='22023',message='لا تكرر بند الفاتورة في المرتجع نفسه'; end if;
  for v_item in select value from jsonb_array_elements(p_items) order by value->>'sale_item_id' loop
    if coalesce(v_item->>'sale_item_id','')='' or coalesce(v_item->>'quantity','') !~ '^[0-9]+$' or coalesce(v_item->>'disposition','') not in ('restock','damaged') then raise exception using errcode='22023',message='بيانات بند المرتجع غير صحيحة'; end if;
    begin
      select * into v_sale_item from public.sale_items where id=(v_item->>'sale_item_id')::uuid and sale_id=p_sale_id for update;
      v_quantity:=(v_item->>'quantity')::integer;
    exception when invalid_text_representation then raise exception using errcode='22023',message='معرّف بند الفاتورة غير صالح';
    end;
    if not found then raise exception using errcode='P0002',message='بند الفاتورة غير موجود'; end if;
    if v_quantity<1 then raise exception using errcode='22023',message='كمية المرتجع يجب أن تكون أكبر من صفر'; end if;
    select coalesce(sum(i.quantity),0)::integer into v_returned from public.sale_return_items i where i.sale_item_id=v_sale_item.id;
    if v_quantity>v_sale_item.quantity-v_returned then raise exception using errcode='23514',message='كمية الإرجاع تتجاوز الكمية المباعة المتبقية'; end if;
    v_total:=v_total+(v_quantity*v_sale_item.unit_price); v_count:=v_count+1;
  end loop;
  insert into public.sale_returns(sale_id,customer_id,customer_name,total_amount,notes,created_by)
  values(p_sale_id,v_sale.customer_id,v_sale.customer_name,v_total,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()))
  returning id,return_number into v_return_id,v_return_number;
  for v_item in select value from jsonb_array_elements(p_items) order by value->>'sale_item_id' loop
    select * into v_sale_item from public.sale_items where id=(v_item->>'sale_item_id')::uuid;
    v_quantity:=(v_item->>'quantity')::integer; v_disposition:=v_item->>'disposition';
    insert into public.sale_return_items(sale_return_id,sale_item_id,motorcycle_id,quantity,disposition,unit_price,line_total)
    values(v_return_id,v_sale_item.id,v_sale_item.motorcycle_id,v_quantity,v_disposition,v_sale_item.unit_price,v_quantity*v_sale_item.unit_price);
    if v_disposition='restock' then
      update public.motorcycles set stock=stock+v_quantity where id=v_sale_item.motorcycle_id;
      insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by)
      values(v_sale_item.motorcycle_id,'sale_return',v_quantity,v_return_id,'إعادة مخزون صالح من مرتجع بيع '||v_sale.invoice_number,(select auth.uid()));
    end if;
  end loop;
  select coalesce(sum(total_amount),0) into v_returns_total from public.sale_returns where sale_id=p_sale_id;
  update public.sales set payment_status=case when amount_paid>=greatest(0,total-v_returns_total) then 'paid' when amount_paid>0 then 'partial' else 'unpaid' end,updated_at=now() where id=p_sale_id;
  return jsonb_build_object('id',v_return_id,'return_number',v_return_number,'sale_id',p_sale_id,'total_amount',v_total,'items_count',v_count,'customer_credit',v_total);
end;
$function$;
revoke all on function public.create_sale_return(uuid,jsonb,text) from public,anon;
grant execute on function public.create_sale_return(uuid,jsonb,text) to authenticated;