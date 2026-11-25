-- Applied migration source recovered from Supabase migration ledger.

create table if not exists public.sale_deliveries(
 id uuid primary key default gen_random_uuid(),
 delivery_number bigint generated always as identity unique,
 sale_id uuid not null unique references public.sales(id) on delete restrict,
 delivered_at timestamptz not null default now(),
 recipient_name text not null,
 recipient_phone text,
 odometer_reading integer check(odometer_reading is null or odometer_reading>=0),
 accessories text,
 condition_notes text,
 notes text,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);
create index if not exists sale_deliveries_delivered_at_idx on public.sale_deliveries(delivered_at desc);
alter table public.sale_deliveries enable row level security;
revoke all on public.sale_deliveries from anon,authenticated;
grant select on public.sale_deliveries to authenticated;
create policy sale_deliveries_read_staff on public.sale_deliveries for select to authenticated using(public.can_manage_sales());

create or replace function private.create_sale_delivery(
 p_sale_id uuid,p_delivered_at timestamptz,p_recipient_name text,p_recipient_phone text,
 p_odometer_reading integer,p_accessories text,p_condition_notes text,p_notes text
) returns uuid language plpgsql security definer set search_path='' as $function$
declare v_id uuid;v_sale public.sales%rowtype;
begin
 if not public.can_manage_sales() then raise exception 'غير مصرح بتسجيل تسليم الدراجات' using errcode='42501';end if;
 if p_sale_id is null or nullif(btrim(coalesce(p_recipient_name,'')),'') is null or (p_odometer_reading is not null and p_odometer_reading<0) then
  raise exception 'بيانات محضر التسليم غير صحيحة' using errcode='22023';
 end if;
 select * into v_sale from public.sales where id=p_sale_id for update;
 if not found or v_sale.status<>'posted' then raise exception 'فاتورة البيع غير موجودة أو غير مرحلة' using errcode='P0002';end if;
 if exists(select 1 from public.sale_deliveries where sale_id=p_sale_id) then raise exception 'تم تسجيل محضر تسليم لهذه الفاتورة بالفعل' using errcode='23505';end if;
 insert into public.sale_deliveries(sale_id,delivered_at,recipient_name,recipient_phone,odometer_reading,accessories,condition_notes,notes,created_by)
 values(p_sale_id,coalesce(p_delivered_at,now()),btrim(p_recipient_name),nullif(btrim(coalesce(p_recipient_phone,'')),''),p_odometer_reading,
 nullif(btrim(coalesce(p_accessories,'')),''),nullif(btrim(coalesce(p_condition_notes,'')),''),nullif(btrim(coalesce(p_notes,'')),''),(select auth.uid()))
 returning id into v_id;
 return v_id;
end $function$;

create or replace function public.create_sale_delivery(uuid,timestamptz,text,text,integer,text,text,text)
returns uuid language sql security invoker set search_path='' as
$function$ select private.create_sale_delivery($1,$2,$3,$4,$5,$6,$7,$8) $function$;
revoke all on function public.create_sale_delivery(uuid,timestamptz,text,text,integer,text,text,text) from public,anon;
grant execute on function public.create_sale_delivery(uuid,timestamptz,text,text,integer,text,text,text) to authenticated;
revoke all on function private.create_sale_delivery(uuid,timestamptz,text,text,integer,text,text,text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.create_sale_delivery(uuid,timestamptz,text,text,integer,text,text,text) to authenticated;

