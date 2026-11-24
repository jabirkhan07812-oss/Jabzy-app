-- Expand JABZY room gift catalog and keep server-side coin prices in sync.
-- Safe to run after 20261124_room_gifts.sql.
alter table public.room_gifts drop constraint if exists room_gifts_gift_code_check;
alter table public.room_gifts
  add constraint room_gifts_gift_code_check
  check (gift_code in ('rose','tulip','daisy','bouquet','sunflower','heart','crystal_heart','diamond_necklace','love_carousel','kiss','hug','pink_heart','love_letter','couple_ring','love_bear','teddy','paw_print','chick','puppy','kitten','bunny','birthday_cake','balloon','confetti','party_popper','fireworks','champagne','crown','sparkle','diamond','trophy','royal_crown','super_car','private_jet','yacht','luxury_villa','superbike','royal_palace','rocket','golden_phoenix','treasure_chest','magic_dragon','shooting_star','golden_guitar','moon','clover','music_note','galaxy','golden_star','magic_wand'));

-- JABZY Room Gifts: atomic coin debit + room gift event
-- Run this migration in Supabase SQL Editor before using the Room Gift button.

create table if not exists public.room_gifts (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.live_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  gift_code text not null check (gift_code in ('rose','tulip','daisy','bouquet','sunflower','heart','crystal_heart','diamond_necklace','love_carousel','kiss','hug','pink_heart','love_letter','couple_ring','love_bear','teddy','paw_print','chick','puppy','kitten','bunny','birthday_cake','balloon','confetti','party_popper','fireworks','champagne','crown','sparkle','diamond','trophy','royal_crown','super_car','private_jet','yacht','luxury_villa','superbike','royal_palace','rocket','golden_phoenix','treasure_chest','magic_dragon','shooting_star','golden_guitar','moon','clover','music_note','galaxy','golden_star','magic_wand')),
  coin_cost integer not null check (coin_cost > 0),
  created_at timestamptz not null default now(),
  constraint room_gifts_no_self_gift check (sender_id <> recipient_id)
);

create index if not exists room_gifts_room_created_idx
  on public.room_gifts(room_id, created_at desc);

alter table public.room_gifts enable row level security;

drop policy if exists "Room members can view room gifts" on public.room_gifts;
create policy "Room members can view room gifts"
on public.room_gifts for select to authenticated
using (
  exists (
    select 1 from public.live_rooms r
    where r.id = room_gifts.room_id
      and (
        r.created_by = auth.uid()
        or exists (
          select 1 from public.live_room_members m
          where m.room_id = r.id and m.user_id = auth.uid()
        )
      )
  )
);

revoke all on public.room_gifts from anon, authenticated;
grant select on public.room_gifts to authenticated;

create or replace function public.send_room_gift(
  p_room_id uuid,
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
  v_room_active boolean;
  v_sender_is_member boolean;
  v_recipient_is_member boolean;
begin
  if v_sender_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_cost := case p_gift_code
    when 'rose' then 10
    when 'tulip' then 10
    when 'daisy' then 10
      when 'bouquet' then 30
    when 'sunflower' then 40
      when 'heart' then 25
  when 'crystal_heart' then 350
  when 'diamond_necklace' then 1800
  when 'love_carousel' then 900
    when 'kiss' then 10
    when 'hug' then 10
    when 'pink_heart' then 10
    when 'love_letter' then 75
    when 'couple_ring' then 300
    when 'love_bear' then 450
    when 'teddy' then 50
    when 'paw_print' then 10
    when 'chick' then 10
    when 'puppy' then 80
    when 'kitten' then 90
    when 'bunny' then 120
    when 'birthday_cake' then 150
    when 'balloon' then 10
    when 'confetti' then 10
    when 'party_popper' then 100
    when 'fireworks' then 350
    when 'champagne' then 250
    when 'crown' then 100
    when 'sparkle' then 10
    when 'diamond' then 250
    when 'trophy' then 500
    when 'royal_crown' then 2000
    when 'super_car' then 1000
    when 'private_jet' then 5000
    when 'yacht' then 7000
    when 'luxury_villa' then 8000
  when 'superbike' then 2500
  when 'royal_palace' then 15000
    when 'rocket' then 10000
  when 'golden_phoenix' then 18000
  when 'treasure_chest' then 6000
  when 'magic_dragon' then 25000
  when 'shooting_star' then 1200
  when 'golden_guitar' then 2200
    when 'moon' then 10
    when 'clover' then 10
    when 'music_note' then 10
    when 'galaxy' then 12000
    when 'golden_star' then 1500
    when 'magic_wand' then 750
    else null
  end;
  if v_cost is null then raise exception 'INVALID_GIFT'; end if;
  if p_recipient_id is null or p_recipient_id = v_sender_id then
    raise exception 'INVALID_RECIPIENT';
  end if;

  select (r.status = 'active'),
         (r.created_by = v_sender_id or exists (
           select 1 from public.live_room_members m
           where m.room_id = r.id and m.user_id = v_sender_id
         )),
         (r.created_by = p_recipient_id or exists (
           select 1 from public.live_room_members m
           where m.room_id = r.id and m.user_id = p_recipient_id
         ))
    into v_room_active, v_sender_is_member, v_recipient_is_member
  from public.live_rooms r
  where r.id = p_room_id;

  if not found or v_room_active is distinct from true then
    raise exception 'ROOM_NOT_ACTIVE';
  end if;
  if v_sender_is_member is distinct from true then
    raise exception 'SENDER_NOT_IN_ROOM';
  end if;
  if v_recipient_is_member is distinct from true then
    raise exception 'RECIPIENT_NOT_IN_ROOM';
  end if;

  select balance into v_balance
  from public.user_coins
  where user_id = v_sender_id
  for update;

  if not found then raise exception 'COIN_WALLET_NOT_FOUND'; end if;
  if coalesce(v_balance, 0) < v_cost then raise exception 'INSUFFICIENT_COINS'; end if;

  update public.user_coins
  set balance = balance - v_cost
  where user_id = v_sender_id;

  insert into public.room_gifts(room_id, sender_id, recipient_id, gift_code, coin_cost)
  values (p_room_id, v_sender_id, p_recipient_id, p_gift_code, v_cost)
  returning id into v_gift_id;

  return v_gift_id;
end;
$$;

revoke all on function public.send_room_gift(uuid, uuid, text) from public, anon;
grant execute on function public.send_room_gift(uuid, uuid, text) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'room_gifts'
  ) then
    alter publication supabase_realtime add table public.room_gifts;
  end if;
end $$;
