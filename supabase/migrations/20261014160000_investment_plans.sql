alter table public.profiles
  add column if not exists selected_plan text,
  add column if not exists selected_plan_at timestamptz;

update public.profiles p
set selected_plan = u.raw_user_meta_data ->> 'investment_plan',
    selected_plan_at = coalesce(p.selected_plan_at, now())
from auth.users u
where u.id = p.id
  and p.selected_plan is null
  and u.raw_user_meta_data ? 'investment_plan';
