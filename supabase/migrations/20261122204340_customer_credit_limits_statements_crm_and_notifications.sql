-- Source recovered from the applied production migration ledger.
alter table public.clients add column if not exists credit_limit numeric(14,2) check(credit_limit is null or credit_limit>=0);
alter table public.clients add column if not exists customer_segment text not null default 'standard' check(customer_segment in ('standard','vip','wholesale','restricted'));
alter table public.clients add column if not exists lead_source text;
alter table public.clients add column if not exists marketing_consent boolean not null default false;
alter table public.clients add column if not exists consent_updated_at timestamptz;

create table if not exists public.customer_interactions(
 id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.clients(id) on delete restrict,
 interaction_type text not null check(interaction_type in ('call','whatsapp','visit','email','complaint','follow_up','other')),
 subject text not null,notes text,interaction_at timestamptz not null default now(),next_follow_up timestamptz,
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now()
);
create index if not exists customer_interactions_customer_date_idx on public.customer_interactions(customer_id,interaction_at desc);
create table if not exists public.customer_complaints(
 id uuid primary key default gen_random_uuid(),complaint_number bigint generated always as identity unique,
 customer_id uuid references public.clients(id) on delete restrict,customer_name text not null,customer_phone text,
 subject text not null,description text not null,priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
 status text not null default 'open' check(status in ('open','in_progress','resolved','closed')),
 assigned_to uuid references auth.users(id) on delete restrict,resolution text,resolved_at timestamptz,
 created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now()
);
create index if not exists customer_complaints_status_idx on public.customer_complaints(status,priority,created_at desc);
create table if not exists public.internal_notifications(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 title text not null,body text,category text not null default 'general',read_at timestamptz,
 created_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now()
);
create index if not exists internal_notifications_user_read_idx on public.internal_notifications(user_id,read_at,created_at desc);

alter table public.customer_interactions enable row level security;
alter table public.customer_complaints enable row level security;
alter table public.internal_notifications enable row level security;
revoke all on public.customer_interactions,public.customer_complaints,public.internal_notifications from anon,authenticated;
grant select on public.customer_interactions,public.customer_complaints,public.internal_notifications to authenticated;
create policy customer_interactions_read on public.customer_interactions for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('customer_data_view') or public.has_employee_permission('customer_data_manage'));
create policy customer_complaints_read on public.customer_complaints for select to authenticated using(public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('customer_data_view') or public.has_employee_permission('customer_data_manage'));
create policy internal_notifications_read on public.internal_notifications for select to authenticated using(user_id=(select auth.uid()) or public.has_any_role(array['manager','owner','admin']::public.app_role[]));

