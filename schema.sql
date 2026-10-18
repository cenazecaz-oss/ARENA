-- ARENA database. Safe to run again: paste the WHOLE file in Supabase > SQL Editor > Run.
-- All coins are virtual. Balances can only change through the functions in this file.

-- ============ PROFILES ============
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'Creator',
  voting_coins int not null default 100 check (voting_coins >= 0),
  reward_coins int not null default 0 check (reward_coins >= 0),
  last_claim date not null default current_date,
  created_at timestamptz not null default now()
);
create table if not exists public.reward_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  description text not null,
  coins int not null,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
alter table public.reward_history enable row level security;
drop policy if exists "read own profile" on public.profiles;
drop policy if exists "read profiles" on public.profiles;
create policy "read profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "read own history" on public.reward_history;
create policy "read own history" on public.reward_history for select to authenticated using (auth.uid() = user_id);
-- everyone can see names; nobody can read other people's balances
revoke all on public.profiles from anon, authenticated;
grant select (id, name, created_at) on public.profiles to authenticated;
grant select on public.reward_history to authenticated;
grant usage on schema public to authenticated;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1), 'Creator'), 40));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
insert into public.profiles (id, name)
select id, left(coalesce(raw_user_meta_data->>'name', raw_user_meta_data->>'full_name', split_part(email,'@',1), 'Creator'), 40) from auth.users
on conflict (id) do nothing;

create or replace function public.my_profile() returns public.profiles
language sql security definer set search_path = public stable as $$ select * from public.profiles where id = auth.uid() $$;

-- ============ POSTS, COMMENTS, FOLLOWS, LIKES, UNLOCKS ============
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('photo','video')),
  title text not null check (char_length(title) between 1 and 120),
  description text not null default '' check (char_length(description) <= 500),
  gate text not null default 'free' check (gate in ('free','paid','follow')),
  price int not null default 5 check (price between 1 and 100),
  file_path text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create table if not exists public.follows (
  follower uuid not null references public.profiles(id) on delete cascade,
  followee uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower, followee), check (follower <> followee)
);
create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (post_id, user_id)
);
create table if not exists public.unlocks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
alter table public.posts enable row level security; alter table public.comments enable row level security;
alter table public.follows enable row level security; alter table public.likes enable row level security; alter table public.unlocks enable row level security;

drop policy if exists "posts read" on public.posts;   create policy "posts read" on public.posts for select to authenticated using (true);
drop policy if exists "posts insert" on public.posts; create policy "posts insert" on public.posts for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "posts update" on public.posts; create policy "posts update" on public.posts for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "posts delete" on public.posts; create policy "posts delete" on public.posts for delete to authenticated using (auth.uid() = user_id);
drop policy if exists "comments read" on public.comments;   create policy "comments read" on public.comments for select to authenticated using (true);
drop policy if exists "comments insert" on public.comments; create policy "comments insert" on public.comments for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "comments delete" on public.comments; create policy "comments delete" on public.comments for delete to authenticated
  using (auth.uid() = user_id or exists (select 1 from public.posts p where p.id = post_id and p.user_id = auth.uid()));
drop policy if exists "follows read" on public.follows;   create policy "follows read" on public.follows for select to authenticated using (true);
drop policy if exists "follows insert" on public.follows; create policy "follows insert" on public.follows for insert to authenticated with check (auth.uid() = follower);
drop policy if exists "follows delete" on public.follows; create policy "follows delete" on public.follows for delete to authenticated using (auth.uid() = follower);
drop policy if exists "likes read" on public.likes;   create policy "likes read" on public.likes for select to authenticated using (true);
drop policy if exists "likes insert" on public.likes; create policy "likes insert" on public.likes for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "likes delete" on public.likes; create policy "likes delete" on public.likes for delete to authenticated using (auth.uid() = user_id);
drop policy if exists "unlocks read" on public.unlocks; create policy "unlocks read" on public.unlocks for select to authenticated
  using (auth.uid() = user_id or exists (select 1 from public.posts p where p.id = post_id and p.user_id = auth.uid()));
