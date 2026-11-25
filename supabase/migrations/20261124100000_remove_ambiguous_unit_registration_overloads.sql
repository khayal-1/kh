begin;

-- PostgREST cannot reliably resolve the older default-argument overloads beside
-- the current cost-bearing RPC. Remove only those function signatures; no rows
-- or unit records are changed. Keep the single 10-argument public entry point
-- whose implementation records the opening unit cost and stock ledger entries.
drop function if exists public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text);
drop function if exists public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text);

-- Reassert the intended access boundary on the sole public signature.
revoke all on function public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text,numeric) from public,anon;
grant execute on function public.register_motorcycle_unit_with_engine_number(uuid,text,text,text,date,date,text,integer,text,numeric) to authenticated;

commit;
