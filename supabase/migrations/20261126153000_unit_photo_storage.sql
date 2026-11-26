-- Keep physical-unit photos separate from model reference images in photo_assets.
-- This private bucket and metadata table are additive; existing catalog imagery remains untouched.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('motorcycle-unit-photos','motorcycle-unit-photos',false,8388608,array['image/jpeg','image/png','image/webp']::text[])
on conflict (id) do nothing;

create table if not exists public.motorcycle_unit_photos (
  id uuid primary key default gen_random_uuid(),
  motorcycle_unit_id uuid not null references public.motorcycle_units(id) on delete restrict,
  storage_path text not null unique,
  is_primary boolean not null default false,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint motorcycle_unit_photos_path_matches_unit check (storage_path like ('units/' || motorcycle_unit_id::text || '/%'))
);
create index if not exists motorcycle_unit_photos_unit_created_idx
  on public.motorcycle_unit_photos(motorcycle_unit_id, created_at);
create unique index if not exists motorcycle_unit_photos_one_primary_uidx
  on public.motorcycle_unit_photos(motorcycle_unit_id) where is_primary;

alter table public.motorcycle_unit_photos enable row level security;
revoke all on public.motorcycle_unit_photos from anon, authenticated;
grant select, insert, update, delete on public.motorcycle_unit_photos to authenticated;

create policy motorcycle_unit_photos_read on public.motorcycle_unit_photos
  for select to authenticated using (
    public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('catalog_manage')
    or public.has_employee_permission('finance_manage')
  );
create policy motorcycle_unit_photos_insert on public.motorcycle_unit_photos
  for insert to authenticated with check (
    created_by=(select auth.uid())
    and (public.has_any_role(array['manager','owner','admin']::public.app_role[])
      or public.has_employee_permission('catalog_manage'))
    and exists(select 1 from public.motorcycle_units u where u.id=motorcycle_unit_id)
  );
create policy motorcycle_unit_photos_update on public.motorcycle_unit_photos
  for update to authenticated using (
    public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('catalog_manage')
  ) with check (
    public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('catalog_manage')
  );
create policy motorcycle_unit_photos_delete on public.motorcycle_unit_photos
  for delete to authenticated using (
    public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('catalog_manage')
  );

create policy motorcycle_unit_photo_objects_read on storage.objects
  for select to authenticated using (
    bucket_id='motorcycle-unit-photos'
    and (public.has_any_role(array['manager','owner','admin']::public.app_role[])
      or public.has_employee_permission('catalog_manage')
      or public.has_employee_permission('finance_manage'))
  );
create policy motorcycle_unit_photo_objects_insert on storage.objects
  for insert to authenticated with check (
    bucket_id='motorcycle-unit-photos'
    and (public.has_any_role(array['manager','owner','admin']::public.app_role[])
      or public.has_employee_permission('catalog_manage'))
  );
create policy motorcycle_unit_photo_objects_delete on storage.objects
  for delete to authenticated using (
    bucket_id='motorcycle-unit-photos'
    and (public.has_any_role(array['manager','owner','admin']::public.app_role[])
      or public.has_employee_permission('catalog_manage'))
  );

create or replace function private.set_motorcycle_unit_primary_photo_impl(p_photo_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_unit_id uuid;
begin
  if (select auth.uid()) is null or not (
    public.has_any_role(array['manager','owner','admin']::public.app_role[])
    or public.has_employee_permission('catalog_manage')
  ) then
    raise exception 'ليس لديك صلاحية إدارة صور الوحدة' using errcode='42501';
  end if;
  select motorcycle_unit_id into v_unit_id
    from public.motorcycle_unit_photos where id=p_photo_id;
  if not found then raise exception 'صورة الوحدة غير موجودة' using errcode='P0002'; end if;
  perform 1 from public.motorcycle_units where id=v_unit_id for update;
  update public.motorcycle_unit_photos set is_primary=false where motorcycle_unit_id=v_unit_id and is_primary;
  update public.motorcycle_unit_photos set is_primary=true where id=p_photo_id;
end;
$$;
revoke all on function private.set_motorcycle_unit_primary_photo_impl(uuid) from public, anon;
grant execute on function private.set_motorcycle_unit_primary_photo_impl(uuid) to authenticated;

create or replace function public.set_motorcycle_unit_primary_photo(p_photo_id uuid)
returns void language sql security invoker set search_path='' as $$
  select private.set_motorcycle_unit_primary_photo_impl($1);
$$;
revoke all on function public.set_motorcycle_unit_primary_photo(uuid) from public, anon;
grant execute on function public.set_motorcycle_unit_primary_photo(uuid) to authenticated;

commit;
