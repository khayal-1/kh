-- Private, target-bound documents for physical units and supplier bills.
-- Existing model photos and supplier records are not changed.
begin;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('motorcycle-documents','motorcycle-documents',false,15728640,
        array['application/pdf','image/jpeg','image/png','image/webp']::text[])
on conflict (id) do nothing;

create table if not exists public.motorcycle_documents (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('unit','supplier_bill')),
  motorcycle_unit_id uuid references public.motorcycle_units(id) on delete restrict,
  supplier_bill_id uuid references public.supplier_bills(id) on delete restrict,
  storage_path text not null unique,
  file_name text not null check (length(btrim(file_name)) between 1 and 180),
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png','image/webp')),
  file_size bigint not null check (file_size between 1 and 15728640),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint motorcycle_documents_one_target check (
    (target_type='unit' and motorcycle_unit_id is not null and supplier_bill_id is null
      and storage_path = 'units/' || motorcycle_unit_id::text || '/' || id::text || '.' ||
        case mime_type when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end)
    or
    (target_type='supplier_bill' and supplier_bill_id is not null and motorcycle_unit_id is null
      and storage_path = 'supplier-bills/' || supplier_bill_id::text || '/' || id::text || '.' ||
        case mime_type when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' end)
  )
);
create index if not exists motorcycle_documents_unit_created_idx
  on public.motorcycle_documents(motorcycle_unit_id,created_at) where motorcycle_unit_id is not null;
create index if not exists motorcycle_documents_bill_created_idx
  on public.motorcycle_documents(supplier_bill_id,created_at) where supplier_bill_id is not null;

create or replace function private.can_access_motorcycle_document_target(p_target_type text,p_target_id uuid,p_write boolean default false)
returns boolean
language plpgsql stable security definer set search_path=''
as $$
begin
  if (select auth.uid()) is null or p_target_id is null then return false; end if;
  if p_target_type='unit' then
    if not exists(select 1 from public.motorcycle_units u where u.id=p_target_id) then return false; end if;
    if p_write then
      return public.has_any_role(array['manager','owner','admin']::public.app_role[])
        or public.has_employee_permission('catalog_manage');
    end if;
    return public.has_any_role(array['manager','owner','admin']::public.app_role[])
      or public.has_employee_permission('catalog_manage')
      or public.has_employee_permission('finance_manage');
  elsif p_target_type='supplier_bill' then
    if not exists(select 1 from public.supplier_bills b where b.id=p_target_id) then return false; end if;
    return public.can_manage_purchasing();
  end if;
  return false;
end;
$$;
revoke all on function private.can_access_motorcycle_document_target(text,uuid,boolean) from public,anon;
grant execute on function private.can_access_motorcycle_document_target(text,uuid,boolean) to authenticated;

alter table public.motorcycle_documents enable row level security;
revoke all on public.motorcycle_documents from public,anon,authenticated;
grant select,insert,delete on public.motorcycle_documents to authenticated;
create policy motorcycle_documents_read on public.motorcycle_documents
  for select to authenticated using (
    private.can_access_motorcycle_document_target(target_type,coalesce(motorcycle_unit_id,supplier_bill_id),false)
  );
create policy motorcycle_documents_insert on public.motorcycle_documents
  for insert to authenticated with check (
    created_by=(select auth.uid())
    and private.can_access_motorcycle_document_target(target_type,coalesce(motorcycle_unit_id,supplier_bill_id),true)
  );
create policy motorcycle_documents_delete on public.motorcycle_documents
  for delete to authenticated using (
    created_by=(select auth.uid())
    and private.can_access_motorcycle_document_target(target_type,coalesce(motorcycle_unit_id,supplier_bill_id),true)
  );

create policy motorcycle_documents_objects_read on storage.objects
  for select to authenticated using (
    bucket_id='motorcycle-documents'
    and exists(select 1 from public.motorcycle_documents d where d.storage_path=name
      and private.can_access_motorcycle_document_target(d.target_type,coalesce(d.motorcycle_unit_id,d.supplier_bill_id),false))
  );
create policy motorcycle_documents_objects_insert on storage.objects
  for insert to authenticated with check (
    bucket_id='motorcycle-documents'
    and exists(select 1 from public.motorcycle_documents d where d.storage_path=name
      and d.created_by=(select auth.uid())
      and private.can_access_motorcycle_document_target(d.target_type,coalesce(d.motorcycle_unit_id,d.supplier_bill_id),true))
  );
create policy motorcycle_documents_objects_delete on storage.objects
  for delete to authenticated using (
    bucket_id='motorcycle-documents'
    and exists(select 1 from public.motorcycle_documents d where d.storage_path=name
      and d.created_by=(select auth.uid())
      and private.can_access_motorcycle_document_target(d.target_type,coalesce(d.motorcycle_unit_id,d.supplier_bill_id),true))
  );

commit;
