-- ============================================================================
-- SMART CANTEEN MANAGEMENT & FOOD DEMAND PREDICTION SYSTEM (UCS531)
-- Complete PostgreSQL Schema, RLS Policies, Seed Data & Cloud RPC
-- Run this entire script inside Supabase -> SQL Editor -> New Query -> Run
-- ============================================================================

-- 1. Enable UUID extension
create extension if not exists "uuid-ossp";

-- 2. Profiles / Users table
create table if not exists public.profiles (
  id uuid primary key default uuid_generate_v4(),
  roll_number text unique not null,
  full_name text not null,
  email text unique not null,
  role text not null default 'student' check (role in ('student', 'admin')),
  created_at timestamptz default now()
);

-- 3. Menu Items table
create table if not exists public.menu_items (
  id uuid primary key default uuid_generate_v4(),
  name text not null unique,
  category text not null default 'Main Course',
  price numeric(10,2) not null default 50.00,
  historical_avg integer not null default 50,
  is_available_today boolean not null default true,
  calories integer default 450,
  prep_time_mins integer default 15,
  created_at timestamptz default now()
);

-- 4. Meal Preferences table (One preference per student per item per date)
create table if not exists public.meal_preferences (
  id uuid primary key default uuid_generate_v4(),
  student_roll text not null,
  student_name text not null,
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  quantity integer not null default 1 check (quantity between 1 and 5),
  meal_date date not null default current_date,
  updated_at timestamptz default now(),
  unique(student_roll, menu_item_id, meal_date)
);

-- 5. Daily Preparation, Prediction & Wastage Records
create table if not exists public.daily_records (
  id uuid primary key default uuid_generate_v4(),
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  record_date date not null default current_date,
  current_preferences integer not null default 0,
  historical_avg integer not null default 0,
  predicted_demand integer not null default 0,
  prepared_qty integer not null default 0,
  sold_qty integer not null default 0,
  leftover_qty integer generated always as (greatest(prepared_qty - sold_qty, 0)) stored,
  wastage_pct numeric(5,2) generated always as (
    case when prepared_qty > 0
    then round((greatest(prepared_qty - sold_qty, 0)::numeric / prepared_qty::numeric) * 100, 2)
    else 0 end
  ) stored,
  created_at timestamptz default now(),
  unique(menu_item_id, record_date)
);

-- 6. Disable RLS for smooth hackathon/viva demo (or allow public anon read/write)
alter table public.profiles enable row level security;
alter table public.menu_items enable row level security;
alter table public.meal_preferences enable row level security;
alter table public.daily_records enable row level security;

drop policy if exists "Public full access profiles" on public.profiles;
create policy "Public full access profiles" on public.profiles for all using (true) with check (true);

drop policy if exists "Public full access menu_items" on public.menu_items;
create policy "Public full access menu_items" on public.menu_items for all using (true) with check (true);

drop policy if exists "Public full access meal_preferences" on public.meal_preferences;
create policy "Public full access meal_preferences" on public.meal_preferences for all using (true) with check (true);

drop policy if exists "Public full access daily_records" on public.daily_records;
create policy "Public full access daily_records" on public.daily_records for all using (true) with check (true);

-- 7. Cloud Database Function (Serverless SQL RPC for Demand Prediction)
-- Formula: Predicted Demand = ROUND(0.7 * Current_Preferences + 0.3 * Historical_Average)
create or replace function public.run_demand_prediction(target_date date default current_date)
returns table (
  item_id uuid,
  item_name text,
  current_prefs integer,
  hist_avg integer,
  predicted integer
)
language plpgsql
security definer
as $$
begin
  return query
  with pref_counts as (
    select
      m.id as m_id,
      m.name as m_name,
      coalesce(sum(p.quantity), 0)::integer as cur_p,
      m.historical_avg as h_avg,
      round(0.7 * coalesce(sum(p.quantity), 0) + 0.3 * m.historical_avg)::integer as pred
    from public.menu_items m
    left join public.meal_preferences p
      on p.menu_item_id = m.id and p.meal_date = target_date
    where m.is_available_today = true
    group by m.id, m.name, m.historical_avg
  )
  insert into public.daily_records (menu_item_id, record_date, current_preferences, historical_avg, predicted_demand)
  select m_id, target_date, cur_p, h_avg, pred from pref_counts
  on conflict (menu_item_id, record_date)
  do update set
    current_preferences = excluded.current_preferences,
    historical_avg = excluded.historical_avg,
    predicted_demand = excluded.predicted_demand
  returning
    daily_records.menu_item_id,
    (select name from public.menu_items where id = daily_records.menu_item_id),
    daily_records.current_preferences,
    daily_records.historical_avg,
    daily_records.predicted_demand;
