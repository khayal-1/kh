create table public.sale_return_item_units (
  id uuid primary key default gen_random_uuid(),
  sale_return_item_id uuid not null references public.sale_return_items(id) on delete restrict,
  sale_item_id uuid not null references public.sale_items(id) on delete restrict,
  motorcycle_unit_id uuid not null references public.motorcycle_units(id) on delete restrict,
  vin_snapshot text not null,
  engine_number_snapshot text,
  unit_cost numeric(14,2) check (unit_cost is null or unit_cost >= 0),
  created_at timestamptz not null default now(),
  constraint sale_return_item_units_sale_event_unit_key unique (sale_item_id,motorcycle_unit_id)
);

create index sale_return_item_units_return_item_idx
  on public.sale_return_item_units(sale_return_item_id);
create index sale_return_item_units_motorcycle_unit_idx
  on public.sale_return_item_units(motorcycle_unit_id);

alter table public.sale_return_item_units enable row level security;
revoke all on table public.sale_return_item_units from public, anon, authenticated;

create or replace function private.bind_sale_return_item_units()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_linked_count integer;
  v_picked integer := 0;
  v_unit record;
begin
  select count(*)::integer
    into v_linked_count
    from public.sale_item_units
   where sale_item_id = new.sale_item_id;

  if v_linked_count = 0 then
    return new;
  end if;

  for v_unit in
    select u.id, u.vin, u.engine_number,
           coalesce(siu.unit_cost, u.unit_cost, si.unit_cost) as unit_cost
      from public.sale_item_units siu
      join public.motorcycle_units u on u.id = siu.motorcycle_unit_id
      join public.sale_items si on si.id = siu.sale_item_id
     where siu.sale_item_id = new.sale_item_id
       and u.sale_item_id = new.sale_item_id
       and u.unit_status = 'sold'
       and not exists (
         select 1
           from public.sale_return_item_units prior
          where prior.sale_item_id = new.sale_item_id
            and prior.motorcycle_unit_id = u.id
       )
     order by u.registered_at desc, u.id desc
     limit new.quantity
     for update of u skip locked
  loop
    insert into public.sale_return_item_units(
      sale_return_item_id, sale_item_id, motorcycle_unit_id,
      vin_snapshot, engine_number_snapshot, unit_cost
    ) values (
      new.id, new.sale_item_id, v_unit.id,
      v_unit.vin, v_unit.engine_number, v_unit.unit_cost
    );
    v_picked := v_picked + 1;
  end loop;

  if v_picked <> new.quantity then
    raise exception 'عدد الوحدات المرتبطة بالفاتورة لا يكفي للمرتجع؛ لا يمكن إعادة نفس الشاسيه مرتين'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

revoke all on function private.bind_sale_return_item_units() from public, anon, authenticated;

drop trigger if exists sale_return_items_bind_physical_units on public.sale_return_items;
create trigger sale_return_items_bind_physical_units
before insert on public.sale_return_items
for each row
execute function private.bind_sale_return_item_units();

create or replace function private.post_sale_return_cogs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  si public.sale_items%rowtype;
  inv uuid;
  cogs uuid;
  j uuid;
  v numeric(14,2);
  r public.sale_returns%rowtype;
  v_linked integer;
  v_updated integer;
begin
  select * into si from public.sale_items where id = new.sale_item_id;
  select * into r from public.sale_returns where id = new.sale_return_id;

  select count(*)::integer,
         coalesce(sum(coalesce(unit_cost, si.unit_cost)), 0)
    into v_linked, v
    from public.sale_return_item_units
   where sale_return_item_id = new.id;

  if new.disposition = 'restock' then
    if v_linked = 0 then
      v := coalesce(si.unit_cost, 0) * new.quantity;
    end if;

    if v > 0 then
      select id into inv from public.accounting_accounts where code = '1200' and is_active;
      select id into cogs from public.accounting_accounts where code = '5000' and is_active;
      if inv is null or cogs is null then
        raise exception 'حساب المخزون أو تكلفة البضاعة غير مهيأ؛ ألغيت عملية المرتجع'
          using errcode = '23514';
      end if;

      insert into public.journal_entries(
        entry_date, description, source_type, source_id, created_by
      ) values (
        r.created_at::date, 'إعادة تكلفة بضاعة مرتجعة', 'sale_return_cogs', new.id, r.created_by
      ) returning id into j;

      insert into public.journal_entry_lines(
        journal_entry_id, account_id, debit, credit, memo
      ) values
        (j, inv, v, 0, 'إعادة تكلفة الوحدات المرتجعة'),
        (j, cogs, 0, v, 'عكس تكلفة البضاعة المرتجعة');
    end if;
  end if;

  if v_linked > 0 then
    update public.motorcycle_units u
       set unit_status = case
             when new.disposition = 'restock' then 'available'
             else 'retired'
           end,
           sale_item_id = null
      from public.sale_return_item_units ru
     where ru.sale_return_item_id = new.id
       and ru.motorcycle_unit_id = u.id
       and u.sale_item_id = new.sale_item_id
       and u.unit_status = 'sold';

    get diagnostics v_updated = row_count;
    if v_updated <> v_linked then
      raise exception 'تعذر تحديث حالة كل وحدات الشاسيه المرتجعة؛ ألغيت العملية بالكامل'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.post_sale_return_cogs() from public, anon, authenticated;
