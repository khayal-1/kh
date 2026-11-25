begin;

create table if not exists public.sale_item_units (
  id uuid primary key default gen_random_uuid(),
  sale_item_id uuid not null references public.sale_items(id) on delete restrict,
  motorcycle_unit_id uuid not null references public.motorcycle_units(id) on delete restrict,
  vin_snapshot text not null,
  engine_number_snapshot text,
  unit_cost numeric(14,2) check(unit_cost is null or unit_cost>=0),
  created_at timestamptz not null default now(),
  unique(sale_item_id,motorcycle_unit_id)
);
create index if not exists sale_item_units_sale_item_idx on public.sale_item_units(sale_item_id);
alter table public.sale_item_units enable row level security;
revoke all on public.sale_item_units from anon,authenticated;
grant select on public.sale_item_units to authenticated;
create policy sale_item_units_read on public.sale_item_units
  for select to authenticated using (public.can_manage_sales());

-- Backfill the historical identity for units already linked to a sale item.
insert into public.sale_item_units(
  sale_item_id,motorcycle_unit_id,vin_snapshot,engine_number_snapshot,unit_cost
)
select u.sale_item_id,u.id,u.vin,u.engine_number,u.unit_cost
from public.motorcycle_units u
where u.sale_item_id is not null
on conflict(sale_item_id,motorcycle_unit_id) do nothing;

create or replace function private.prevent_sold_unit_identity_edits()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if exists(select 1 from public.sale_item_units where motorcycle_unit_id=old.id)
     and (new.vin is distinct from old.vin or new.engine_number is distinct from old.engine_number) then
    raise exception 'لا يمكن تغيير رقم الشاسيه أو رقم الموتور بعد ربط الوحدة بفاتورة بيع؛ احتفظ ببيانات البيع التاريخية كما هي'
      using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function private.prevent_sold_unit_identity_edits() from public,anon,authenticated;
drop trigger if exists motorcycle_units_identity_immutable on public.motorcycle_units;
create trigger motorcycle_units_identity_immutable
before update of vin,engine_number on public.motorcycle_units
for each row execute function private.prevent_sold_unit_identity_edits();

create or replace function private.post_sale_item_cogs()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  c uuid;
  i uuid;
  j uuid;
  v_cost_total numeric(14,2);
  v_unit_id uuid;
  v_updated integer:=0;
  v_explicit_unit text:=nullif(current_setting('ekm.sale_unit_id',true),'');
begin
  if v_explicit_unit is not null then
    begin v_unit_id:=v_explicit_unit::uuid;
    exception when others then raise exception 'معرّف الوحدة المحددة غير صالح' using errcode='22023'; end;
    update public.motorcycle_units
       set unit_status='sold',sale_item_id=new.id
     where id=v_unit_id and motorcycle_id=new.motorcycle_id and unit_status='available';
    get diagnostics v_updated=row_count;
    if v_updated<>new.quantity then
      raise exception 'الوحدة المحددة لم تعد متاحة أو لا تطابق طراز الدراجة؛ ألغيت العملية بالكامل'
        using errcode='23514';
    end if;
  else
    with picked as (
      select id from public.motorcycle_units
       where motorcycle_id=new.motorcycle_id and unit_status='available'
       order by registered_at,id limit new.quantity for update skip locked
    )
    update public.motorcycle_units u
       set unit_status='sold',sale_item_id=new.id
      from picked where u.id=picked.id;
    get diagnostics v_updated=row_count;
    if v_updated<>new.quantity then
      raise exception 'لا توجد وحدة مسجلة متاحة لكل كمية البيع؛ لم يتم اعتماد الفاتورة'
        using errcode='23514';
    end if;
  end if;

  insert into public.sale_item_units(
    sale_item_id,motorcycle_unit_id,vin_snapshot,engine_number_snapshot,unit_cost
  )
  select new.id,u.id,u.vin,u.engine_number,coalesce(u.unit_cost,new.unit_cost)
    from public.motorcycle_units u
   where u.sale_item_id=new.id
  on conflict(sale_item_id,motorcycle_unit_id) do nothing;

  select coalesce(sum(siu.unit_cost),new.unit_cost*new.quantity)
    into v_cost_total
    from public.sale_item_units siu
   where siu.sale_item_id=new.id;
  if v_cost_total>0 then
    select id into c from public.accounting_accounts where code='5000' and is_active;
    select id into i from public.accounting_accounts where code='1200' and is_active;
    if c is null or i is null then
      raise exception 'حسابات تكلفة البضاعة أو المخزون غير مهيأة؛ ألغيت عملية البيع'
        using errcode='23514';
    end if;
    insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
    select s.created_at::date,'تكلفة بضاعة فاتورة '||s.invoice_number,'sale_cogs',new.id,s.created_by
      from public.sales s where s.id=new.sale_id returning id into j;
    insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
    values(j,c,v_cost_total,0,'تكلفة الوحدات المباعة'),(j,i,0,v_cost_total,'تخفيض قيمة المخزون');
  end if;

  update public.sales s
     set costing_status=case when exists(
       select 1 from public.sale_items si where si.sale_id=new.sale_id and si.unit_cost is null
     ) then 'incomplete' else 'complete' end
   where s.id=new.sale_id;
  return new;
