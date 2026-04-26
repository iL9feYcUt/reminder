-- generate_reminders.sql
-- Supabase SQL: replace the generate_reminders() RPC with this implementation.
-- Usage: paste into Supabase SQL editor and run (it will create or replace the function).

/*
Rules implemented:
- Generate reminders for the next 7 days (today .. today+6)
- For each lesson found (special_schedule overrides weekly_schedule):
  - Create a 'preview' reminder at the lesson start datetime (use start_time if set, otherwise fall back to a default time by period)
  - Create a 'review' reminder at lesson start datetime + 7 days
- Skip inserting if a reminder with same user_id, title, type and due_date already exists
- Exclude days that are holidays or outside any registered term
- The function inserts reminders for the calling user (uses auth.uid())
*/

create or replace function public.generate_reminders()
returns void
language plpgsql
security definer
as $$
declare
  d date;
  rec record;
  lesson_start_time time;
  lesson_due timestamptz;
begin
  -- Special-day schedule first (explicit dates)
  for i in 0..6 loop
    d := current_date + i;
    -- skip holidays
    if exists (select 1 from public.holidays h where h.date = d) then
      continue;
    end if;

    -- ensure inside a term (if no term exists that contains the date, skip)
    if not exists (select 1 from public.terms t where d between t.start_date and t.end_date) then
      continue;
    end if;

    -- special schedules for that date: group by subject and pick earliest period/start_time
    for rec in
      select ss.subject, min(ss.period) as period, min(ss.start_time) as start_time
      from public.special_schedule ss
      where ss.date = d
      group by ss.subject
    loop
      -- compute start time (use special.start_time if present; otherwise default by period)
      lesson_start_time := coalesce(rec.start_time, 
        case when rec.period = 1 then time '09:10:00'
             when rec.period = 2 then time '10:10:00'
             when rec.period = 3 then time '11:10:00'
             when rec.period = 4 then time '12:10:00'
             when rec.period = 5 then time '13:40:00'
             when rec.period = 6 then time '14:40:00'
             when rec.period = 7 then time '15:40:00'
             when rec.period = 8 then time '16:40:00'
             else time '09:10:00' end);

      -- build timestamptz for Asia/Tokyo so local lesson time is stored correctly
      lesson_due := (d::timestamp + lesson_start_time) AT TIME ZONE 'Asia/Tokyo';

      -- preview
      if not exists (
        select 1 from public.reminders r
        where r.user_id = auth.uid() and r.type = 'preview' and r.title = rec.subject and r.due_date = lesson_due
      ) then
        insert into public.reminders (user_id, title, memo, type, due_date, created_at)
        values (auth.uid(), rec.subject, null, 'preview', lesson_due, now());
      end if;

      -- review (7 days later)
      if not exists (
        select 1 from public.reminders r
        where r.user_id = auth.uid() and r.type = 'review' and r.title = rec.subject and r.due_date = lesson_due + interval '7 days'
      ) then
        insert into public.reminders (user_id, title, memo, type, due_date, created_at)
        values (auth.uid(), rec.subject, null, 'review', lesson_due + interval '7 days', now());
      end if;
    end loop;

    -- weekly schedule for that weekday (only if no special_schedule exists for same period/date)
    -- weekly schedules for that weekday: group by subject to avoid multiple reminders for consecutive periods
    for rec in 
      select ws.subject, min(ws.period) as period, min(ws.start_time) as start_time
      from public.weekly_schedule ws
      where ws.day_of_week = extract(dow from d)::int
      group by ws.subject
    loop
      -- if a special_schedule exists for this date and same period, skip (special overrides weekly)
      if exists (select 1 from public.special_schedule ss where ss.date = d and ss.period = rec.period) then
        continue;
      end if;

      lesson_start_time := coalesce(rec.start_time, 
        case when rec.period = 1 then time '09:10:00'
             when rec.period = 2 then time '10:10:00'
             when rec.period = 3 then time '11:10:00'
             when rec.period = 4 then time '12:10:00'
             when rec.period = 5 then time '13:40:00'
             when rec.period = 6 then time '14:40:00'
             when rec.period = 7 then time '15:40:00'
             when rec.period = 8 then time '16:40:00'
             else time '09:10:00' end);

      -- build timestamptz for Asia/Tokyo so local lesson time is stored correctly
      lesson_due := (d::timestamp + lesson_start_time) AT TIME ZONE 'Asia/Tokyo';

      -- preview
      if not exists (
        select 1 from public.reminders r
        where r.user_id = auth.uid() and r.type = 'preview' and r.title = rec.subject and r.due_date = lesson_due
      ) then
        insert into public.reminders (user_id, title, memo, type, due_date, created_at)
        values (auth.uid(), rec.subject, null, 'preview', lesson_due, now());
      end if;

      -- review
      if not exists (
        select 1 from public.reminders r
        where r.user_id = auth.uid() and r.type = 'review' and r.title = rec.subject and r.due_date = lesson_due + interval '7 days'
      ) then
        insert into public.reminders (user_id, title, memo, type, due_date, created_at)
        values (auth.uid(), rec.subject, null, 'review', lesson_due + interval '7 days', now());
      end if;

    end loop;

  end loop;

end;
$$;

-- Notes:
-- - Run this in Supabase's SQL editor. If you use Row-Level Security that requires owner-based inserts, ensure the function runs with adequate privileges or set user_id appropriately in a BEFORE INSERT trigger.
-- - The function uses auth.uid() for the user_id; if you want this to run as an admin to populate multiple users, modify accordingly.
