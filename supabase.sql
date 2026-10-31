-- Maquininha do Super Banco Imobiliário — estrutura no Supabase
-- Tabelas com prefixo sbi_ para não misturar com outros projetos.
-- Leitura liberada (anon); gravação só pelas funções abaixo, que validam saldo e sala.

create table if not exists public.sbi_rooms (
  code       text primary key check (code ~ '^[A-Z0-9]{4,6}$'),
  initial    bigint not null check (initial >= 0),
  salary     bigint not null check (salary >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.sbi_players (
  id      uuid primary key default gen_random_uuid(),
  room    text not null references public.sbi_rooms(code) on delete cascade,
  pos     int  not null,
  name    text not null check (char_length(name) between 1 and 20),
  color   text not null,
  balance bigint not null
);
create index if not exists sbi_players_room_idx on public.sbi_players(room);

create table if not exists public.sbi_ops (
  id         bigint generated always as identity primary key,
  room       text not null references public.sbi_rooms(code) on delete cascade,
  type       text not null check (type in ('pagar','receber','transferir','partida')),
  from_id    uuid references public.sbi_players(id) on delete cascade, -- null = Banco
  to_id      uuid references public.sbi_players(id) on delete cascade, -- null = Banco
  amount     bigint not null check (amount > 0),
  undone     boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists sbi_ops_room_idx on public.sbi_ops(room, id desc);

alter table public.sbi_rooms   enable row level security;
alter table public.sbi_players enable row level security;
alter table public.sbi_ops     enable row level security;

drop policy if exists sbi_rooms_read on public.sbi_rooms;
drop policy if exists sbi_players_read on public.sbi_players;
drop policy if exists sbi_ops_read on public.sbi_ops;
create policy sbi_rooms_read   on public.sbi_rooms   for select to anon, authenticated using (true);
create policy sbi_players_read on public.sbi_players for select to anon, authenticated using (true);
create policy sbi_ops_read     on public.sbi_ops     for select to anon, authenticated using (true);

-- Criar partida
create or replace function public.sbi_create_room(
  p_code text, p_initial bigint, p_salary bigint, p_names text[], p_colors text[]
) returns void
language plpgsql security definer set search_path = '' as $$
declare i int;
begin
  if array_length(p_names,1) is null or array_length(p_names,1) not between 2 and 6 then
    raise exception 'De 2 a 6 jogadores';
  end if;
  insert into public.sbi_rooms(code, initial, salary) values (upper(p_code), p_initial, p_salary);
  for i in 1..array_length(p_names,1) loop
    insert into public.sbi_players(room, pos, name, color, balance)
    values (upper(p_code), i, left(btrim(p_names[i]),20), p_colors[i], p_initial);
  end loop;
end $$;

-- Lançar operação (Banco = null)
create or replace function public.sbi_op(
  p_room text, p_type text, p_from uuid, p_to uuid, p_amount bigint
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_bal bigint;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Valor inválido'; end if;
  if p_from is null and p_to is null then raise exception 'Escolha um jogador'; end if;
  if p_from is not null and p_from = p_to then raise exception 'Escolha jogadores diferentes'; end if;
  if p_to is not null and not exists (select 1 from public.sbi_players where id = p_to and room = p_room) then
    raise exception 'Jogador não está nesta partida';
  end if;
  if p_from is not null then
    select balance into v_bal from public.sbi_players where id = p_from and room = p_room for update;
    if not found then raise exception 'Jogador não está nesta partida'; end if;
    if v_bal < p_amount then raise exception 'Saldo insuficiente'; end if;
    update public.sbi_players set balance = balance - p_amount where id = p_from;
  end if;
  if p_to is not null then
    update public.sbi_players set balance = balance + p_amount where id = p_to;
  end if;
  insert into public.sbi_ops(room, type, from_id, to_id, amount) values (p_room, p_type, p_from, p_to, p_amount);
end $$;

-- Desfazer a última operação da partida
create or replace function public.sbi_undo(p_room text) returns void
language plpgsql security definer set search_path = '' as $$
declare o public.sbi_ops;
begin
  select * into o from public.sbi_ops where room = p_room and not undone order by id desc limit 1 for update;
  if not found then raise exception 'Nada para desfazer'; end if;
  if o.from_id is not null then update public.sbi_players set balance = balance + o.amount where id = o.from_id; end if;
  if o.to_id   is not null then update public.sbi_players set balance = balance - o.amount where id = o.to_id;   end if;
  update public.sbi_ops set undone = true where id = o.id;
end $$;

revoke all on function public.sbi_create_room(text,bigint,bigint,text[],text[]) from public;
revoke all on function public.sbi_op(text,text,uuid,uuid,bigint) from public;
revoke all on function public.sbi_undo(text) from public;
grant execute on function public.sbi_create_room(text,bigint,bigint,text[],text[]) to anon, authenticated;
grant execute on function public.sbi_op(text,text,uuid,uuid,bigint) to anon, authenticated;
grant execute on function public.sbi_undo(text) to anon, authenticated;

-- Tempo real
do $$ begin
  begin alter publication supabase_realtime add table public.sbi_players; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.sbi_ops;     exception when duplicate_object then null; end;
end $$;