end;
$$;

-- 8. Seed Initial Menu Items
insert into public.menu_items (name, category, price, historical_avg, is_available_today, calories, prep_time_mins)
values
  ('Chole Bhature', 'North Indian', 60.00, 90, true, 620, 15),
  ('Masala Dosa', 'South Indian', 55.00, 65, true, 410, 12),
  ('Paneer Grilled Sandwich', 'Snacks', 45.00, 50, true, 360, 10),
  ('Rajma Chawal Bowl', 'Thali & Bowls', 65.00, 80, true, 540, 10),
  ('Veg Hakka Noodles', 'Indo-Chinese', 50.00, 55, true, 480, 14),
  ('Cold Coffee & Samosa Combo', 'Beverages', 40.00, 75, true, 390, 5)
on conflict (name) do nothing;

-- 9. Seed Sample Student Preferences for Today (so dashboard looks alive immediately!)
insert into public.meal_preferences (student_roll, student_name, menu_item_id, quantity, meal_date)
select '1024031074', 'Gurman Singh', id, 1, current_date from public.menu_items where name = 'Chole Bhature'
on conflict do nothing;

insert into public.meal_preferences (student_roll, student_name, menu_item_id, quantity, meal_date)
select '1024031064', 'Priyancy Ajmani', id, 1, current_date from public.menu_items where name = 'Masala Dosa'
on conflict do nothing;

insert into public.meal_preferences (student_roll, student_name, menu_item_id, quantity, meal_date)
select '1024030881', 'Aarav Sharma', id, 2, current_date from public.menu_items where name = 'Chole Bhature'
on conflict do nothing;

-- 10. Seed Past 6 Days of Historical Wastage Analytics (for Weekly Wastage Chart)
do $$
declare
  cb_id uuid;
  dosa_id uuid;
  rajma_id uuid;
begin
  select id into cb_id from public.menu_items where name = 'Chole Bhature' limit 1;
  select id into dosa_id from public.menu_items where name = 'Masala Dosa' limit 1;
  select id into rajma_id from public.menu_items where name = 'Rajma Chawal Bowl' limit 1;

  if cb_id is not null then
    insert into public.daily_records (menu_item_id, record_date, current_preferences, historical_avg, predicted_demand, prepared_qty, sold_qty)
    values
      (cb_id, current_date - 6, 78, 90, 82, 95, 76),
      (cb_id, current_date - 5, 84, 90, 86, 90, 83),
      (cb_id, current_date - 4, 65, 90, 73, 75, 70),
      (cb_id, current_date - 3, 88, 90, 89, 90, 87),
      (cb_id, current_date - 2, 72, 90, 77, 80, 75),
      (cb_id, current_date - 1, 80, 90, 83, 85, 82)
    on conflict (menu_item_id, record_date) do nothing;
  end if;

  if dosa_id is not null then
    insert into public.daily_records (menu_item_id, record_date, current_preferences, historical_avg, predicted_demand, prepared_qty, sold_qty)
    values
      (dosa_id, current_date - 3, 55, 65, 58, 60, 56),
      (dosa_id, current_date - 2, 60, 65, 62, 65, 60),
      (dosa_id, current_date - 1, 58, 65, 60, 62, 59)
    on conflict (menu_item_id, record_date) do nothing;
  end if;
end $$;

-- 11. Explicit API Role Grants (prevents permission issues on newer Supabase projects)
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
grant all on all sequences in schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
