-- ============================================================
-- SAMARA CARE V9 - COMPLETE, IDEMPOTENT SUPABASE SETUP
-- Run this entire script once in a NEW Supabase SQL Editor query.
-- It can safely be run again if needed.
-- ============================================================

begin;

-- ---------- Profiles ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  login_id text unique not null,
  full_name text not null,
  role text not null default 'Caregiver' check (role in ('Admin','Manager','Nurse','Caregiver','Accounts','Kitchen')),
  employee_id text,
  mobile text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Make sure columns exist if this table came from an older version.
alter table public.profiles add column if not exists employee_id text;
alter table public.profiles add column if not exists mobile text;
alter table public.profiles add column if not exists active boolean not null default true;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

-- ---------- Operational tables ----------
create table if not exists public.patients (
  id uuid primary key default gen_random_uuid(),
  patient_code text unique not null,
  full_name text not null,
  age integer,
  gender text,
  room_bed text,
  admission_date date,
  diagnosis text,
  emergency_contact text,
  care_level text default 'Assisted',
  status text default 'Active',
  outstanding numeric(12,2) not null default 0,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.care_records (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  activity text not null,
  status text not null,
  remarks text,
  recorded_by uuid references public.profiles(id),
  recorded_at timestamptz not null default now()
);

create table if not exists public.vital_signs (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  blood_pressure text,
  spo2 numeric(5,2),
  temperature numeric(5,2),
  alert_level text default 'Normal',
  recorded_by uuid references public.profiles(id),
  recorded_at timestamptz not null default now()
);

create table if not exists public.medicine_records (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  medicine text not null,
  scheduled_time time,
  status text not null default 'Pending',
  administered_at timestamptz,
  recorded_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.meal_records (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  meal_type text not null,
  diet_type text,
  consumption text,
  recorded_by uuid references public.profiles(id),
  recorded_at timestamptz not null default now()
);

create table if not exists public.billing_transactions (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  transaction_type text not null check (transaction_type in ('Charge','Payment')),
  amount numeric(12,2) not null check (amount >= 0),
  description text,
  recorded_by uuid references public.profiles(id),
  recorded_at timestamptz not null default now()
);

-- ---------- Non-recursive security helper functions ----------
create or replace function public.samara_current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and active = true limit 1;
$$;

create or replace function public.samara_is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles where id = auth.uid() and active = true);
$$;

create or replace function public.samara_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'Admin' and active = true);
$$;

create or replace function public.samara_can_manage_finance()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.samara_current_role() in ('Admin','Manager','Accounts'), false);
$$;

revoke all on function public.samara_current_role() from public;
revoke all on function public.samara_is_active_staff() from public;
revoke all on function public.samara_is_admin() from public;
revoke all on function public.samara_can_manage_finance() from public;
grant execute on function public.samara_current_role() to authenticated;
grant execute on function public.samara_is_active_staff() to authenticated;
grant execute on function public.samara_is_admin() to authenticated;
grant execute on function public.samara_can_manage_finance() to authenticated;