create or replace function private.set_customer_profile_meta(p_customer_id uuid,p_credit_limit numeric,p_segment text,p_lead_source text,p_marketing_consent boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.can_manage_finance() and not public.has_employee_permission('customer_data_manage') and not public.has_employee_permission('sales_manage') then raise exception 'غير مصرح بتعديل ملف العميل' using errcode='42501';end if;
 if p_credit_limit is not null and p_credit_limit<0 or p_segment not in ('standard','vip','wholesale','restricted') then raise exception 'بيانات ملف العميل غير صحيحة' using errcode='22023';end if;
 update public.clients set credit_limit=p_credit_limit,customer_segment=p_segment,lead_source=nullif(btrim(coalesce(p_lead_source,'')),''),marketing_consent=coalesce(p_marketing_consent,false),consent_updated_at=now()
 where id=p_customer_id;
 if not found then raise exception 'العميل غير موجود' using errcode='P0002';end if;
end $$;

create or replace function private.guard_customer_credit_limit()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_limit numeric(14,2);v_existing numeric(14,2);v_new_due numeric(14,2);
begin
 if new.customer_id is null then return new;end if;
 select credit_limit into v_limit from public.clients where id=new.customer_id;
 if v_limit is null then return new;end if;
 select coalesce(sum(greatest(0,s.total-coalesce(s.amount_paid,0)-coalesce(s.credit_applied,0))),0) into v_existing
 from public.sales s where s.customer_id=new.customer_id and s.status='posted';
 v_new_due:=greatest(0,new.total-coalesce(new.amount_paid,0)-coalesce(new.credit_applied,0));
 if v_existing+v_new_due>v_limit then raise exception 'تم تجاوز الحد الائتماني للعميل. الرصيد الحالي %، والعملية الجديدة %، والحد %',v_existing,v_new_due,v_limit using errcode='23514';end if;
 return new;
end $$;
drop trigger if exists sales_credit_limit_guard on public.sales;
create trigger sales_credit_limit_guard before insert on public.sales for each row execute function private.guard_customer_credit_limit();

create or replace function private.create_customer_interaction(p_customer_id uuid,p_type text,p_subject text,p_notes text,p_follow_up timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.has_any_role(array['manager','owner','admin']::public.app_role[]) and not public.has_employee_permission('customer_data_manage') then raise exception 'غير مصرح بتسجيل تفاعل العميل' using errcode='42501';end if;
 if p_type not in ('call','whatsapp','visit','email','complaint','follow_up','other') or nullif(btrim(coalesce(p_subject,'')),'') is null then raise exception 'بيانات التفاعل غير صحيحة' using errcode='22023';end if;
 insert into public.customer_interactions(customer_id,interaction_type,subject,notes,next_follow_up,created_by)
 values(p_customer_id,p_type,btrim(p_subject),nullif(btrim(coalesce(p_notes,'')),''),p_follow_up,(select auth.uid())) returning id into v_id;return v_id;
end $$;

create or replace function private.create_customer_complaint(p_customer_id uuid,p_name text,p_phone text,p_subject text,p_description text,p_priority text,p_assigned_to uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.has_any_role(array['manager','owner','admin']::public.app_role[]) and not public.has_employee_permission('customer_data_manage') then raise exception 'غير مصرح بتسجيل شكاوى العملاء' using errcode='42501';end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null or nullif(btrim(coalesce(p_subject,'')),'') is null or nullif(btrim(coalesce(p_description,'')),'') is null or p_priority not in ('low','normal','high','urgent') then raise exception 'بيانات الشكوى غير صحيحة' using errcode='22023';end if;
 insert into public.customer_complaints(customer_id,customer_name,customer_phone,subject,description,priority,assigned_to,created_by)
 values(p_customer_id,btrim(p_name),nullif(btrim(coalesce(p_phone,'')),''),btrim(p_subject),btrim(p_description),p_priority,p_assigned_to,(select auth.uid())) returning id into v_id;return v_id;
end $$;

create or replace function private.update_customer_complaint(p_id uuid,p_status text,p_resolution text,p_assigned_to uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_any_role(array['manager','owner','admin']::public.app_role[]) and not public.has_employee_permission('customer_data_manage') then raise exception 'غير مصرح بتحديث الشكاوى' using errcode='42501';end if;
 if p_status not in ('open','in_progress','resolved','closed') then raise exception 'حالة الشكوى غير صحيحة' using errcode='22023';end if;
 update public.customer_complaints set status=p_status,resolution=coalesce(nullif(btrim(coalesce(p_resolution,'')),''),resolution),assigned_to=coalesce(p_assigned_to,assigned_to),resolved_at=case when p_status in ('resolved','closed') then now() else null end where id=p_id;
 if not found then raise exception 'الشكوى غير موجودة' using errcode='P0002';end if;
end $$;

create or replace function private.create_internal_notification(p_user_id uuid,p_title text,p_body text,p_category text default 'general')
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.has_any_role(array['manager','owner','admin']::public.app_role[]) and not public.has_employee_permission('customer_data_manage') and not public.has_employee_permission('finance_manage') then raise exception 'غير مصرح بإرسال إشعار داخلي' using errcode='42501';end if;
 if p_user_id is null or nullif(btrim(coalesce(p_title,'')),'') is null then raise exception 'بيانات الإشعار غير صحيحة' using errcode='22023';end if;
 insert into public.internal_notifications(user_id,title,body,category,created_by) values(p_user_id,btrim(p_title),nullif(btrim(coalesce(p_body,'')),''),coalesce(nullif(p_category,''),'general'),(select auth.uid())) returning id into v_id;return v_id;
end $$;
create or replace function private.mark_internal_notification_read(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin update public.internal_notifications set read_at=now() where id=p_id and user_id=(select auth.uid());if not found then raise exception 'الإشعار غير موجود' using errcode='P0002';end if;end $$;

create or replace view public.customer_statement
with (security_invoker=true) as
select s.customer_id,s.created_at::date as entry_date,'invoice'::text as entry_type,s.invoice_number::text as document_number,s.total::numeric(14,2) as debit,0::numeric(14,2) as credit
from public.sales s where s.customer_id is not null and s.status='posted'
union all
select s.customer_id,p.paid_at::date,'payment',coalesce(p.reference,'دفعة بيع')::text,0::numeric(14,2),p.amount::numeric(14,2)
from public.payments p join public.sales s on s.id=p.sale_id where s.customer_id is not null
union all
select r.customer_id,r.created_at::date,'sale_return',r.return_number::text,0::numeric(14,2),r.total_amount::numeric(14,2)
from public.sale_returns r where r.customer_id is not null
union all
select t.customer_id,t.created_at::date,'credit_applied','رصيد دائن',0::numeric(14,2),abs(t.amount)::numeric(14,2)
from public.customer_credit_transactions t where t.transaction_type='invoice_credit_application';

grant select on public.customer_statement to authenticated;
create policy payments_read_own_customer on public.payments for select to authenticated using(
 exists(select 1 from public.sales s join public.clients c on c.id=s.customer_id where s.id=payments.sale_id and c.user_id=(select auth.uid()))
);
create policy sale_returns_read_own_customer on public.sale_returns for select to authenticated using(
 exists(select 1 from public.clients c where c.id=sale_returns.customer_id and c.user_id=(select auth.uid()))
);
create policy customer_credit_transactions_read_own_customer on public.customer_credit_transactions for select to authenticated using(
 exists(select 1 from public.clients c where c.id=customer_credit_transactions.customer_id and c.user_id=(select auth.uid()))
);

create or replace function public.set_customer_profile_meta(uuid,numeric,text,text,boolean) returns void language sql security invoker set search_path='' as $$ select private.set_customer_profile_meta($1,$2,$3,$4,$5) $$;
create or replace function public.create_customer_interaction(uuid,text,text,text,timestamptz default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_customer_interaction($1,$2,$3,$4,$5) $$;
create or replace function public.create_customer_complaint(uuid,text,text,text,text,text,uuid default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_customer_complaint($1,$2,$3,$4,$5,$6,$7) $$;
create or replace function public.update_customer_complaint(uuid,text,text,uuid default null) returns void language sql security invoker set search_path='' as $$ select private.update_customer_complaint($1,$2,$3,$4) $$;
create or replace function public.create_internal_notification(uuid,text,text,text default 'general') returns uuid language sql security invoker set search_path='' as $$ select private.create_internal_notification($1,$2,$3,$4) $$;
create or replace function public.mark_internal_notification_read(uuid) returns void language sql security invoker set search_path='' as $$ select private.mark_internal_notification_read($1) $$;
do $$ declare sig text;begin for sig in select unnest(array[
'public.set_customer_profile_meta(uuid,numeric,text,text,boolean)','public.create_customer_interaction(uuid,text,text,text,timestamptz)',
'public.create_customer_complaint(uuid,text,text,text,text,text,uuid)','public.update_customer_complaint(uuid,text,text,uuid)',
'public.create_internal_notification(uuid,text,text,text)','public.mark_internal_notification_read(uuid)'
]) loop execute format('revoke all on function %s from public,anon',sig);execute format('grant execute on function %s to authenticated',sig);end loop;end $$;

