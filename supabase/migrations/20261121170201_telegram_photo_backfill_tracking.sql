alter table public.photo_assets
  add column if not exists sync_error text,
  add column if not exists sync_attempted_at timestamptz;

create index if not exists photo_assets_unsynced_idx
  on public.photo_assets (created_at)
  where storage_path is null and sync_error is null;