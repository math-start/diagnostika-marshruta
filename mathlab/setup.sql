-- Math/Lab database setup. Execute once in Supabase SQL Editor.
create extension if not exists pgcrypto;
create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id),
  name text not null,
  code text unique not null,
  created_at timestamptz default now()
);
create table if not exists public.student_sessions (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id),
  student_name text not null,
  token_hash text unique not null,
  answers jsonb not null default '{}'::jsonb,
  score integer,
  finished boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists student_sessions_class_idx on public.student_sessions(class_id);
alter table public.classes enable row level security;
alter table public.student_sessions enable row level security;
drop policy if exists teacher_classes on public.classes;
create policy teacher_classes on public.classes for all to authenticated
  using (teacher_id=auth.uid()) with check (teacher_id=auth.uid());
drop policy if exists teacher_sessions on public.student_sessions;
create policy teacher_sessions on public.student_sessions for select to authenticated
  using (exists(select 1 from public.classes c where c.id=class_id and c.teacher_id=auth.uid()));
create or replace function public.assign_teacher() returns trigger
 language plpgsql security definer set search_path=public as $$
begin
  new.teacher_id:=auth.uid();
  if new.teacher_id is null then raise exception 'Authentication required'; end if;
  return new;
end$$;
drop trigger if exists assign_teacher_trigger on public.classes;
create trigger assign_teacher_trigger before insert on public.classes
 for each row execute function public.assign_teacher();
revoke all on public.classes, public.student_sessions from anon;
grant select,insert on public.classes to authenticated;
grant select on public.student_sessions to authenticated;
create or replace function public.session_json(s public.student_sessions) returns jsonb
 language sql stable as $$
  select jsonb_build_object('student_name',s.student_name,'answers',s.answers,
    'score',s.score,'finished',s.finished,'updated_at',s.updated_at)
$$;
create or replace function public.start_student_session(p_name text,p_class_code text,p_token text) returns jsonb
 language plpgsql security definer set search_path=public as $$
declare c uuid; s public.student_sessions;
begin
  if length(trim(p_name))<1 or length(p_name)>80 or p_token !~ '^[A-Z2-9]{24}$' then
    raise exception 'Invalid input';
  end if;
  select id into c from public.classes where code=p_class_code;
  if c is null then raise exception 'Class code not found'; end if;
  insert into public.student_sessions(class_id,student_name,token_hash)
    values (c,trim(p_name),encode(digest(p_token,'sha256'),'hex')) returning * into s;
  return public.session_json(s);
end$$;
create or replace function public.get_student_session(p_token text) returns jsonb
 language plpgsql security definer set search_path=public as $$
declare s public.student_sessions;
begin
  select * into s from public.student_sessions
    where token_hash=encode(digest(p_token,'sha256'),'hex');
  if not found then raise exception 'Session not found'; end if;
  return public.session_json(s);
end$$;
create or replace function public.save_student_answers(p_token text,p_answers jsonb) returns jsonb
 language plpgsql security definer set search_path=public as $$
declare s public.student_sessions; k text;
begin
  if jsonb_typeof(p_answers)<>'object' or pg_column_size(p_answers)>4096 then
    raise exception 'Invalid answers';
  end if;
  for k in select jsonb_object_keys(p_answers) loop
    if k !~ '^[0-7]$' or jsonb_typeof(p_answers->k)<>'string'
      or length(p_answers->>k)>40 then raise exception 'Invalid answer'; end if;
  end loop;
  update public.student_sessions set answers=p_answers,updated_at=now()
    where token_hash=encode(digest(p_token,'sha256'),'hex') and not finished
    returning * into s;
  if not found then raise exception 'Session not found or already submitted'; end if;
  return public.session_json(s);
end$$;
create or replace function public.finish_student_session(p_token text) returns jsonb
 language plpgsql security definer set search_path=public as $$
declare s public.student_sessions;
 correct numeric[]:=array[400,840,8,6,0.35,7,36,80];
 i integer; v text; n numeric; points integer:=0;
begin
  select * into s from public.student_sessions
    where token_hash=encode(digest(p_token,'sha256'),'hex') for update;
  if not found then raise exception 'Session not found'; end if;
  if s.finished then return public.session_json(s); end if;
  for i in 0..7 loop
    v:=replace(trim(coalesce(s.answers->>i::text,'')),',','.');
    if v ~ '^[+-]?[0-9]{1,12}(\.[0-9]{1,8})?$' then
      n:=v::numeric;
      if abs(n-correct[i+1])<0.00001 then points:=points+1; end if;
    end if;
  end loop;
  update public.student_sessions set score=points, finished=true,updated_at=now()
    where id=s.id returning * into s;
  return public.session_json(s);
end$$;
revoke all on function public.session_json(public.student_sessions) from public;
revoke all on function public.start_student_session(text,text,text),
  public.get_student_session(text),public.save_student_answers(text,jsonb),
  public.finish_student_session(text) from public;
grant execute on function public.start_student_session(text,text,text),
  public.get_student_session(text),public.save_student_answers(text,jsonb),
  public.finish_student_session(text) to anon,authenticated;
