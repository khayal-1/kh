-- Source recovered from the applied production migration ledger.
create table if not exists public.sales_quotations(
 id uuid primary key default gen_random_uuid(),quotation_number bigint generated always as identity unique,
 customer_id uuid references public.clients(id) on delete restrict,customer_name text not null,customer_phone text not null,
 valid_until date not null,status text not null default 'draft' check(status in ('draft','sent','accepted','expired','converted','cancelled')),
 subtotal numeric(14,2) not null default 0,total_amount numeric(14,2) not null default 0,notes text,
 sale_id uuid unique references public.sales(id) on delete restrict,
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now()
);
create table if not exists public.sales_quotation_items(
 id uuid primary key default gen_random_uuid(),quotation_id uuid not null references public.sales_quotations(id) on delete restrict,
 motorcycle_id uuid not null references public.motorcycles(id) on delete restrict,quantity integer not null check(quantity>0),
 unit_price numeric(14,2) not null check(unit_price>=0),line_total numeric(14,2) not null check(line_total>=0)
);
create table if not exists public.sale_installments(
 id uuid primary key default gen_random_uuid(),sale_id uuid not null references public.sales(id) on delete restrict,
 installment_number integer not null check(installment_number>0),due_date date not null,
 amount numeric(14,2) not null check(amount>0),paid_amount numeric(14,2) not null default 0 check(paid_amount>=0 and paid_amount<=amount),
 status text not null default 'pending' check(status in ('pending','partial','paid','cancelled')),
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),
 unique(sale_id,installment_number)
);
create index if not exists sale_installments_due_idx on public.sale_installments(due_date,status);

alter table public.sales_quotations enable row level security;
alter table public.sales_quotation_items enable row level security;
alter table public.sale_installments enable row level security;
revoke all on public.sales_quotations,public.sales_quotation_items,public.sale_installments from anon,authenticated;
grant select on public.sales_quotations,public.sales_quotation_items,public.sale_installments to authenticated;
create policy sales_quotations_read on public.sales_quotations for select to authenticated using(
 public.can_manage_sales() or exists(select 1 from public.clients c where c.id=sales_quotations.customer_id and c.user_id=(select auth.uid()))
);
create policy sales_quotation_items_read on public.sales_quotation_items for select to authenticated using(
 public.can_manage_sales() or exists(select 1 from public.sales_quotations q join public.clients c on c.id=q.customer_id where q.id=sales_quotation_items.quotation_id and c.user_id=(select auth.uid()))
);
create policy sale_installments_read on public.sale_installments for select to authenticated using(
 public.can_manage_sales() or exists(select 1 from public.sales s join public.clients c on c.id=s.customer_id where s.id=sale_installments.sale_id and c.user_id=(select auth.uid()))
);

create or replace function private.create_sales_quotation(p_customer_id uuid,p_name text,p_phone text,p_valid_until date,p_notes text,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid();v_item jsonb;v_bike uuid;v_qty integer;v_price numeric(14,2);v_total numeric(14,2):=0;
begin
 if not public.can_manage_sales() then raise exception 'غير مصرح بإنشاء عرض سعر' using errcode='42501';end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null or nullif(btrim(coalesce(p_phone,'')),'') is null or p_valid_until is null or p_valid_until<current_date or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>20 then raise exception 'بيانات عرض السعر غير صحيحة' using errcode='22023';end if;
 if p_customer_id is not null and not exists(select 1 from public.clients where id=p_customer_id) then raise exception 'العميل غير موجود' using errcode='P0002';end if;
 insert into public.sales_quotations(id,customer_id,customer_name,customer_phone,valid_until,notes,created_by)
 values(v_id,p_customer_id,btrim(p_name),btrim(p_phone),p_valid_until,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()));
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_bike:=(v_item->>'motorcycle_id')::uuid;v_qty:=(v_item->>'quantity')::integer;v_price:=round((v_item->>'unit_price')::numeric,2);
  if v_qty is null or v_qty<=0 or v_price is null or v_price<0 or not exists(select 1 from public.motorcycles where id=v_bike and status='available' and stock>=v_qty) then raise exception 'كمية أو سعر أو مخزون أحد أصناف العرض غير صالح' using errcode='23514';end if;
  insert into public.sales_quotation_items(quotation_id,motorcycle_id,quantity,unit_price,line_total) values(v_id,v_bike,v_qty,v_price,round(v_qty*v_price,2));
  v_total:=v_total+round(v_qty*v_price,2);
 end loop;
 update public.sales_quotations set subtotal=v_total,total_amount=v_total where id=v_id;
 return v_id;
