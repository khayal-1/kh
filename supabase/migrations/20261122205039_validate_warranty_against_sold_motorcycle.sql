-- Source recovered from the applied production migration ledger.
CREATE OR REPLACE FUNCTION private.create_warranty(p_motorcycle_id uuid, p_sale_id uuid, p_customer_id uuid, p_customer_name text, p_phone text, p_start date, p_end date, p_terms text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
 if not private.can_manage_finance() and not public.has_employee_permission('catalog_manage') then raise exception 'غير مصرح بإدارة الضمان' using errcode='42501';end if;
 if p_motorcycle_id is null or nullif(btrim(coalesce(p_customer_name,'')),'') is null or nullif(btrim(coalesce(p_phone,'')),'') is null or p_start is null or p_end is null or p_end<p_start then raise exception 'بيانات الضمان غير صحيحة' using errcode='22023';end if;
 if p_sale_id is not null and not exists(select 1 from public.sales s join public.sale_items si on si.sale_id=s.id where s.id=p_sale_id and s.status='posted' and si.motorcycle_id=p_motorcycle_id) then raise exception 'يجب أن تحتوي فاتورة البيع على طراز الدراجة نفسها قبل إصدار الضمان' using errcode='22023';end if;
 insert into public.warranties(motorcycle_id,sale_id,customer_id,customer_name,customer_phone,start_date,end_date,terms,created_by) values(p_motorcycle_id,p_sale_id,p_customer_id,btrim(p_customer_name),btrim(p_phone),p_start,p_end,nullif(btrim(coalesce(p_terms,'')),''),(select auth.uid())) returning id into v_id;return v_id;
end $function$
;
