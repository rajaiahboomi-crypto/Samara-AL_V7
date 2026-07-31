begin;

alter table public.profiles add column if not exists auth_email text;

update public.profiles
set auth_email = 'admin@users.samaracare.local'
where login_id = 'admin' and coalesce(auth_email,'') = '';

create unique index if not exists profiles_auth_email_unique
on public.profiles (lower(auth_email))
where auth_email is not null;

create or replace function public.samara_login_email(p_login_id text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select auth_email
  from public.profiles
  where login_id = lower(trim(p_login_id)) and active = true
  limit 1;
$$;

revoke all on function public.samara_login_email(text) from public;
grant execute on function public.samara_login_email(text) to anon, authenticated;

drop function if exists public.samara_admin_save_employee(uuid,text,text,text,text,text,boolean);
drop function if exists public.samara_admin_save_employee(uuid,text,text,text,text,text,text,boolean);

create function public.samara_admin_save_employee(
  p_user_id uuid,
  p_login_id text,
  p_auth_email text,
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
declare result public.profiles;
begin
  if not public.samara_is_admin() then raise exception 'Administrator permission required'; end if;
  if p_role not in ('Admin','Manager','Nurse','Caregiver','Accounts','Kitchen') then raise exception 'Invalid role'; end if;
  if position('@' in trim(p_auth_email)) = 0 then raise exception 'A valid employee email is required'; end if;

  insert into public.profiles(id,login_id,auth_email,full_name,role,employee_id,mobile,active,updated_at)
  values(p_user_id,lower(trim(p_login_id)),lower(trim(p_auth_email)),trim(p_full_name),p_role,nullif(trim(p_employee_id),''),nullif(trim(p_mobile),''),p_active,now())
  on conflict (id) do update set
    login_id=excluded.login_id,
    auth_email=excluded.auth_email,
    full_name=excluded.full_name,
    role=excluded.role,
    employee_id=excluded.employee_id,
    mobile=excluded.mobile,
    active=excluded.active,
    updated_at=now()
  returning * into result;
  return result;
end;
$$;

revoke all on function public.samara_admin_save_employee(uuid,text,text,text,text,text,text,boolean) from public;
grant execute on function public.samara_admin_save_employee(uuid,text,text,text,text,text,text,boolean) to authenticated;

commit;

select 'SAMARA CARE V10 EMAIL LOGIN UPGRADE COMPLETED SUCCESSFULLY' as result;
