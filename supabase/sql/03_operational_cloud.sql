-- Samara Care shared operational database
-- Run after 01_setup.sql and 02_create_first_admin.sql.

create extension if not exists pgcrypto;

create or replace function public.is_active_staff()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active=true)
$$;
create or replace function public.has_role(allowed text[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active=true and role=any(allowed))
$$;
revoke all on function public.is_active_staff() from public;
revoke all on function public.has_role(text[]) from public;
grant execute on function public.is_active_staff(), public.has_role(text[]) to authenticated;

create table if not exists public.patients (
 id uuid primary key default gen_random_uuid(), patient_no text unique not null,
 full_name text not null, age integer check(age between 0 and 130), gender text,
 room_bed text, admission_date date not null default current_date, diagnosis text,
 emergency_contact text, care_level text not null default 'Assisted', status text not null default 'Active',
 created_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.care_records (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id) on delete cascade,
 activity text not null, status text not null default 'Completed', notes text,
 recorded_by uuid references public.profiles(id), recorded_at timestamptz not null default now()
);
create table if not exists public.vital_signs (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id) on delete cascade,
 bp text, pulse integer, temperature numeric(4,1), spo2 integer, alert text not null default 'Normal', notes text,
 recorded_by uuid references public.profiles(id), recorded_at timestamptz not null default now()
);
create table if not exists public.medicine_records (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id) on delete cascade,
 medicine text not null, scheduled_time time, status text not null default 'Pending', notes text,
 recorded_by uuid references public.profiles(id), administered_by uuid references public.profiles(id),
 administered_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.meal_records (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id) on delete cascade,
 meal text not null, diet_type text not null, consumption text not null, notes text,
 recorded_by uuid references public.profiles(id), recorded_at timestamptz not null default now()
);
create table if not exists public.billing_transactions (
 id uuid primary key default gen_random_uuid(), patient_id uuid not null references public.patients(id) on delete cascade,
 transaction_type text not null check(transaction_type in ('Charge','Payment')),
 amount numeric(12,2) not null check(amount>0), description text,
 recorded_by uuid references public.profiles(id), recorded_at timestamptz not null default now()
);
create table if not exists public.audit_log (
 id bigint generated always as identity primary key, table_name text not null, record_id uuid,
 action text not null, actor uuid references public.profiles(id), details jsonb, created_at timestamptz not null default now()
);

create index if not exists idx_care_patient_time on public.care_records(patient_id, recorded_at desc);
create index if not exists idx_vitals_patient_time on public.vital_signs(patient_id, recorded_at desc);
create index if not exists idx_meds_patient_time on public.medicine_records(patient_id, created_at desc);
create index if not exists idx_meals_patient_time on public.meal_records(patient_id, recorded_at desc);
create index if not exists idx_billing_patient_time on public.billing_transactions(patient_id, recorded_at desc);

alter table public.patients enable row level security;
alter table public.care_records enable row level security;
alter table public.vital_signs enable row level security;
alter table public.medicine_records enable row level security;
alter table public.meal_records enable row level security;
alter table public.billing_transactions enable row level security;
alter table public.audit_log enable row level security;

-- All active staff may read operational data.
do $$
declare t text;
begin
 foreach t in array array['patients','care_records','vital_signs','medicine_records','meal_records','billing_transactions'] loop
  execute format('drop policy if exists "Active staff read %1$s" on public.%1$I',t);
  execute format('create policy "Active staff read %1$s" on public.%1$I for select to authenticated using (public.is_active_staff())',t);
 end loop;
end $$;

-- Patient writes: Admin, Manager, Nurse; Accounts may read only.
create policy "Patient create" on public.patients for insert to authenticated with check(public.has_role(array['Admin','Manager','Nurse']));
create policy "Patient update" on public.patients for update to authenticated using(public.has_role(array['Admin','Manager','Nurse'])) with check(public.has_role(array['Admin','Manager','Nurse']));
create policy "Patient delete admin" on public.patients for delete to authenticated using(public.has_role(array['Admin']));

