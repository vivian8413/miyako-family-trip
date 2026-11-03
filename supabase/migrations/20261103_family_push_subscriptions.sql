-- Miyako PWA push subscriptions. Run manually in Supabase SQL Editor.
-- This does not modify existing family, memo, expense or notification records.
create table if not exists public.family_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth_secret text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists family_push_subscriptions_user_idx
  on public.family_push_subscriptions(auth_user_id);
alter table public.family_push_subscriptions enable row level security;
revoke all on public.family_push_subscriptions from anon;
grant select, insert, update, delete on public.family_push_subscriptions to authenticated;
drop policy if exists family_push_subscriptions_own_select on public.family_push_subscriptions;
create policy family_push_subscriptions_own_select on public.family_push_subscriptions
for select to authenticated using (auth_user_id = (select auth.uid()));
drop policy if exists family_push_subscriptions_own_insert on public.family_push_subscriptions;
create policy family_push_subscriptions_own_insert on public.family_push_subscriptions
for insert to authenticated with check (
 auth_user_id = (select auth.uid()) and exists (
 select 1 from public.family_members fm where fm.auth_user_id = (select auth.uid())
 )
);
drop policy if exists family_push_subscriptions_own_update on public.family_push_subscriptions;
create policy family_push_subscriptions_own_update on public.family_push_subscriptions
for update to authenticated using (auth_user_id = (select auth.uid()))
with check (auth_user_id = (select auth.uid()));
drop policy if exists family_push_subscriptions_own_delete on public.family_push_subscriptions;
create policy family_push_subscriptions_own_delete on public.family_push_subscriptions
for delete to authenticated using (auth_user_id = (select auth.uid()));
-- Sender must run server-side using the service role, never in public GitHub Pages JS.