-- Admin securely creates or updates a profile after the browser creates the Auth account.
create or replace function public.samara_admin_save_employee(
  p_user_id uuid,
  p_login_id text,
  p_full_name text,
  p_role text,
  p_employee_id text default null,
  p_mobile text default null,
  p_active boolean default true
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.profiles;
begin
  if not public.samara_is_admin() then
    raise exception 'Administrator permission required';
  end if;

  if p_role not in ('Admin','Manager','Nurse','Caregiver','Accounts','Kitchen') then
    raise exception 'Invalid role';
  end if;

  insert into public.profiles(id, login_id, full_name, role, employee_id, mobile, active, updated_at)
  values(p_user_id, lower(trim(p_login_id)), trim(p_full_name), p_role, nullif(trim(p_employee_id),''), nullif(trim(p_mobile),''), p_active, now())
  on conflict (id) do update set
    login_id = excluded.login_id,
    full_name = excluded.full_name,
    role = excluded.role,
    employee_id = excluded.employee_id,
    mobile = excluded.mobile,
    active = excluded.active,
    updated_at = now()
  returning * into result;

  return result;
end;
$$;

revoke all on function public.samara_admin_save_employee(uuid,text,text,text,text,text,boolean) from public;
grant execute on function public.samara_admin_save_employee(uuid,text,text,text,text,text,boolean) to authenticated;

-- Admin may activate/deactivate an employee profile.
create or replace function public.samara_admin_set_employee_active(p_user_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.samara_is_admin() then
    raise exception 'Administrator permission required';
  end if;
  if p_user_id = auth.uid() and p_active = false then
    raise exception 'Administrator cannot disable the currently logged-in account';
  end if;
  update public.profiles set active = p_active, updated_at = now() where id = p_user_id;
end;
$$;

revoke all on function public.samara_admin_set_employee_active(uuid,boolean) from public;
grant execute on function public.samara_admin_set_employee_active(uuid,boolean) to authenticated;

-- ---------- Remove all older policies to eliminate recursion/conflicts ----------
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies where schemaname='public' and tablename in ('profiles','patients','care_records','vital_signs','medicine_records','meal_records','billing_transactions')
  loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

-- ---------- RLS ----------
alter table public.profiles enable row level security;
alter table public.patients enable row level security;
alter table public.care_records enable row level security;
alter table public.vital_signs enable row level security;
alter table public.medicine_records enable row level security;
alter table public.meal_records enable row level security;
alter table public.billing_transactions enable row level security;

-- Profiles: active staff can read directory; admins write through RPC only.
create policy profiles_read_active_staff on public.profiles for select to authenticated using (public.samara_is_active_staff());

-- Patients: all active staff read; Admin/Manager/Nurse create/update.
create policy patients_read on public.patients for select to authenticated using (public.samara_is_active_staff());
create policy patients_insert on public.patients for insert to authenticated with check (public.samara_current_role() in ('Admin','Manager','Nurse'));
create policy patients_update on public.patients for update to authenticated using (public.samara_current_role() in ('Admin','Manager','Nurse')) with check (public.samara_current_role() in ('Admin','Manager','Nurse'));

-- Care, vitals, medicines and meals.
create policy care_read on public.care_records for select to authenticated using (public.samara_is_active_staff());
create policy care_insert on public.care_records for insert to authenticated with check (public.samara_current_role() in ('Admin','Manager','Nurse','Caregiver'));
create policy care_update on public.care_records for update to authenticated using (public.samara_current_role() in ('Admin','Manager','Nurse')) with check (public.samara_current_role() in ('Admin','Manager','Nurse'));

create policy vitals_read on public.vital_signs for select to authenticated using (public.samara_is_active_staff());
create policy vitals_insert on public.vital_signs for insert to authenticated with check (public.samara_current_role() in ('Admin','Manager','Nurse'));

create policy medicines_read on public.medicine_records for select to authenticated using (public.samara_is_active_staff());
create policy medicines_insert on public.medicine_records for insert to authenticated with check (public.samara_current_role() in ('Admin','Manager','Nurse'));
create policy medicines_update on public.medicine_records for update to authenticated using (public.samara_current_role() in ('Admin','Manager','Nurse')) with check (public.samara_current_role() in ('Admin','Manager','Nurse'));

create policy meals_read on public.meal_records for select to authenticated using (public.samara_is_active_staff());
create policy meals_insert on public.meal_records for insert to authenticated with check (public.samara_current_role() in ('Admin','Manager','Nurse','Caregiver','Kitchen'));

-- Finance restricted to Admin, Manager and Accounts.
create policy billing_read on public.billing_transactions for select to authenticated using (public.samara_can_manage_finance());
create policy billing_insert on public.billing_transactions for insert to authenticated with check (public.samara_can_manage_finance());

-- ---------- Grants ----------
grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant select, insert, update on public.patients to authenticated;
grant select, insert, update on public.care_records to authenticated;
grant select, insert on public.vital_signs to authenticated;
grant select, insert, update on public.medicine_records to authenticated;
grant select, insert on public.meal_records to authenticated;
grant select, insert on public.billing_transactions to authenticated;

-- ---------- Realtime ----------
do $$
begin
  begin alter publication supabase_realtime add table public.profiles; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.patients; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.care_records; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.vital_signs; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.medicine_records; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.meal_records; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.billing_transactions; exception when duplicate_object then null; end;
end $$;

commit;

select 'SAMARA CARE V9 SETUP COMPLETED SUCCESSFULLY' as result;
