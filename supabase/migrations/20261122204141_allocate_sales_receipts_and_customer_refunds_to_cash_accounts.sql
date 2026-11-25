-- Source recovered from the applied production migration ledger.
create or replace function private.allocate_sale_payment_to_cash_account(p_payment_id uuid,p_cash_account_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.payments%rowtype;v_cash uuid;v_suspense uuid;v_entry uuid:=gen_random_uuid();
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسوية المقبوضات' using errcode='42501';end if;
 select * into p from public.payments where id=p_payment_id for update;
 if not found or p.journal_entry_id is null or p.cash_account_id is not null then raise exception 'الدفعة غير موجودة أو تمت تسويتها بالفعل' using errcode='P0002';end if;
 select account_id into v_cash from public.cash_accounts where id=p_cash_account_id and is_active;
 select id into v_suspense from public.accounting_accounts where code='1030' and is_active;
 if v_cash is null or v_suspense is null then raise exception 'حساب الخزينة أو حساب المقبوضات غير الموزعة غير جاهز' using errcode='22023';end if;
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by)
 values(v_entry,p.paid_at::date,'تسوية دفعة بيع إلى حساب نقدي/بنكي','sale_payment_reclass',p.id,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
 values(v_entry,v_cash,p.amount,0,'إثبات النقدية في الحساب المختار'),(v_entry,v_suspense,0,p.amount,'إقفال المقبوضات غير الموزعة');
 update public.payments set cash_account_id=p_cash_account_id where id=p.id;
 return jsonb_build_object('payment_id',p.id,'journal_entry_id',v_entry);
end $$;

create or replace function private.allocate_customer_refund_to_cash_account(p_transaction_id uuid,p_cash_account_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.customer_credit_transactions%rowtype;v_cash uuid;v_suspense uuid;v_entry uuid;v_amount numeric(14,2);
begin
 if not private.can_manage_finance() then raise exception 'غير مصرح بتسوية مردودات العملاء' using errcode='42501';end if;
 select * into t from public.customer_credit_transactions where id=p_transaction_id for update;
 if not found or t.transaction_type<>'cash_refund' or t.cash_account_id is not null then raise exception 'عملية الرد غير موجودة أو تمت تسويتها بالفعل' using errcode='P0002';end if;
 select account_id into v_cash from public.cash_accounts where id=p_cash_account_id and is_active;
 select id into v_suspense from public.accounting_accounts where code='1030' and is_active;
 if v_cash is null or v_suspense is null then raise exception 'حساب الخزينة أو حساب المقبوضات غير الموزعة غير جاهز' using errcode='22023';end if;
 v_amount:=abs(t.amount);v_entry:=gen_random_uuid();
 insert into public.journal_entries(id,entry_date,description,source_type,source_id,created_by)
 values(v_entry,t.created_at::date,'تسوية رد رصيد عميل إلى حساب نقدي/بنكي','customer_refund_reclass',t.id,(select auth.uid()));
 insert into public.journal_entry_lines(journal_entry_id,account_id,debit,credit,memo)
 values(v_entry,v_suspense,v_amount,0,'إقفال رد العميل غير الموزع'),(v_entry,v_cash,0,v_amount,'إثبات خروج النقدية من الحساب المختار');
 update public.customer_credit_transactions set cash_account_id=p_cash_account_id where id=t.id;
 return jsonb_build_object('transaction_id',t.id,'journal_entry_id',v_entry);
end $$;

create or replace function public.allocate_sale_payment_to_cash_account(uuid,uuid)
returns jsonb language sql security invoker set search_path='' as $$ select private.allocate_sale_payment_to_cash_account($1,$2) $$;
create or replace function public.allocate_customer_refund_to_cash_account(uuid,uuid)
returns jsonb language sql security invoker set search_path='' as $$ select private.allocate_customer_refund_to_cash_account($1,$2) $$;
revoke all on function public.allocate_sale_payment_to_cash_account(uuid,uuid) from public,anon;
grant execute on function public.allocate_sale_payment_to_cash_account(uuid,uuid) to authenticated;
revoke all on function public.allocate_customer_refund_to_cash_account(uuid,uuid) from public,anon;
grant execute on function public.allocate_customer_refund_to_cash_account(uuid,uuid) to authenticated;

