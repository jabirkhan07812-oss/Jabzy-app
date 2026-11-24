-- JABZY Room Gifts: atomic coin debit + room gift event
-- Run this migration in Supabase SQL Editor before using the Room Gift button.

create table if not exists public.room_gifts (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.live_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  gift_code text not null check (gift_code in ('rose','heart','teddy','crown','diamond','trophy','super_car','royal_crown','private_jet','rocket')),
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
    when 'heart' then 25
    when 'teddy' then 50
    when 'crown' then 100
    when 'diamond' then 250
    when 'trophy' then 500
    when 'super_car' then 1000
    when 'royal_crown' then 2000
    when 'private_jet' then 5000
    when 'rocket' then 10000
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
