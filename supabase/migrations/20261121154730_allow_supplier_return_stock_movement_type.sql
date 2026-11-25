alter table public.stock_movements
  drop constraint if exists stock_movements_movement_type_check;
alter table public.stock_movements
  add constraint stock_movements_movement_type_check
  check (movement_type = any (array['opening','sale','adjustment','purchase_receipt','purchase_return','sale_return']::text[]));
