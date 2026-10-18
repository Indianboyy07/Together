-- Together: initial schema + RLS. Run in Supabase SQL editor. NOT yet tested against a live project.
create extension if not exists pgcrypto;

create table public.couples (id uuid primary key default gen_random_uuid(), name text, created_at timestamptz not null default now());
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Person', timezone text not null default 'UTC',
  avatar_path text, created_at timestamptz not null default now());
create table public.couple_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  couple_id uuid not null references public.couples(id) on delete cascade);
create index on public.couple_members(couple_id);

create function public.enforce_two_members() returns trigger language plpgsql as $$
begin if (select count(*) from public.couple_members where couple_id = new.couple_id) >= 2
  then raise exception 'couple already has two members'; end if; return new; end $$;
create trigger trg_two_members before insert on public.couple_members
  for each row execute function public.enforce_two_members();

create function public.my_couple() returns uuid language sql stable security definer set search_path = public as $$
  select couple_id from public.couple_members where user_id = auth.uid() $$;

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null default public.my_couple() references public.couples(id) on delete cascade,
  creator_id uuid not null default auth.uid() references auth.users(id),
  assignee_id uuid not null references auth.users(id),
  title text not null check (char_length(title) between 1 and 120),
  description text, priority smallint not null default 2,
  due_time time, recurrence text not null default 'once' check (recurrence in ('once','daily','weekly')),
  weekdays smallint[], start_date date not null default current_date, end_date date, one_time_date date,
  archived_at timestamptz, created_at timestamptz not null default now());
create index on public.tasks(couple_id, assignee_id);

create table public.task_completions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  occurrence_date date not null,
  user_id uuid not null default auth.uid() references auth.users(id),
  completed_at timestamptz not null default now(),
  unique (task_id, occurrence_date));

create table public.points_ledger (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  completion_id uuid not null unique references public.task_completions(id) on delete cascade,
  points int not null default 10, day date not null, created_at timestamptz not null default now());

create function public.award_points() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.points_ledger(couple_id, user_id, completion_id, points, day)
  select t.couple_id, new.user_id, new.id, 10, new.occurrence_date from public.tasks t where t.id = new.task_id
  on conflict (completion_id) do nothing;
  return new; end $$;
create trigger trg_award after insert on public.task_completions for each row execute function public.award_points();

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null default public.my_couple() references public.couples(id) on delete cascade,
  author_id uuid not null default auth.uid() references auth.users(id),
  title text not null default '', body text not null, pinned boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create function public.notes_touch() returns trigger language plpgsql as $$
begin new.created_at := old.created_at; new.author_id := old.author_id; new.couple_id := old.couple_id;
  new.updated_at := now(); return new; end $$;
create trigger trg_notes_touch before update on public.notes for each row execute function public.notes_touch();

create table public.love_notes (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null default public.my_couple() references public.couples(id) on delete cascade,
  author_id uuid not null default auth.uid() references auth.users(id),
  recipient_id uuid not null references auth.users(id),
  kind text not null default 'note' check (kind in ('note','birthday','anniversary')),
  title text not null default '', body text not null,
  status text not null default 'draft' check (status in ('draft','sent')),
  reveal_at timestamptz, sent_at timestamptz, read_at timestamptz,
  created_at timestamptz not null default now());
create index on public.love_notes(recipient_id, status, reveal_at);

-- RLS
alter table public.couples enable row level security;
alter table public.profiles enable row level security;
alter table public.couple_members enable row level security;
alter table public.tasks enable row level security;
alter table public.task_completions enable row level security;
alter table public.points_ledger enable row level security;
alter table public.notes enable row level security;
alter table public.love_notes enable row level security;
revoke all on all tables in schema public from anon;

create policy couples_read on public.couples for select to authenticated using (id = public.my_couple());
create policy members_read on public.couple_members for select to authenticated using (couple_id = public.my_couple());
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or id in (select user_id from public.couple_members where couple_id = public.my_couple()));
create policy profiles_ins on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_upd on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy tasks_read on public.tasks for select to authenticated using (couple_id = public.my_couple());
create policy tasks_ins on public.tasks for insert to authenticated with check (
  couple_id = public.my_couple() and creator_id = auth.uid()
  and assignee_id in (select user_id from public.couple_members where couple_id = public.my_couple()));
create policy tasks_upd on public.tasks for update to authenticated
  using (creator_id = auth.uid() and couple_id = public.my_couple())
  with check (creator_id = auth.uid() and couple_id = public.my_couple()
  and assignee_id in (select user_id from public.couple_members where couple_id = public.my_couple()));
create policy tasks_del on public.tasks for delete to authenticated using (creator_id = auth.uid() and couple_id = public.my_couple());

create policy comp_read on public.task_completions for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id and t.couple_id = public.my_couple()));
create policy comp_ins on public.task_completions for insert to authenticated with check (
  user_id = auth.uid() and exists (select 1 from public.tasks t where t.id = task_id
    and t.assignee_id = auth.uid() and t.couple_id = public.my_couple() and t.archived_at is null)
  and occurrence_date <= current_date + 1);
create policy comp_del on public.task_completions for delete to authenticated using (user_id = auth.uid());

create policy points_read on public.points_ledger for select to authenticated using (couple_id = public.my_couple());

create policy notes_read on public.notes for select to authenticated using (couple_id = public.my_couple());
create policy notes_ins on public.notes for insert to authenticated with check (couple_id = public.my_couple() and author_id = auth.uid());
create policy notes_upd on public.notes for update to authenticated using (couple_id = public.my_couple()) with check (couple_id = public.my_couple());
create policy notes_del on public.notes for delete to authenticated using (couple_id = public.my_couple());

-- Recipients cannot read a note before reveal_at, even with direct API queries.
create policy love_read on public.love_notes for select to authenticated using (
  couple_id = public.my_couple() and (author_id = auth.uid() or
    (recipient_id = auth.uid() and status = 'sent' and (reveal_at is null or reveal_at <= now()))));
create policy love_ins on public.love_notes for insert to authenticated with check (
  couple_id = public.my_couple() and author_id = auth.uid() and recipient_id <> auth.uid()
  and recipient_id in (select user_id from public.couple_members where couple_id = public.my_couple()));
create policy love_upd on public.love_notes for update to authenticated
  using (author_id = auth.uid() and (status = 'draft' or reveal_at > now()))
  with check (author_id = auth.uid() and couple_id = public.my_couple());
create policy love_del on public.love_notes for delete to authenticated
  using (author_id = auth.uid() and (status = 'draft' or reveal_at > now()));

create function public.mark_love_note_read(p_id uuid) returns void language sql security definer set search_path = public as $$
  update public.love_notes set read_at = now()
  where id = p_id and recipient_id = auth.uid() and status = 'sent' and read_at is null
    and (reveal_at is null or reveal_at <= now()) $$;
revoke all on function public.mark_love_note_read(uuid) from public, anon;
grant execute on function public.mark_love_note_read(uuid) to authenticated;

-- ADMIN PROVISIONING (run once in the SQL editor after creating the two Auth users in the dashboard).
-- Replace the emails. Public sign-up must be turned OFF in Auth settings.
-- with c as (insert into public.couples(name) values ('Us') returning id)
-- insert into public.couple_members(user_id, couple_id)
--   select u.id, c.id from auth.users u, c where u.email in ('EMAIL_ONE','EMAIL_TWO');
-- insert into public.profiles(id, display_name)
--   select id, 'Person ' || row_number() over () from auth.users where email in ('EMAIL_ONE','EMAIL_TWO');