grant select, insert, delete on public.posts, public.comments, public.follows, public.likes to authenticated;
grant update (title, description, gate, price) on public.posts to authenticated;
grant select on public.unlocks to authenticated;

-- ============ BATTLES ============
create table if not exists public.battles (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  category text not null check (category in ('dance','sing','debate','comedy','roast','follow')),
  mode text not null check (mode in ('video','audio')),
  status text not null default 'open' check (status in ('open','live','ended')),
  pool int not null default 0,
  winner uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create table if not exists public.battle_entries (
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  votes int not null default 0,
  boost int not null default 0,
  primary key (battle_id, user_id)
);
create table if not exists public.battle_likes (
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (battle_id, user_id)
);
alter table public.battles enable row level security; alter table public.battle_entries enable row level security; alter table public.battle_likes enable row level security;
drop policy if exists "battles read" on public.battles; create policy "battles read" on public.battles for select to authenticated using (true);
drop policy if exists "entries read" on public.battle_entries; create policy "entries read" on public.battle_entries for select to authenticated using (true);
drop policy if exists "blikes read" on public.battle_likes; create policy "blikes read" on public.battle_likes for select to authenticated using (auth.uid() = user_id);
grant select on public.battles, public.battle_entries, public.battle_likes to authenticated;

-- ============ COIN FUNCTIONS ============
drop function if exists public.add_reward(text, int);

create or replace function public.claim_monthly() returns int
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  update public.profiles set voting_coins = voting_coins + 100, last_claim = current_date
   where id = auth.uid() and date_trunc('month', last_claim) < date_trunc('month', current_date) returning voting_coins into v;
  if v is null then raise exception 'already_claimed'; end if;
  return v;
end $$;

create or replace function public.unlock_post(p_post uuid) returns void
language plpgsql security definer set search_path = public as $$
declare po public.posts; me uuid := auth.uid(); ok boolean := false;
begin
  select * into po from public.posts where id = p_post;
  if po.id is null then raise exception 'not_found'; end if;
  if po.gate <> 'paid' or po.user_id = me then raise exception 'not_paid_content'; end if;
  if exists (select 1 from public.unlocks where user_id = me and post_id = p_post) then return; end if;
  update public.profiles set voting_coins = voting_coins - po.price where id = me and voting_coins >= po.price;
  if found then ok := true; else
    update public.profiles set reward_coins = reward_coins - po.price where id = me and reward_coins >= po.price; ok := found;
  end if;
  if not ok then raise exception 'not_enough_coins'; end if;
  insert into public.unlocks (user_id, post_id) values (me, p_post);
  update public.profiles set reward_coins = reward_coins + po.price where id = po.user_id;
  insert into public.reward_history (user_id, description, coins) values (po.user_id, left('Unlock: ' || po.title, 120), po.price);
end $$;

create or replace function public.create_battle(p_title text, p_cat text, p_mode text) returns uuid
language plpgsql security definer set search_path = public as $$
declare i uuid;
begin
  insert into public.battles (host_id, title, category, mode) values (auth.uid(), left(trim(p_title), 120), p_cat, p_mode) returning id into i;
  return i;
end $$;

create or replace function public.join_battle(p_battle uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b public.battles; n int;
begin
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.status = 'ended' then raise exception 'battle_closed'; end if;
  if b.host_id = auth.uid() then raise exception 'host_cannot_battle'; end if;
  select count(*) into n from public.battle_entries where battle_id = p_battle;
  if n >= 2 then raise exception 'battle_full'; end if;
  insert into public.battle_entries (battle_id, user_id) values (p_battle, auth.uid());
  if n + 1 = 2 then update public.battles set status = 'live' where id = p_battle; end if;
end $$;

create or replace function public.cast_vote(p_battle uuid, p_target uuid, n int) returns void
language plpgsql security definer set search_path = public as $$
declare b public.battles;
begin
  if n not in (1, 5, 10) then raise exception 'bad_amount'; end if;
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.status <> 'live' then raise exception 'battle_not_live'; end if;
  if exists (select 1 from public.battle_entries where battle_id = p_battle and user_id = auth.uid()) then raise exception 'contender_cannot_vote'; end if;
  if not exists (select 1 from public.battle_entries where battle_id = p_battle and user_id = p_target) then raise exception 'bad_target'; end if;
  update public.profiles set voting_coins = voting_coins - n where id = auth.uid() and voting_coins >= n;
  if not found then raise exception 'not_enough_coins'; end if;
  update public.battle_entries set votes = votes + n where battle_id = p_battle and user_id = p_target;
  update public.battles set pool = pool + n where id = p_battle;
end $$;

create or replace function public.like_battle(p_battle uuid, p_target uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b public.battles;
begin
  select * into b from public.battles where id = p_battle;
  if b.id is null or b.status <> 'live' then raise exception 'battle_not_live'; end if;
  if exists (select 1 from public.battle_entries where battle_id = p_battle and user_id = auth.uid()) then raise exception 'contender_cannot_vote'; end if;
  begin
    insert into public.battle_likes (battle_id, user_id) values (p_battle, auth.uid());
  exception when unique_violation then raise exception 'already_liked'; end;
  update public.battle_entries set boost = boost + 2 where battle_id = p_battle and user_id = p_target;
end $$;

-- Host ends the battle: 20% of the pool to the host, 80% shared between the contenders by their eligible votes
create or replace function public.end_battle(p_battle uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b public.battles; e record; hostcut int; rest int; tv int; sh int; w uuid;
begin
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.host_id <> auth.uid() then raise exception 'not_host'; end if;
  if b.status = 'ended' then return; end if;
  hostcut := floor(b.pool * 0.2); rest := b.pool - hostcut;
  select coalesce(sum(votes), 0) into tv from public.battle_entries where battle_id = p_battle;
  if hostcut > 0 then
    update public.profiles set reward_coins = reward_coins + hostcut where id = b.host_id;
    insert into public.reward_history (user_id, description, coins) values (b.host_id, left('Host 20%: ' || b.title, 120), hostcut);
  end if;
  for e in select * from public.battle_entries where battle_id = p_battle loop
    sh := case when tv > 0 then floor(rest * e.votes / tv) else 0 end;
    if sh > 0 then
      update public.profiles set reward_coins = reward_coins + sh where id = e.user_id;
      insert into public.reward_history (user_id, description, coins) values (e.user_id, left('Battle reward: ' || b.title, 120), sh);
    end if;
  end loop;
  select user_id into w from public.battle_entries where battle_id = p_battle order by (votes + boost) desc limit 1;
  update public.battles set status = 'ended', winner = w where id = p_battle;
end $$;

revoke all on function public.claim_monthly(), public.unlock_post(uuid), public.create_battle(text,text,text), public.join_battle(uuid),
  public.cast_vote(uuid,uuid,int), public.like_battle(uuid,uuid), public.end_battle(uuid), public.my_profile() from public, anon;
grant execute on function public.claim_monthly(), public.unlock_post(uuid), public.create_battle(text,text,text), public.join_battle(uuid),
  public.cast_vote(uuid,uuid,int), public.like_battle(uuid,uuid), public.end_battle(uuid), public.my_profile() to authenticated;
drop function if exists public.spend_voting_coins(int); drop function if exists public.spend_reward_coins(int);

-- ============ FILE STORAGE (photos and videos from the user's device) ============
insert into storage.buckets (id, name, public, file_size_limit) values ('media', 'media', false, 52428800) on conflict (id) do nothing;

create or replace function public.can_view_media(p text) returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.posts po where po.file_path = p and (
    po.gate = 'free' or po.user_id = auth.uid()
    or (po.gate = 'paid' and exists (select 1 from public.unlocks u where u.post_id = po.id and u.user_id = auth.uid()))
    or (po.gate = 'follow' and exists (select 1 from public.follows f where f.follower = auth.uid() and f.followee = po.user_id))
  ))
$$;
drop policy if exists "arena upload own folder" on storage.objects;
create policy "arena upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "arena view allowed media" on storage.objects;
create policy "arena view allowed media" on storage.objects for select to authenticated
  using (bucket_id = 'media' and ((storage.foldername(name))[1] = auth.uid()::text or public.can_view_media(name)));
drop policy if exists "arena delete own media" on storage.objects;
create policy "arena delete own media" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
