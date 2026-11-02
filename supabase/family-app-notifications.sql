-- Miyako family in-app notifications. Run once in Supabase SQL Editor.
-- No push subscriptions, no changes to existing member/expense/photo rows.
create table if not exists public.family_app_notifications (
 id bigint generated always as identity primary key,
 recipient_user_id uuid not null,
 actor_user_id uuid,
 event_type text not null,
 title text not null,
 detail text not null default '',
 created_at timestamptz not null default now(),
 read_at timestamptz
);
create index if not exists family_app_notifications_recipient_idx on public.family_app_notifications(recipient_user_id,created_at desc);
alter table public.family_app_notifications enable row level security;
revoke all on public.family_app_notifications from anon;
grant select,update on public.family_app_notifications to authenticated;
drop policy if exists "notification recipient read" on public.family_app_notifications;
create policy "notification recipient read" on public.family_app_notifications for select to authenticated using (recipient_user_id=auth.uid());
drop policy if exists "notification recipient mark read" on public.family_app_notifications;
create policy "notification recipient mark read" on public.family_app_notifications for update to authenticated using (recipient_user_id=auth.uid()) with check (recipient_user_id=auth.uid());
-- Prevent authenticated clients from forging notifications or changing event metadata.
revoke update on public.family_app_notifications from authenticated;
grant update (read_at) on public.family_app_notifications to authenticated;

create or replace function public.miyako_emit_family_notification()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
 actor uuid := auth.uid();
 event_label text;
 event_detail text;
 event_type text;
begin
 if actor is null then return new; end if;
 if tg_table_name='trip_memos' then
  if tg_op='UPDATE' and new.content is not distinct from old.content then return new; end if;
  event_type:='memo'; event_label:=case when tg_op='INSERT' then '新增共用備忘' else '更新共用備忘' end;
  event_detail:=left(coalesce(new.content,''),120);
 elsif tg_table_name='trip_expenses' then
  event_type:='expense';event_label:=case when tg_op='INSERT' then '新增共用費用' else '更新共用費用' end;
  event_detail:=left(coalesce(new.description,''),120);
 elsif tg_table_name='family_wall_photos' then
  event_type:='photo';event_label:='上傳新照片';
  event_detail:=left(coalesce(new.caption,'共用相簿新增照片'),120);
 else return new; end if;
 insert into public.family_app_notifications(recipient_user_id,actor_user_id,event_type,title,detail)
 select m.auth_user_id,actor,event_type,
        coalesce((select nickname from public.family_members where auth_user_id=actor limit 1),'家人')||' '||event_label,
        event_detail
 from public.family_members m
 where m.auth_user_id is not null and m.auth_user_id<>actor
 and exists(select 1 from public.family_join_requests j where j.auth_user_id=m.auth_user_id and j.status='approved');
 return new;
end $$;
drop trigger if exists miyako_notify_memos on public.trip_memos;
create trigger miyako_notify_memos after insert or update on public.trip_memos for each row execute function public.miyako_emit_family_notification();
drop trigger if exists miyako_notify_expenses on public.trip_expenses;
create trigger miyako_notify_expenses after insert or update on public.trip_expenses for each row execute function public.miyako_emit_family_notification();
drop trigger if exists miyako_notify_photos on public.family_wall_photos;
create trigger miyako_notify_photos after insert on public.family_wall_photos for each row execute function public.miyako_emit_family_notification();