end $$;

create or replace function private.update_sales_quotation_status(p_quote_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.can_manage_sales() then raise exception 'غير مصرح بتحديث عرض السعر' using errcode='42501';end if;
 if p_status not in ('sent','accepted','cancelled','expired') then raise exception 'حالة عرض السعر غير صحيحة' using errcode='22023';end if;
 update public.sales_quotations set status=p_status where id=p_quote_id and status in ('draft','sent','accepted');
 if not found then raise exception 'عرض السعر غير موجود أو تم تحويله بالفعل' using errcode='P0002';end if;
end $$;

create or replace function private.convert_sales_quotation(p_quote_id uuid,p_payment_amount numeric default 0,p_payment_method text default 'cash',p_reference text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.sales_quotations%rowtype;v_user uuid;v_items jsonb;v_result jsonb;v_sale_id uuid;
begin
 if not public.can_manage_sales() then raise exception 'غير مصرح بتحويل عرض السعر إلى فاتورة' using errcode='42501';end if;
 select * into q from public.sales_quotations where id=p_quote_id for update;
 if not found or q.status<>'accepted' or q.valid_until<current_date then raise exception 'يجب اعتماد عرض السعر وأن يكون ساريًا قبل التحويل' using errcode='23514';end if;
 select jsonb_agg(jsonb_build_object('motorcycle_id',motorcycle_id,'quantity',quantity,'unit_price',unit_price)) into v_items from public.sales_quotation_items where quotation_id=p_quote_id;
 select user_id into v_user from public.clients where id=q.customer_id;
 if v_user is not null then
  v_result:=public.create_showroom_sale_for_customer(v_user,q.customer_name,q.customer_phone,v_items,coalesce(p_payment_amount,0),coalesce(p_payment_method,'cash'),p_reference,q.notes);
 else
  v_result:=public.create_showroom_sale(q.customer_name,q.customer_phone,v_items,coalesce(p_payment_amount,0),coalesce(p_payment_method,'cash'),p_reference,q.notes);
 end if;
 v_sale_id:=nullif(v_result->>'sale_id','')::uuid;
 if v_sale_id is null then raise exception 'تم إنشاء الفاتورة دون إرجاع رقمها؛ أوقف التحويل وراجع السجل' using errcode='P0001';end if;
 update public.sales_quotations set status='converted',sale_id=v_sale_id where id=p_quote_id;
 return jsonb_build_object('quotation_id',p_quote_id,'sale_id',v_sale_id,'sale_result',v_result);
end $$;

create or replace function private.create_sale_installment_schedule(p_sale_id uuid,p_schedule jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare s public.sales%rowtype;v_returns numeric(14,2);v_due numeric(14,2);v_sum numeric(14,2);v_item jsonb;v_n integer:=0;v_date date;v_amount numeric(14,2);
begin
 if not public.can_manage_sales() then raise exception 'غير مصرح بإنشاء جدول أقساط' using errcode='42501';end if;
 select * into s from public.sales where id=p_sale_id and status='posted' for update;if not found then raise exception 'الفاتورة غير موجودة' using errcode='P0002';end if;
 if exists(select 1 from public.sale_installments where sale_id=p_sale_id and status<>'cancelled') then raise exception 'يوجد جدول أقساط قائم لهذه الفاتورة' using errcode='23505';end if;
 select coalesce(sum(total_amount),0) into v_returns from public.sale_returns where sale_id=p_sale_id;
 v_due:=greatest(0,s.total-v_returns-s.amount_paid-s.credit_applied);
 if v_due<=0 or jsonb_typeof(p_schedule) is distinct from 'array' or jsonb_array_length(p_schedule)<1 or jsonb_array_length(p_schedule)>36 then raise exception 'لا يوجد رصيد مستحق أو جدول الأقساط غير صالح' using errcode='22023';end if;
 select coalesce(sum((value->>'amount')::numeric),0) into v_sum from jsonb_array_elements(p_schedule);
 if abs(v_sum-v_due)>0.01 then raise exception 'مجموع الأقساط يجب أن يساوي الرصيد المستحق: %',v_due using errcode='23514';end if;
 for v_item in select value from jsonb_array_elements(p_schedule) loop
  v_date:=(v_item->>'due_date')::date;v_amount:=round((v_item->>'amount')::numeric,2);
  if v_date is null or v_date<s.created_at::date or v_amount<=0 then raise exception 'تاريخ أو مبلغ قسط غير صالح' using errcode='22023';end if;
  v_n:=v_n+1;
  insert into public.sale_installments(sale_id,installment_number,due_date,amount,created_by) values(p_sale_id,v_n,v_date,v_amount,(select auth.uid()));
 end loop;
 return v_n;
end $$;

create or replace function private.record_sale_installment_payment(p_installment_id uuid,p_amount numeric,p_method text,p_reference text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare i public.sale_installments%rowtype;v_due numeric(14,2);v_result jsonb;v_paid numeric(14,2);
begin
 if not public.can_manage_sales() then raise exception 'غير مصرح بتحصيل القسط' using errcode='42501';end if;
 select * into i from public.sale_installments where id=p_installment_id for update;if not found or i.status='cancelled' then raise exception 'القسط غير موجود أو ملغي' using errcode='P0002';end if;
 v_due:=i.amount-i.paid_amount;if p_amount is null or p_amount<=0 or p_amount>v_due then raise exception 'مبلغ التحصيل يتجاوز رصيد القسط' using errcode='23514';end if;
 v_result:=public.record_sale_payment(i.sale_id,p_amount,p_method,p_reference);
 v_paid:=i.paid_amount+p_amount;
 update public.sale_installments set paid_amount=v_paid,status=case when v_paid>=amount then 'paid' when v_paid>0 then 'partial' else 'pending' end where id=i.id;
 return jsonb_build_object('installment_id',i.id,'paid_amount',v_paid,'remaining',i.amount-v_paid,'sale_payment',v_result);
end $$;

create or replace function public.create_sales_quotation(uuid,text,text,date,text,jsonb) returns uuid language sql security invoker set search_path='' as $$ select private.create_sales_quotation($1,$2,$3,$4,$5,$6) $$;
create or replace function public.update_sales_quotation_status(uuid,text) returns void language sql security invoker set search_path='' as $$ select private.update_sales_quotation_status($1,$2) $$;
create or replace function public.convert_sales_quotation(uuid,numeric default 0,text default 'cash',text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.convert_sales_quotation($1,$2,$3,$4) $$;
create or replace function public.create_sale_installment_schedule(uuid,jsonb) returns integer language sql security invoker set search_path='' as $$ select private.create_sale_installment_schedule($1,$2) $$;
create or replace function public.record_sale_installment_payment(uuid,numeric,text,text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.record_sale_installment_payment($1,$2,$3,$4) $$;
do $$ declare sig text;begin for sig in select unnest(array[
'public.create_sales_quotation(uuid,text,text,date,text,jsonb)','public.update_sales_quotation_status(uuid,text)',
'public.convert_sales_quotation(uuid,numeric,text,text)','public.create_sale_installment_schedule(uuid,jsonb)',
'public.record_sale_installment_payment(uuid,numeric,text,text)'
]) loop execute format('revoke all on function %s from public,anon',sig);execute format('grant execute on function %s to authenticated',sig);end loop;end $$;

