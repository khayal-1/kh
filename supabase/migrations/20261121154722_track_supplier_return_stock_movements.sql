drop sequence if exists public.supplier_return_number_seq;

create or replace function public.record_motorcycle_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_source text := coalesce(current_setting('ekm.stock_movement_source',true),'');
  v_reference text := nullif(current_setting('ekm.stock_movement_reference',true),'');
begin
  if tg_op='INSERT' then
    if new.stock>0 then
      insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,notes,created_by)
      values(new.id,'opening',new.stock,'رصيد افتتاحي عند إضافة الدراجة',(select auth.uid()));
    end if;
  elsif new.stock is distinct from old.stock and v_source<>'sale' then
    insert into public.stock_movements(motorcycle_id,movement_type,quantity_delta,reference_id,notes,created_by)
    values(
      new.id,
      case
        when v_source='purchase_receipt' then 'purchase_receipt'
        when v_source='purchase_return' then 'purchase_return'
        else 'adjustment'
      end,
      new.stock-old.stock,
      case when v_source in ('purchase_receipt','purchase_return') and v_reference is not null then v_reference::uuid else null end,
      case
        when v_source='purchase_receipt' then 'استلام توريد'
        when v_source='purchase_return' then 'مرتجع إلى المورد'
        else 'تسوية مخزون من تعديل بيانات الدراجة'
      end,
      (select auth.uid())
    );
  end if;
  return new;
end;
$function$;
