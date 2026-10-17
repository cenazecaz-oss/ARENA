-- Run this once in Supabase > SQL Editor > New query > Run.
-- Two virtual balances per user. No cash value. Coins can only change through the functions below.

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
create policy "read own profile" on public.profiles for select using (auth.uid() = id);
drop policy if exists "read own history" on public.reward_history;
create policy "read own history" on public.reward_history for select using (auth.uid() = user_id);
-- No insert/update policies on purpose: the browser cannot edit balances directly.

-- Create a profile (with the first 100 monthly coins) when someone signs up
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1), 'Creator'));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- Spend voting coins (votes and unlocks)
create or replace function public.spend_voting_coins(n int) returns int
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  if n < 1 or n > 100 then raise exception 'bad_amount'; end if;
  update public.profiles set voting_coins = voting_coins - n
   where id = auth.uid() and voting_coins >= n returning voting_coins into v;
  if v is null then raise exception 'not_enough_coins'; end if;
  return v;
end $$;

-- Spend reward coins (unlocks)
create or replace function public.spend_reward_coins(n int) returns int
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  if n < 1 or n > 100 then raise exception 'bad_amount'; end if;
  update public.profiles set reward_coins = reward_coins - n
   where id = auth.uid() and reward_coins >= n returning reward_coins into v;
  if v is null then raise exception 'not_enough_coins'; end if;
  return v;
end $$;

-- Monthly allowance: +100 voting coins, once per calendar month
create or replace function public.claim_monthly() returns int
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  update public.profiles set voting_coins = voting_coins + 100, last_claim = current_date
   where id = auth.uid() and date_trunc('month', last_claim) < date_trunc('month', current_date)
   returning voting_coins into v;
  if v is null then raise exception 'already_claimed'; end if;
  return v;
end $$;

-- Add a battle/sales reward. TEST ONLY: the browser decides the amount (capped at 500).
-- Before a real launch, compute rewards on the server instead (see README, "Security").
create or replace function public.add_reward(p_desc text, p_coins int) returns int
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  if p_coins < 1 or p_coins > 500 then raise exception 'bad_amount'; end if;
  update public.profiles set reward_coins = reward_coins + p_coins where id = auth.uid() returning reward_coins into v;
  insert into public.reward_history (user_id, description, coins) values (auth.uid(), left(p_desc, 120), p_coins);
  return v;
end $$;

revoke all on function public.spend_voting_coins(int), public.spend_reward_coins(int), public.claim_monthly(), public.add_reward(text, int) from public, anon;
grant execute on function public.spend_voting_coins(int), public.spend_reward_coins(int), public.claim_monthly(), public.add_reward(text, int) to authenticated;