end;
$$;

create or replace function private.post_sale_return_cogs()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  si public.sale_items%rowtype;
  inv uuid;
  cogs uuid;
  j uuid;
  v numeric(14,2);
  r public.sale_returns%rowtype;
begin
  if new.disposition<>'restock' then return new; end if;
  select * into si from public.sale_items where id=new.sale_item_id;
  select * into r from public.sale_returns where id=new.sale_return_id;
  select coalesce(sum(x.unit_cost),si.unit_cost*new.quantity) into v
  from (
    select siu.unit_cost
    from public.sale_item_units siu
    join public.motorcycle_units u on u.id=siu.motorcycle_unit_id
    where siu.sale_item_id=new.sale_item_id and u.unit_status='sold'
    order by u.registered_at desc,u.id desc
    limit new.quantity
  ) x;
  if v>0 then
    select id into inv from public.accounting_accounts where code='1200' and is_active;
    select id into cogs from public.accounting_accounts where code='5000' and is_active;
    insert into public.journal_entries(entry_date,description,source_type,source_id,created_by)
    values(r.created_at::date,'إعادة تكلفة بضاعة مرتجعة','sale_return_cogs',new.id,r.created_by)
    returning id into j;
    insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
    values(j,inv,v,0,'إعادة تكلفة الوحدات المرتجعة'),(j,cogs,0,v,'عكس تكلفة البضاعة المرتجعة');
  end if;
  with picked as (
    select id from public.motorcycle_units
     where sale_item_id=new.sale_item_id and unit_status='sold'
     order by registered_at desc,id desc
     limit new.quantity for update skip locked
  )
  update public.motorcycle_units u
     set unit_status='available',sale_item_id=null
    from picked where u.id=picked.id;
  return new;
end;
$$;

create or replace function public.get_sale_invoice(p_sale_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  s public.sales%rowtype;
  v_items jsonb;
  v_payments jsonb;
  v_returns jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'يجب تسجيل الدخول لعرض الفاتورة' using errcode='42501';
  end if;
  select * into s from public.sales where id=p_sale_id;
  if not found then raise exception 'الفاتورة غير موجودة' using errcode='P0002'; end if;
  if not public.can_manage_sales()
     and not exists(select 1 from public.clients c where c.id=s.customer_id and c.user_id=(select auth.uid())) then
    raise exception 'غير مصرح بعرض هذه الفاتورة' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'sale_item_id',si.id,'motorcycle_name',si.motorcycle_name,'model_year',si.model_year,
    'quantity',si.quantity,'unit_price',si.unit_price,'line_total',si.line_total,
    'units',coalesce((
      select jsonb_agg(jsonb_build_object(
        'unit_id',siu.motorcycle_unit_id,'vin',siu.vin_snapshot,
        'engine_number',siu.engine_number_snapshot,'unit_cost',siu.unit_cost
      ) order by siu.created_at,siu.id)
      from public.sale_item_units siu where siu.sale_item_id=si.id
    ),'[]'::jsonb)
  ) order by si.created_at,si.id),'[]'::jsonb)
  into v_items from public.sale_items si where si.sale_id=s.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'amount',p.amount,'method',p.method,'reference',p.reference,'paid_at',p.paid_at
  ) order by p.paid_at,p.id),'[]'::jsonb)
  into v_payments from public.payments p where p.sale_id=s.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'return_number',r.return_number,'total_amount',r.total_amount,'created_at',r.created_at,'notes',r.notes
  ) order by r.created_at,r.id),'[]'::jsonb)
  into v_returns from public.sale_returns r where r.sale_id=s.id;

  return jsonb_build_object(
    'id',s.id,'invoice_number',s.invoice_number,'customer_name',s.customer_name,
    'customer_phone',s.customer_phone,'created_at',s.created_at,'status',s.status,
    'subtotal',s.subtotal,'discount',s.discount,'total',s.total,
    'amount_paid',s.amount_paid,'credit_applied',s.credit_applied,
    'payment_status',s.payment_status,'notes',s.notes,
    'items',v_items,'payments',v_payments,'returns',v_returns
  );
end;
$$;
revoke all on function public.get_sale_invoice(uuid) from public,anon;
grant execute on function public.get_sale_invoice(uuid) to authenticated;

commit;
