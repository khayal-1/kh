begin;

drop policy if exists motorcycle_units_sales_read on public.motorcycle_units;
create policy motorcycle_units_sales_read on public.motorcycle_units
  for select to authenticated using (public.can_manage_sales());

create or replace function private.create_showroom_sale_with_units_impl(
  p_customer_user_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_payment_amount numeric,
  p_payment_method text,
  p_payment_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  item jsonb;
  unit_value text;
  unit_id uuid;
  u public.motorcycle_units%rowtype;
  b public.motorcycles%rowtype;
  cl public.clients%rowtype;
  customer_id uuid;
  customer_name_value text;
  customer_phone_value text;
  sale_id uuid;
  invoice_value text;
  paid_value numeric(14,2):=coalesce(p_payment_amount,0);
  total_value numeric(14,2):=0;
  quantity_value integer;
  status_value text;
  item_id uuid;
  item_count integer:=0;
  all_ids text[];
  result_units jsonb:='[]'::jsonb;
begin
  if (select auth.uid()) is null or not public.can_manage_sales() then
    raise exception 'ليس لديك صلاحية تسجيل المبيعات' using errcode='42501';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'بيانات أصناف الفاتورة غير صحيحة' using errcode='22023';
  end if;
  if jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>20 or paid_value<0 then
    raise exception 'بيانات أصناف الفاتورة غير صحيحة' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_items) x(value)
            where jsonb_typeof(value->'unit_ids') is distinct from 'array') then
    raise exception 'حدد قائمة أرقام الشاسيه لكل صنف' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_items) x(value)
            where jsonb_array_length(value->'unit_ids')<1) then
    raise exception 'حدد رقم شاسيه واحدًا على الأقل لكل طراز' using errcode='22023';
  end if;

  select array_agg(u.value)
    into all_ids
    from jsonb_array_elements(p_items) p,
         jsonb_array_elements_text(p.value->'unit_ids') u(value);
  if coalesce(cardinality(all_ids),0)<1
     or cardinality(all_ids)<>(select count(distinct x) from unnest(all_ids) x) then
    raise exception 'اختر وحدات فعلية مختلفة لكل صنف؛ لا يمكن بيع موديل بكمية دون تحديد أرقام الشاسيه' using errcode='22023';
  end if;

  -- Lock models in stable order, then lock the exact physical units.
  for item in
    select value from jsonb_array_elements(p_items) x(value)
    order by value->>'motorcycle_id'
  loop
    begin
      select * into b from public.motorcycles
       where id=(item->>'motorcycle_id')::uuid for update;
    exception when invalid_text_representation then
      raise exception 'طراز الدراجة المحدد غير صالح' using errcode='22023';
    end;
    if not found or b.status<>'available'::public.motorcycle_status then
      raise exception 'أحد طرازات الدراجة غير موجود أو غير متاح للبيع' using errcode='23514';
    end if;
    if jsonb_typeof(item->'unit_ids') is distinct from 'array'
       or jsonb_array_length(item->'unit_ids')<1 then
      raise exception 'حدد رقم شاسيه واحدًا على الأقل لكل طراز' using errcode='22023';
    end if;
    quantity_value:=jsonb_array_length(item->'unit_ids');
    if b.stock<quantity_value then
      raise exception 'رصيد الطراز لا يكفي للوحدات المحددة: %',b.name using errcode='23514';
    end if;
    for unit_value in select value from jsonb_array_elements_text(item->'unit_ids') loop
      begin unit_id:=unit_value::uuid;
      exception when others then raise exception 'معرّف وحدة غير صالح' using errcode='22023'; end;
      select * into u from public.motorcycle_units
       where id=unit_id and motorcycle_id=b.id and unit_status='available'
       for update;
      if not found then
        raise exception 'إحدى الوحدات المحددة غير متاحة أو لا تطابق طراز الدراجة: %',b.name
          using errcode='23514';
      end if;
      total_value:=total_value+b.price;
      item_count:=item_count+1;
    end loop;
  end loop;

  if paid_value>total_value then
    raise exception 'المبلغ المدفوع أكبر من إجمالي الفاتورة' using errcode='23514';
  end if;
  if paid_value>0 and coalesce(p_payment_method,'') not in ('cash','bank_transfer','card','other') then
    raise exception 'طريقة الدفع غير صحيحة' using errcode='22023';
  end if;

  if p_customer_user_id is not null then
    select * into cl from public.clients where user_id=p_customer_user_id for share;
    if not found then
      raise exception 'حساب العميل المحدد غير مرتبط بملف عميل' using errcode='P0002';
    end if;
    customer_id:=cl.id;
    customer_name_value:=coalesce(nullif(btrim(cl.display_name),''),nullif(btrim(p_customer_name),''),'عميل');
    customer_phone_value:=coalesce(nullif(btrim(cl.phone),''),nullif(btrim(p_customer_phone),''),'');
  else
    customer_name_value:=coalesce(nullif(btrim(p_customer_name),''),'عميل نقدي');
    customer_phone_value:=nullif(btrim(coalesce(p_customer_phone,'')),'');
    insert into public.clients(user_id,display_name,phone)
    values(null,customer_name_value,customer_phone_value)
    returning id into customer_id;
  end if;

  invoice_value:='EKM-'||to_char(now(),'YYYYMMDD')||'-'||
    lpad(nextval('public.sale_invoice_number_seq')::text,6,'0');
  status_value:=case when paid_value=0 then 'unpaid' when paid_value<total_value then 'partial' else 'paid' end;
  insert into public.sales(
    invoice_number,customer_id,customer_name,customer_phone,channel,
    subtotal,total,amount_paid,payment_status,notes,created_by
  ) values (
    invoice_value,customer_id,customer_name_value,nullif(customer_phone_value,''),'showroom',
    total_value,total_value,paid_value,status_value,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())
  ) returning id into sale_id;

  for item in
    select value from jsonb_array_elements(p_items) x(value)
    order by value->>'motorcycle_id'
  loop
    select * into b from public.motorcycles where id=(item->>'motorcycle_id')::uuid;
    quantity_value:=jsonb_array_length(item->'unit_ids');
    for unit_value in select value from jsonb_array_elements_text(item->'unit_ids') loop
      unit_id:=unit_value::uuid;
      select * into u from public.motorcycle_units where id=unit_id;
      perform set_config('ekm.sale_unit_id',u.id::text,true);
      insert into public.sale_items(
        sale_id,motorcycle_id,motorcycle_name,model_year,unit_price,quantity,line_total,unit_cost
      ) values (
        sale_id,b.id,b.name,b.model_year,b.price,1,b.price,
        coalesce(u.unit_cost,(select unit_cost from public.motorcycle_inventory_costs where motorcycle_id=b.id))
      ) returning id into item_id;
      result_units:=result_units||jsonb_build_array(jsonb_build_object(
        'unit_id',u.id,'sale_item_id',item_id,'motorcycle_id',b.id,
        'motorcycle_name',b.name,'model_year',b.model_year,'vin',u.vin,
        'engine_number',u.engine_number,'unit_price',b.price
      ));
    end loop;
    perform set_config('ekm.sale_unit_id','',true);
    perform set_config('ekm.stock_movement_source','sale',true);
    update public.motorcycles set stock=stock-quantity_value where id=b.id;
    perform set_config('ekm.stock_movement_source','',true);
    insert into public.stock_movements(
      motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by
    ) values(b.id,'sale',-quantity_value,sale_id,'بيع وحدات محددة بأرقام الشاسيه ضمن فاتورة '||invoice_value,(select auth.uid()));
  end loop;

  if paid_value>0 then
    insert into public.payments(sale_id,amount,method,reference,received_by)
    values(sale_id,paid_value,p_payment_method,nullif(btrim(coalesce(p_payment_reference,'')),''),(select auth.uid()));
  end if;
  return jsonb_build_object(
    'id',sale_id,'sale_id',sale_id,'created_at',now(),'invoice_number',invoice_value,
    'customer_id',customer_id,'customer_name',customer_name_value,
    'customer_phone',customer_phone_value,'total',total_value,'subtotal',total_value,
    'amount_paid',paid_value,'balance_due',total_value-paid_value,
    'payment_status',status_value,'units',result_units,'quantity',item_count
  );
end;
$$;

revoke all on function private.create_showroom_sale_with_units_impl(uuid,text,text,jsonb,numeric,text,text,text) from public,anon;
grant execute on function private.create_showroom_sale_with_units_impl(uuid,text,text,jsonb,numeric,text,text,text) to authenticated;

create or replace function public.create_showroom_sale_with_units(
  p_customer_user_id uuid,p_customer_name text,p_customer_phone text,
  p_items jsonb,p_payment_amount numeric,p_payment_method text,
  p_payment_reference text default null,p_notes text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select private.create_showroom_sale_with_units_impl($1,$2,$3,$4,$5,$6,$7,$8);
$$;
revoke all on function public.create_showroom_sale_with_units(uuid,text,text,jsonb,numeric,text,text,text) from public,anon;
grant execute on function public.create_showroom_sale_with_units(uuid,text,text,jsonb,numeric,text,text,text) to authenticated;

commit;
