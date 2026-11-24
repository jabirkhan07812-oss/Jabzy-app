-- JABZY direct-chat gifts: secure coin debit and gift event.
-- Run this migration in Supabase SQL Editor after the user_coins wallet setup.
create table if not exists public.chat_gifts (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  gift_code text not null,
  coin_cost integer not null check (coin_cost > 0),
  created_at timestamptz not null default now(),
  constraint chat_gifts_no_self_gift check (sender_id <> recipient_id)
);
create index if not exists chat_gifts_sender_created_idx on public.chat_gifts(sender_id, created_at desc);
create index if not exists chat_gifts_recipient_created_idx on public.chat_gifts(recipient_id, created_at desc);
alter table public.chat_gifts enable row level security;
drop policy if exists "Chat participants can view their gifts" on public.chat_gifts;
create policy "Chat participants can view their gifts"
on public.chat_gifts for select to authenticated
using (sender_id = auth.uid() or recipient_id = auth.uid());
revoke all on public.chat_gifts from anon, authenticated;
grant select on public.chat_gifts to authenticated;

create or replace function public.send_chat_gift(
  p_recipient_id uuid,
  p_gift_code text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_sender_id uuid := auth.uid();
  v_cost integer;
  v_balance integer;
  v_gift_id uuid;
begin
  if v_sender_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_recipient_id is null or p_recipient_id = v_sender_id then
    raise exception 'INVALID_RECIPIENT';
  end if;

  v_cost := case p_gift_code
    when 'rose' then 10 when 'tulip' then 10 when 'daisy' then 10
    when 'bouquet' then 30 when 'sunflower' then 40 when 'heart' then 25
    when 'mini_bouquet' then 25 when 'chocolate_box' then 30
    when 'love_mug' then 35 when 'cupcake' then 20 when 'starry_lamp' then 40
    when 'music_box' then 50 when 'pearl_bracelet' then 60 when 'mini_teddy' then 70
    when 'heart_balloon' then 80 when 'rose_basket' then 100
    when 'crystal_heart' then 350 when 'diamond_necklace' then 1800
    when 'love_carousel' then 900 when 'kiss' then 10 when 'hug' then 10
    when 'pink_heart' then 10 when 'love_letter' then 75 when 'couple_ring' then 300
    when 'love_bear' then 450 when 'teddy' then 50 when 'paw_print' then 10
    when 'chick' then 10 when 'puppy' then 80 when 'kitten' then 90
    when 'bunny' then 120 when 'birthday_cake' then 150 when 'balloon' then 10
    when 'confetti' then 10 when 'party_popper' then 100 when 'fireworks' then 350
    when 'champagne' then 250 when 'crown' then 100 when 'sparkle' then 10
    when 'diamond' then 250 when 'trophy' then 500 when 'royal_crown' then 2000
    when 'super_car' then 1000 when 'private_jet' then 5000 when 'yacht' then 7000
    when 'luxury_villa' then 8000 when 'superbike' then 2500 when 'royal_palace' then 15000
    when 'rocket' then 10000 when 'golden_phoenix' then 18000
    when 'treasure_chest' then 6000 when 'magic_dragon' then 25000
    when 'shooting_star' then 1200 when 'golden_guitar' then 2200
    when 'moon' then 10 when 'clover' then 10 when 'music_note' then 10
    when 'galaxy' then 12000 when 'golden_star' then 1500 when 'magic_wand' then 750
    else null
  end;
  if v_cost is null then raise exception 'INVALID_GIFT'; end if;

  if not exists (select 1 from auth.users where id = p_recipient_id) then
    raise exception 'INVALID_RECIPIENT';
  end if;

  select balance into v_balance
  from public.user_coins
  where user_id = v_sender_id
  for update;
  if not found then raise exception 'COIN_WALLET_NOT_FOUND'; end if;
  if coalesce(v_balance, 0) < v_cost then raise exception 'INSUFFICIENT_COINS'; end if;

  update public.user_coins set balance = balance - v_cost where user_id = v_sender_id;
  insert into public.chat_gifts(sender_id, recipient_id, gift_code, coin_cost)
  values (v_sender_id, p_recipient_id, p_gift_code, v_cost)
  returning id into v_gift_id;

  -- Also add a normal chat event so both people see the gift in their conversation.
  insert into public.messages(sender_id, receiver_id, message)
  values (v_sender_id, p_recipient_id, 'GIFT:' || p_gift_code);

  return v_gift_id;
end;
$$;
revoke all on function public.send_chat_gift(uuid, text) from public, anon;
grant execute on function public.send_chat_gift(uuid, text) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_gifts'
  ) then
    alter publication supabase_realtime add table public.chat_gifts;
  end if;
end $$;
