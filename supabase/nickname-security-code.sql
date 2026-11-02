-- 宮古島家人暱稱：管理員核發一次性安全碼（請在 Supabase SQL Editor 執行一次）
-- 注意：會撤銷舊 update_my_family_nickname RPC 對 authenticated 的執行權限。
begin;

create table if not exists public.family_nickname_codes (
 id uuid primary key default gen_random_uuid(),
 target_user_id uuid not null,
 code text not null,
 expires_at timestamptz not null,
 attempts integer not null default 0,
 used_at timestamptz,
 created_by uuid not null,
 created_at timestamptz not null default now()
);
alter table public.family_nickname_codes enable row level security;
revoke all on public.family_nickname_codes from anon, authenticated;
-- 只有 SECURITY DEFINER RPC 可以存取安全碼。

create or replace function public.issue_family_nickname_code(p_target_user_id uuid)
returns text language plpgsql security definer set search_path = ''
as $$
declare
 v_code text;
begin
 if auth.uid() is null or not (select public.is_family_admin()) then
   raise exception '僅管理員可核發安全碼';
 end if;
 if p_target_user_id is null or not exists (
   select 1 from public.family_members m
   join public.family_join_requests j on j.auth_user_id=m.auth_user_id and j.status='approved'
   where m.auth_user_id=p_target_user_id
 ) then
   raise exception '目標不是已核准家人';
 end if;
 -- 12 位隨機十六進位字元；不採用易猜測的六位數。
 v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 update public.family_nickname_codes set used_at=now()
 where target_user_id=p_target_user_id and used_at is null;
 insert into public.family_nickname_codes(target_user_id,code,expires_at,created_by)
 values (p_target_user_id,v_code,now()+interval '15 minutes',auth.uid());
 return v_code;
end $$;

create or replace function public.redeem_family_nickname_code(p_code text,p_nickname text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
 v_id uuid;
 v_name text:=btrim(coalesce(p_nickname,''));
 v_code text:=upper(btrim(coalesce(p_code,'')));
 v_record public.family_nickname_codes%rowtype;
begin
 v_id:=auth.uid();
 if v_id is null or not exists (
   select 1 from public.family_members m
   join public.family_join_requests j on j.auth_user_id=m.auth_user_id and j.status='approved'
   where m.auth_user_id=v_id
 ) then
   raise exception '僅已核准家人可以修改暱稱';
 end if;
 if char_length(v_name)<1 or char_length(v_name)>30 then
   raise exception '暱稱須為 1 至 30 字';
 end if;
 if v_code !~ '^[0-9A-F]{12}$' then
   raise exception '安全碼格式不正確';
 end if;
 select * into v_record
 from public.family_nickname_codes
 where target_user_id=v_id and used_at is null
 order by created_at desc limit 1 for update;
 if not found then raise exception '沒有可使用的安全碼'; end if;
 if v_record.expires_at<=now() or v_record.attempts>=5 then
   raise exception '安全碼已過期或嘗試次數過多';
 end if;
 if v_record.code<>v_code then
   update public.family_nickname_codes set attempts=attempts+1 where id=v_record.id;
   -- 以正常回傳保留錯誤次數，避免例外導致交易回滾。
   return '安全碼錯誤，剩餘嘗試次數：'||(4-v_record.attempts)::text;
 end if;
 update public.family_members set nickname=v_name where auth_user_id=v_id;
 if not found then raise exception '找不到家人身分'; end if;
 update public.family_nickname_codes set used_at=now() where id=v_record.id;
 return 'SUCCESS';
end $$;

revoke all on function public.issue_family_nickname_code(uuid) from public, anon;
revoke all on function public.redeem_family_nickname_code(text,text) from public, anon;
grant execute on function public.issue_family_nickname_code(uuid) to authenticated;
grant execute on function public.redeem_family_nickname_code(text,text) to authenticated;

-- 禁止繞過安全碼直接使用舊 RPC；舊函式仍保留供未來管理員維護。
do $$
begin
 if to_regprocedure('public.update_my_family_nickname(text)') is not null then
  execute 'revoke all on function public.update_my_family_nickname(text) from public, anon, authenticated';
 end if;
end $$;
commit;
