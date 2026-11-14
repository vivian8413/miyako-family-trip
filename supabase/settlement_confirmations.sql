-- Run once in Supabase SQL Editor before using the payment-confirmation UI.
-- Never modifies trip_expenses, trip_fund_transactions, or existing member slots.
create table if not exists public.trip_settlement_confirmations (
  payer_slot integer not null check (payer_slot between 1 and 9),
  payee_slot integer not null check (payee_slot between 1 and 9),
  ledger_key text not null check (length(ledger_key) between 1 and 160),
  amount_cents bigint not null check (amount_cents > 0),
  payer_confirmed_at timestamptz,
  payee_confirmed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (payer_slot,payee_slot,ledger_key),
  check (payer_slot <> payee_slot)
);
alter table public.trip_settlement_confirmations enable row level security;
revoke all on public.trip_settlement_confirmations from anon, authenticated;
grant select on public.trip_settlement_confirmations to authenticated;
drop policy if exists trip_settlement_confirmations_family_read on public.trip_settlement_confirmations;
create policy trip_settlement_confirmations_family_read on public.trip_settlement_confirmations
 for select to authenticated using (exists (select 1 from public.family_members m where m.auth_user_id=auth.uid()));
create or replace function public.set_trip_settlement_confirmation(
 p_payer integer,p_payee integer,p_ledger_key text,p_amount_cents bigint,p_confirm boolean
) returns void language plpgsql security definer set search_path=public as $$
declare v_slot integer;
begin
 if auth.uid() is null then raise exception '登入已失效'; end if;
 select s.slot into v_slot from public.trip_expense_member_slots s
 where s.auth_user_id=auth.uid();
 if v_slot is null then raise exception '尚未設定費用家人編號'; end if;
 if p_payer not between 1 and 9 or p_payee not between 1 and 9 or p_payer=p_payee
    or p_ledger_key is null or length(p_ledger_key) not between 1 and 160
    or p_amount_cents is null or p_amount_cents<=0 then
  raise exception '付款資料不正確';
 end if;
 if v_slot not in (p_payer,p_payee) then raise exception '只能確認自己的付款或收款'; end if;
 if not exists (select 1 from public.family_members where auth_user_id=auth.uid()) then
  raise exception '尚未核准為家人';
 end if;
 insert into public.trip_settlement_confirmations
 (payer_slot,payee_slot,ledger_key,amount_cents,payer_confirmed_at,payee_confirmed_at)
 values(p_payer,p_payee,p_ledger_key,p_amount_cents,
  case when v_slot=p_payer and p_confirm then now() else null end,
  case when v_slot=p_payee and p_confirm then now() else null end)
 on conflict(payer_slot,payee_slot,ledger_key) do update set
  payer_confirmed_at=case when v_slot=p_payer then (case when p_confirm then now() else null end)
    else trip_settlement_confirmations.payer_confirmed_at end,
  payee_confirmed_at=case when v_slot=p_payee then (case when p_confirm then now() else null end)
    else trip_settlement_confirmations.payee_confirmed_at end,
  updated_at=now()
 where trip_settlement_confirmations.amount_cents=excluded.amount_cents;
 if not found then raise exception '付款金額與原確認紀錄不符'; end if;
end; $$;
revoke all on function public.set_trip_settlement_confirmation(integer,integer,text,bigint,boolean) from public;
grant execute on function public.set_trip_settlement_confirmation(integer,integer,text,bigint,boolean) to authenticated;
