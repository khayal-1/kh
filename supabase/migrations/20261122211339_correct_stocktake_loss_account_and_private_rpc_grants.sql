-- Applied migration source recovered from Supabase migration ledger.

insert into public.accounting_accounts(code,name,account_type,parent_code,is_system,is_active)
values('6091','عجز الجرد','expense','6000',true,true)
on conflict(code) do update set name=excluded.name,account_type=excluded.account_type,parent_code=excluded.parent_code,is_active=true;
CREATE OR REPLACE FUNCTION private.create_stocktake(p_date date, p_notes text, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid:=gen_random_uuid();v_entry uuid:=gen_random_uuid();v_item jsonb;v_bike public.motorcycles%rowtype;v_cost numeric(14,2);v_count integer;v_delta integer;
 v_inventory uuid;v_gain uuid;v_loss uuid;v_increase numeric(14,2):=0;v_decrease numeric(14,2):=0;v_line_value numeric(14,2);v_count_lines integer:=0;v_stocktake_number bigint;
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بإجراء الجرد' using errcode='42501';end if;
 if p_date is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>200 then raise exception 'بيانات الجرد غير صحيحة' using errcode='22023';end if;
 select id into v_inventory from public.accounting_accounts where code='1200' and is_active;select id into v_gain from public.accounting_accounts where code='4090' and is_active;select id into v_loss from public.accounting_accounts where code='6091' and is_active;
 if v_inventory is null or v_gain is null or v_loss is null then raise exception 'حسابات المخزون وفروق الجرد غير مهيأة' using errcode='22023';end if;
 insert into public.stocktake_batches(id,stocktake_date,notes,created_by) values(v_id,p_date,nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid())) returning stocktake_number into v_stocktake_number;
 for v_item in select value from jsonb_array_elements(p_lines) loop
  select * into v_bike from public.motorcycles where id=(v_item->>'motorcycle_id')::uuid for update;if not found then raise exception 'دراجة غير موجودة ضمن الجرد' using errcode='P0002';end if;
  v_count:=(v_item->>'counted_quantity')::integer;if v_count<0 then raise exception 'الكمية المعدودة لا يمكن أن تكون سالبة' using errcode='22023';end if;
  v_delta:=v_count-v_bike.stock;select unit_cost into v_cost from public.motorcycle_inventory_costs where motorcycle_id=v_bike.id;
  if v_delta<>0 and (v_cost is null or v_cost<=0) then raise exception 'يجب إدخال تكلفة شراء فعلية للدراجة % قبل ترحيل فرق الجرد',v_bike.name using errcode='23514';end if;
  v_line_value:=abs(v_delta)*coalesce(v_cost,0);
  insert into public.stocktake_lines(stocktake_id,motorcycle_id,expected_quantity,counted_quantity,quantity_delta,unit_cost,value_delta) values(v_id,v_bike.id,v_bike.stock,v_count,v_delta,v_cost,v_delta*coalesce(v_cost,0));
  if v_delta<>0 then
   insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by) values(v_bike.id,'adjustment',v_delta,v_id,'تسوية جرد رقم '||v_stocktake_number,(select auth.uid()));
   update public.motorcycles set stock=v_count where id=v_bike.id;
   if v_delta>0 then v_increase:=v_increase+v_line_value;else v_decrease:=v_decrease+v_line_value;end if;
  end if;
  v_count_lines:=v_count_lines+1;
 end loop;
 if v_increase+v_decrease>0 then
  insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by) values(v_entry,p_date,'تسوية جرد المخزون #'||v_stocktake_number,'stocktake',v_id,(select auth.uid()));
  if v_increase>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_inventory,v_increase,0,'زيادة مخزون حسب الجرد'),(v_entry,v_gain,0,v_increase,'فائض جرد');end if;
  if v_decrease>0 then insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo) values(v_entry,v_loss,v_decrease,0,'عجز مخزون حسب الجرد'),(v_entry,v_inventory,0,v_decrease,'تخفيض مخزون حسب الجرد');end if;
  update public.stocktake_batches set journal_entry_id=v_entry,total_increase=v_increase,total_decrease=v_decrease where id=v_id;
 end if;
 return jsonb_build_object('stocktake_id',v_id,'stocktake_number',v_stocktake_number,'lines_count',v_count_lines,'increase_value',v_increase,'decrease_value',v_decrease,'journal_entry_id',case when v_increase+v_decrease>0 then v_entry else null end);
end $function$
;
do $$ begin
 revoke all on function private.create_stocktake(date,text,jsonb) from public,anon;
 grant execute on function private.create_stocktake(date,text,jsonb) to authenticated;
 grant usage on schema private to authenticated;
end $$;

