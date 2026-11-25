begin;

alter table public.photo_assets
  add column if not exists telegram_file_unique_id text,
  add column if not exists storage_path text,
  add column if not exists public_url text,
  add column if not exists byte_size bigint,
  add column if not exists optimized boolean not null default false;

create index if not exists photo_assets_motorcycle_created_idx
  on public.photo_assets (motorcycle_id, created_at desc);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('catalog-images','catalog-images',true,8388608,array['image/jpeg','image/png','image/webp']::text[])
on conflict (id) do update
set public=excluded.public, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists catalog_images_upload on storage.objects;
create policy catalog_images_upload on storage.objects for insert to authenticated
with check (bucket_id='catalog-images' and (
  public.has_any_role(array['manager','owner','admin']::public.app_role[])
  or public.has_employee_permission('catalog_manage')
));

drop policy if exists catalog_images_delete on storage.objects;
create policy catalog_images_delete on storage.objects for delete to authenticated
using (bucket_id='catalog-images' and (
  public.has_any_role(array['manager','owner','admin']::public.app_role[])
  or public.has_employee_permission('catalog_manage')
));

drop policy if exists photo_update on public.photo_assets;
create policy photo_update on public.photo_assets for update to authenticated
using (public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('catalog_manage'))
with check (public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('catalog_manage'));

drop policy if exists photo_delete on public.photo_assets;
create policy photo_delete on public.photo_assets for delete to authenticated
using (public.has_any_role(array['manager','owner','admin']::public.app_role[]) or public.has_employee_permission('catalog_manage'));

commit;