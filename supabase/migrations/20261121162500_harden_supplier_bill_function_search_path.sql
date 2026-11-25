create or replace function public.create_supplier_bill(
 p_supplier_id uuid,
 p_bill_number text,
 p_total_amount numeric,
 p_bill_date date default current_date,
 p_due_date date default null,
 p_purchase_order_id uuid default null,
 p_notes text default null
)
returns public.supplier_bills
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_bill public.supplier_bills;
begin
  if (select auth.uid()) is null or not public.can_manage_purchasing() then
    raise exception 'غير مصرح بإدارة فواتير الموردين' using errcode = '42501';
  end if;
  if p_supplier_id is null or nullif(btrim(p_bill_number),'') is null
     or p_total_amount is null or p_total_amount <= 0 then
    raise exception 'بيانات فاتورة المورد غير مكتملة أو غير صحيحة' using errcode = '22023';
  end if;
  if p_bill_date is null or (p_due_date is not null and p_due_date < p_bill_date) then
    raise exception 'تاريخ الاستحقاق لا يمكن أن يسبق تاريخ الفاتورة' using errcode = '22023';
  end if;
  if not exists(select 1 from public.suppliers s where s.id=p_supplier_id and s.is_active) then
    raise exception 'المورد غير موجود أو موقوف' using errcode = '23503';
  end if;
  if p_purchase_order_id is not null and not exists(
    select 1 from public.purchase_orders po where po.id=p_purchase_order_id and po.supplier_id=p_supplier_id and po.status <> 'cancelled'
  ) then
    raise exception 'أمر التوريد لا يتبع هذا المورد أو أنه ملغى' using errcode = '23503';
  end if;
  insert into public.supplier_bills(bill_number,supplier_id,purchase_order_id,bill_date,due_date,total_amount,notes,created_by)
  values (btrim(p_bill_number),p_supplier_id,p_purchase_order_id,p_bill_date,p_due_date,round(p_total_amount,2),nullif(btrim(p_notes),''),(select auth.uid()))
  returning * into v_bill;
  return v_bill;
end;
$function$;
revoke all on function public.create_supplier_bill(uuid,text,numeric,date,date,uuid,text) from public,anon;
grant execute on function public.create_supplier_bill(uuid,text,numeric,date,date,uuid,text) to authenticated,postgres;