-- Care records: clinical/care roles create; managers/admin can amend/delete.
create policy "Care create" on public.care_records for insert to authenticated with check(public.has_role(array['Admin','Manager','Nurse','Caregiver']));
create policy "Care update" on public.care_records for update to authenticated using(public.has_role(array['Admin','Manager','Nurse'])) with check(public.has_role(array['Admin','Manager','Nurse']));
create policy "Care delete" on public.care_records for delete to authenticated using(public.has_role(array['Admin','Manager']));

create policy "Vitals create" on public.vital_signs for insert to authenticated with check(public.has_role(array['Admin','Manager','Nurse']));
create policy "Vitals update" on public.vital_signs for update to authenticated using(public.has_role(array['Admin','Manager','Nurse'])) with check(public.has_role(array['Admin','Manager','Nurse']));
create policy "Vitals delete" on public.vital_signs for delete to authenticated using(public.has_role(array['Admin','Manager']));

create policy "Medicines create" on public.medicine_records for insert to authenticated with check(public.has_role(array['Admin','Manager','Nurse']));
create policy "Medicines update" on public.medicine_records for update to authenticated using(public.has_role(array['Admin','Manager','Nurse'])) with check(public.has_role(array['Admin','Manager','Nurse']));
create policy "Medicines delete" on public.medicine_records for delete to authenticated using(public.has_role(array['Admin','Manager']));

create policy "Meals create" on public.meal_records for insert to authenticated with check(public.has_role(array['Admin','Manager','Nurse','Caregiver','Kitchen']));
create policy "Meals update" on public.meal_records for update to authenticated using(public.has_role(array['Admin','Manager','Nurse','Kitchen'])) with check(public.has_role(array['Admin','Manager','Nurse','Kitchen']));
create policy "Meals delete" on public.meal_records for delete to authenticated using(public.has_role(array['Admin','Manager']));

create policy "Billing create" on public.billing_transactions for insert to authenticated with check(public.has_role(array['Admin','Manager','Accounts']));
create policy "Billing update" on public.billing_transactions for update to authenticated using(public.has_role(array['Admin','Manager','Accounts'])) with check(public.has_role(array['Admin','Manager','Accounts']));
create policy "Billing delete" on public.billing_transactions for delete to authenticated using(public.has_role(array['Admin']));

create policy "Audit admins read" on public.audit_log for select to authenticated using(public.has_role(array['Admin','Manager']));

-- Staff directory names are visible to active employees for attribution in records.
create policy "Active staff read staff directory" on public.profiles for select to authenticated using(public.is_active_staff());

create or replace function public.touch_patient_updated_at() returns trigger language plpgsql as $$
begin new.updated_at:=now(); return new; end $$;

create or replace function public.samara_audit() returns trigger language plpgsql security definer set search_path=public as $$
declare rid uuid; payload jsonb;
begin
 payload:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 begin rid:=(payload->>'id')::uuid; exception when others then rid:=null; end;
 insert into public.audit_log(table_name,record_id,action,actor,details) values(tg_table_name,rid,tg_op,auth.uid(),payload);
 return case when tg_op='DELETE' then old else new end;
end $$;

do $$ declare t text; begin
 foreach t in array array['patients','care_records','vital_signs','medicine_records','meal_records','billing_transactions'] loop
  execute format('drop trigger if exists trg_%1$s_audit on public.%1$I',t);
  execute format('create trigger trg_%1$s_audit after insert or update or delete on public.%1$I for each row execute function public.samara_audit()',t);
 end loop;
end $$;

drop trigger if exists trg_patients_touch on public.patients;
create trigger trg_patients_touch before update on public.patients for each row execute function public.touch_patient_updated_at();

-- Enable realtime publication where possible.
do $$ declare t text; begin
 foreach t in array array['patients','care_records','vital_signs','medicine_records','meal_records','billing_transactions'] loop
  begin execute format('alter publication supabase_realtime add table public.%I',t); exception when duplicate_object then null; end;
 end loop;
end $$;

-- Optional demonstration data. Run only for a fresh system.
-- insert into public.patients(patient_no,full_name,age,gender,room_bed,admission_date,diagnosis,emergency_contact,care_level)
-- values ('P001','Sample Patient',72,'Male','101-A',current_date,'Post-discharge rehabilitation','Relative - 9000000000','Assisted');
