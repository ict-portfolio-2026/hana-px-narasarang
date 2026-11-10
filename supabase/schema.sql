-- HANA뿐인 PX — Supabase 스키마와 접근 정책
-- Supabase 대시보드 > SQL Editor에서 한 번 실행합니다. 여러 번 실행해도 안전하게 작성했습니다.
--
-- 접근 원칙
--   참여자(anon)  : 결과 행 추가만 가능. 조회·수정·삭제 불가
--                   앱 전환 클릭은 px_mark_oneq_clicked()로 oneq_clicked 한 칸만 true로 바꿈
--   운영자        : Supabase Auth로 로그인하고 px_admins에 등록된 계정만 결과 조회 가능
--   그 외         : 모두 거부 (RLS 기본 거부)

-- 1) 결과 테이블 ---------------------------------------------------------------
create table if not exists public.hana_px_results (
  id               bigint generated always as identity primary key,
  created_at       timestamptz not null default now(),
  campaign_id      text        not null,
  result_type      text,
  result_category  text,
  top_benefit_ids  jsonb,
  scores           jsonb,
  benefit_scores   jsonb,
  answers          jsonb,
  user_agent       text,
  oneq_clicked     boolean     not null default false
);

-- 기존 테이블에도 적용되도록 컬럼을 따로 추가
alter table public.hana_px_results add column if not exists client_ref uuid;
create unique index if not exists hana_px_results_client_ref_key
  on public.hana_px_results (client_ref);

-- 2) 운영자 목록 ---------------------------------------------------------------
create table if not exists public.px_admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.px_admins enable row level security;
-- px_admins는 정책을 두지 않아 API로는 읽기·쓰기 모두 불가 (SQL Editor에서만 관리)

-- 3) RLS -------------------------------------------------------------------------
alter table public.hana_px_results enable row level security;

drop policy if exists "participants can insert" on public.hana_px_results;
create policy "participants can insert"
  on public.hana_px_results for insert
  to anon, authenticated
  with check (oneq_clicked = false);

drop policy if exists "admins can read" on public.hana_px_results;
create policy "admins can read"
  on public.hana_px_results for select
  to authenticated
  using (exists (select 1 from public.px_admins a where a.user_id = auth.uid()));

-- 이전 버전에서 쓰던 넓은 권한이 남아 있다면 정리
revoke update, delete on public.hana_px_results from anon, authenticated;

-- ⚠ RLS 정책은 '하나라도 허용하면 통과'(OR)입니다. 예전에 만든 정책이 남아 있으면 위 제한이 무력화됩니다.
--    아래 조회 결과에 위 두 정책 외의 것이 있으면 drop policy 로 지우세요.
--    select policyname, cmd, roles from pg_policies where tablename = 'hana_px_results';

-- 4) 앱 전환 클릭 기록 함수 -----------------------------------------------------
-- 참여자에게 UPDATE 권한을 주지 않고, 자기 결과의 client_ref를 아는 경우에만 한 칸을 바꾼다.
create or replace function public.px_mark_oneq_clicked(p_ref uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.hana_px_results
     set oneq_clicked = true
   where client_ref = p_ref;
$$;

revoke all on function public.px_mark_oneq_clicked(uuid) from public;
grant execute on function public.px_mark_oneq_clicked(uuid) to anon, authenticated;

-- 5) 운영자 등록 (실행 전 이메일을 바꾸세요) ----------------------------------
-- Authentication > Users에서 운영자 계정을 먼저 만든 뒤:
-- insert into public.px_admins (user_id)
--   select id from auth.users where email = 'operator@example.com'
-- on conflict do nothing;
