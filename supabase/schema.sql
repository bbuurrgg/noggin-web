create extension if not exists pgcrypto;

do $$
begin
  if to_regclass('public.boards') is null and to_regclass('public.projects') is not null then
    alter table public.projects rename to boards;
  end if;

  if to_regclass('public.board_members') is null and to_regclass('public.project_members') is not null then
    alter table public.project_members rename to board_members;
  end if;

  if to_regclass('public.board_invites') is null and to_regclass('public.project_invites') is not null then
    alter table public.project_invites rename to board_invites;
  end if;

  if to_regclass('public.board_messages') is null and to_regclass('public.project_messages') is not null then
    alter table public.project_messages rename to board_messages;
  end if;

  if to_regclass('public.board_activity') is null and to_regclass('public.project_activity') is not null then
    alter table public.project_activity rename to board_activity;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'board_members' and column_name = 'project_id'
  ) then
    alter table public.board_members rename column project_id to board_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'board_invites' and column_name = 'project_id'
  ) then
    alter table public.board_invites rename column project_id to board_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'stages' and column_name = 'project_id'
  ) then
    alter table public.stages rename column project_id to board_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tasks' and column_name = 'project_id'
  ) then
    alter table public.tasks rename column project_id to board_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'task_comments' and column_name = 'project_id'
  ) then
    alter table public.task_comments rename column project_id to board_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'board_messages' and column_name = 'project_id'
  ) then
    alter table public.board_messages rename column project_id to board_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'board_activity' and column_name = 'project_id'
  ) then
    alter table public.board_activity rename column project_id to board_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'notifications' and column_name = 'project_id'
  ) then
    alter table public.notifications rename column project_id to board_id;
  end if;
end;
$$;

drop policy if exists "Task attachments are visible for accessible projects" on storage.objects;
drop policy if exists "Editors can upload task attachments" on storage.objects;
drop policy if exists "Editors can update task attachments" on storage.objects;
drop policy if exists "Editors can delete task attachments" on storage.objects;
drop policy if exists "Projects are visible to owners and members" on public.boards;
drop policy if exists "Users can create owned projects" on public.boards;
drop policy if exists "Owners and editors can update projects" on public.boards;
drop policy if exists "Owners can delete projects" on public.boards;
drop policy if exists "Members are visible inside accessible projects" on public.board_members;
drop policy if exists "Owners can manage members" on public.board_members;
drop policy if exists "Invitees can accept project membership" on public.board_members;
drop policy if exists "Invites are visible inside accessible projects" on public.board_invites;
drop policy if exists "Owners can manage invites" on public.board_invites;
drop policy if exists "Invitees can accept their own invites" on public.board_invites;
drop policy if exists "Invitees can decline their own invites" on public.board_invites;
drop policy if exists "Stages are visible inside accessible projects" on public.stages;
drop policy if exists "Owners and editors can manage stages" on public.stages;
drop policy if exists "Tasks are visible inside accessible projects" on public.tasks;
drop policy if exists "Owners and editors can manage tasks" on public.tasks;
drop policy if exists "Comments are visible inside accessible projects" on public.task_comments;
drop policy if exists "Owners and editors can add comments" on public.task_comments;
drop policy if exists "Comment authors can update comments" on public.task_comments;
drop policy if exists "Comment authors and owners can delete comments" on public.task_comments;
drop policy if exists "Messages are visible inside accessible projects" on public.board_messages;
drop policy if exists "Project collaborators can send messages" on public.board_messages;
drop policy if exists "Message authors can update messages" on public.board_messages;
drop policy if exists "Message authors and owners can delete messages" on public.board_messages;
drop policy if exists "Activity is visible inside accessible projects" on public.board_activity;

drop trigger if exists project_activity_notify_members on public.board_activity;
drop trigger if exists project_messages_notify_members on public.board_messages;
drop trigger if exists project_invites_notify_invitee on public.board_invites;
drop trigger if exists board_messages_notify_mentions on public.board_messages;
drop trigger if exists task_comments_notify_mentions on public.task_comments;
drop function if exists public.list_project_members(uuid);
drop function if exists public.list_project_invites(uuid);
drop function if exists public.invite_project_member_by_email(uuid, text, text);
drop function if exists public.cancel_project_invite(uuid, uuid);
drop function if exists public.delete_owned_project(uuid);
drop function if exists public.remove_project_member(uuid, uuid);
drop function if exists public.leave_project(uuid);
drop function if exists public.update_project_member_role(uuid, uuid, text);
drop function if exists public.list_my_pending_project_invites();
drop function if exists public.accept_project_invite(uuid);
drop function if exists public.decline_project_invite(uuid);
drop function if exists public.login_email_for_username(text);
drop function if exists public.notify_project_members(uuid, uuid, text, uuid, text, jsonb, text);
drop function if exists public.notify_project_activity();
drop function if exists public.notify_project_message();
drop function if exists public.notify_project_invite();
drop function if exists public.notify_board_mentions(uuid, uuid, text, uuid, uuid, uuid, text);
drop function if exists public.notify_board_message_mentions();
drop function if exists public.notify_task_comment_mentions();
drop function if exists public.can_access_project(uuid);
drop function if exists public.can_edit_project(uuid);

create table if not exists public.boards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  board_type text not null default 'project'
    check (board_type in ('project', 'list')),
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null
    check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text not null check (char_length(display_name) between 1 and 80),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.board_members (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.boards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'editor'
    check (role in ('owner', 'editor', 'viewer')),
  created_at timestamptz not null default now(),
  unique (board_id, user_id)
);

create table if not exists public.board_invites (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.boards(id) on delete cascade,
  email text not null,
  role text not null default 'editor'
    check (role in ('editor', 'viewer')),
  invited_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  unique (board_id, email)
);

create table if not exists public.stages (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.boards(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 64),
  sort_order integer not null default 0,
  color_value integer
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.boards(id) on delete cascade,
  assignee_id uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  title text not null check (char_length(title) between 1 and 160),
  description text,
  status text not null,
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'urgent')),
  sort_order integer not null default 0,
  due_at timestamptz,
  attachment_urls text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  board_id uuid not null references public.boards(id) on delete cascade,
  author_id uuid references auth.users(id) on delete set null,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.board_messages (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.boards(id) on delete cascade,
  author_id uuid references auth.users(id) on delete set null,
  reply_to_message_id uuid references public.board_messages(id) on delete set null,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.board_message_reactions (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.boards(id) on delete cascade,
  message_id uuid not null references public.board_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);

create table if not exists public.board_activity (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.boards(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  task_id uuid references public.tasks(id) on delete set null,
  stage_id uuid references public.stages(id) on delete set null,
  subject text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  board_id uuid references public.boards(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  notification_type text not null
    check (notification_type in ('chat', 'invite', 'mention', 'task_created', 'task_updated', 'task_moved', 'comment_added')),
  task_id uuid references public.tasks(id) on delete cascade,
  subject text,
  metadata jsonb not null default '{}'::jsonb,
  source_key text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (recipient_id, source_key)
);

alter table public.notifications drop constraint if exists notifications_notification_type_check;
alter table public.notifications add constraint notifications_notification_type_check
  check (notification_type in ('chat', 'invite', 'mention', 'task_created', 'task_updated', 'task_moved', 'comment_added'));

create table if not exists public.drive_file_links (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references public.boards(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete cascade,
  message_id uuid references public.board_messages(id) on delete cascade,
  provider text not null default 'google_drive'
    check (provider = 'google_drive'),
  file_id text not null,
  file_type text not null default 'file'
    check (file_type in ('document', 'spreadsheet', 'presentation', 'drawing', 'form', 'folder', 'file')),
  title text not null check (char_length(title) between 1 and 300),
  url text not null,
  mime_type text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(task_id, message_id) = 1)
);

alter table public.tasks drop constraint if exists tasks_status_check;
alter table public.boards drop constraint if exists boards_board_type_check;
alter table public.boards add column if not exists board_type text not null default 'project';
alter table public.boards add constraint boards_board_type_check
  check (board_type in ('project', 'list'));
alter table public.tasks alter column status drop default;
alter table public.tasks drop constraint if exists tasks_priority_check;
alter table public.tasks add column if not exists priority text not null default 'medium';
alter table public.tasks add constraint tasks_priority_check
  check (priority in ('low', 'medium', 'high', 'urgent'));
alter table public.tasks add column if not exists assignee_id uuid references auth.users(id) on delete set null;
alter table public.tasks add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.tasks add column if not exists updated_by uuid references auth.users(id) on delete set null;
alter table public.tasks add column if not exists due_at timestamptz;
alter table public.tasks add column if not exists attachment_urls text[] not null default '{}';
alter table public.board_messages add column if not exists reply_to_message_id uuid references public.board_messages(id) on delete set null;

insert into storage.buckets (id, name, public)
values ('task-attachments', 'task-attachments', true)
on conflict (id) do update set public = true;

alter table public.boards replica identity full;
alter table public.user_profiles replica identity full;
alter table public.board_members replica identity full;
alter table public.board_invites replica identity full;
alter table public.stages replica identity full;
alter table public.tasks replica identity full;
alter table public.task_comments replica identity full;
alter table public.board_messages replica identity full;
alter table public.board_message_reactions replica identity full;
alter table public.board_activity replica identity full;
alter table public.notifications replica identity full;
alter table public.drive_file_links replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.user_profiles;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.boards;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.board_members;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.board_invites;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.stages;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.tasks;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.task_comments;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.board_messages;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.board_message_reactions;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.board_activity;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.drive_file_links;
exception
  when duplicate_object or undefined_object then null;
end;
$$;

create index if not exists boards_owner_id_idx on public.boards(owner_id);
create unique index if not exists user_profiles_username_unique_idx
  on public.user_profiles(lower(username));
create index if not exists board_members_user_id_idx on public.board_members(user_id);
create index if not exists board_invites_email_idx on public.board_invites(lower(email));
create index if not exists stages_board_id_idx on public.stages(board_id);
create unique index if not exists stages_board_id_name_unique_idx
  on public.stages(board_id, lower(btrim(name)));
create index if not exists tasks_board_id_idx on public.tasks(board_id);
create index if not exists tasks_assignee_id_idx on public.tasks(assignee_id);
create index if not exists tasks_due_at_idx on public.tasks(due_at);
create index if not exists task_comments_task_id_idx on public.task_comments(task_id);
create index if not exists task_comments_board_id_idx on public.task_comments(board_id);
create index if not exists board_messages_board_id_idx on public.board_messages(board_id, created_at desc);
create index if not exists board_messages_reply_to_message_id_idx
  on public.board_messages(reply_to_message_id);
create index if not exists board_message_reactions_board_id_idx
  on public.board_message_reactions(board_id);
create index if not exists board_message_reactions_message_id_idx
  on public.board_message_reactions(message_id);
create index if not exists board_activity_board_id_idx on public.board_activity(board_id, created_at desc);
create index if not exists notifications_recipient_unread_idx
  on public.notifications(recipient_id, created_at desc)
  where read_at is null;
create index if not exists notifications_board_id_idx on public.notifications(board_id);
create index if not exists drive_file_links_board_id_idx on public.drive_file_links(board_id);
create index if not exists drive_file_links_task_id_idx on public.drive_file_links(task_id);
create index if not exists drive_file_links_message_id_idx on public.drive_file_links(message_id);
create unique index if not exists drive_file_links_task_file_unique_idx
  on public.drive_file_links(task_id, file_id)
  where task_id is not null;
create unique index if not exists drive_file_links_message_file_unique_idx
  on public.drive_file_links(message_id, file_id)
  where message_id is not null;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists boards_set_updated_at on public.boards;
create trigger boards_set_updated_at
before update on public.boards
for each row execute function public.set_updated_at();

drop trigger if exists user_profiles_set_updated_at on public.user_profiles;
create trigger user_profiles_set_updated_at
before update on public.user_profiles
for each row execute function public.set_updated_at();

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at
before update on public.tasks
for each row execute function public.set_updated_at();

drop trigger if exists task_comments_set_updated_at on public.task_comments;
create trigger task_comments_set_updated_at
before update on public.task_comments
for each row execute function public.set_updated_at();

drop trigger if exists board_messages_set_updated_at on public.board_messages;
create trigger board_messages_set_updated_at
before update on public.board_messages
for each row execute function public.set_updated_at();

drop trigger if exists drive_file_links_set_updated_at on public.drive_file_links;
create trigger drive_file_links_set_updated_at
before update on public.drive_file_links
for each row execute function public.set_updated_at();

create or replace function public.set_task_audit_fields()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by = coalesce(new.created_by, auth.uid());
    new.updated_by = coalesce(new.updated_by, auth.uid());
  elsif tg_op = 'UPDATE' then
    new.created_by = old.created_by;
    new.updated_by = auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_set_audit_fields on public.tasks;
create trigger tasks_set_audit_fields
before insert or update on public.tasks
for each row execute function public.set_task_audit_fields();

create or replace function public.log_task_activity()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  action text;
  task_title text;
begin
  if tg_op = 'INSERT' then
    action := 'task_created';
    task_title := new.title;
    insert into public.board_activity (board_id, actor_id, event_type, task_id, subject, metadata)
    values (new.board_id, auth.uid(), action, new.id, task_title, jsonb_build_object('status', new.status));
    return new;
  elsif tg_op = 'UPDATE' then
    task_title := new.title;
    if new.status is distinct from old.status then
      action := 'task_moved';
    elsif new.assignee_id is distinct from old.assignee_id then
      action := 'task_assigned';
    else
      action := 'task_updated';
    end if;
    insert into public.board_activity (board_id, actor_id, event_type, task_id, subject, metadata)
    values (
      new.board_id,
      auth.uid(),
      action,
      new.id,
      task_title,
      jsonb_build_object(
        'old_status', old.status,
        'new_status', new.status,
        'old_assignee_id', old.assignee_id,
        'new_assignee_id', new.assignee_id
      )
    );
    return new;
  elsif tg_op = 'DELETE' then
    insert into public.board_activity (board_id, actor_id, event_type, task_id, subject, metadata)
    values (old.board_id, auth.uid(), 'task_deleted', null, old.title, jsonb_build_object('task_id', old.id));
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists tasks_log_activity on public.tasks;
create trigger tasks_log_activity
after insert or update or delete on public.tasks
for each row execute function public.log_task_activity();

create or replace function public.log_comment_activity()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.board_activity (board_id, actor_id, event_type, task_id, subject, metadata)
    values (new.board_id, auth.uid(), 'comment_added', new.task_id, left(new.body, 120), '{}'::jsonb);
    return new;
  end if;
  return new;
end;
$$;

drop trigger if exists task_comments_log_activity on public.task_comments;
create trigger task_comments_log_activity
after insert on public.task_comments
for each row execute function public.log_comment_activity();

drop trigger if exists board_messages_log_activity on public.board_messages;
drop function if exists public.log_board_message_activity();

create or replace function public.notify_board_members(
  target_board_id uuid,
  target_actor_id uuid,
  target_type text,
  target_task_id uuid,
  target_subject text,
  target_metadata jsonb,
  target_source_key text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  actor_email text;
  actor_display_name text;
begin
  if target_actor_id is not null then
    select
      u.email::text,
      nullif(up.display_name, '')
    into actor_email, actor_display_name
    from auth.users u
    left join public.user_profiles up on up.user_id = u.id
    where u.id = target_actor_id
    limit 1;
  end if;

  insert into public.notifications (
    recipient_id,
    board_id,
    actor_id,
    notification_type,
    task_id,
    subject,
    metadata,
    source_key,
    created_at,
    read_at
  )
  select
    recipient.user_id,
    target_board_id,
    target_actor_id,
    target_type,
    target_task_id,
    target_subject,
    target_metadata || jsonb_strip_nulls(
      jsonb_build_object(
        'actor_email', actor_email,
        'actor_display_name', actor_display_name
      )
    ),
    target_source_key || ':' || recipient.user_id::text,
    now(),
    null
  from (
    select p.owner_id as user_id
    from public.boards p
    where p.id = target_board_id

    union

    select pm.user_id
    from public.board_members pm
    where pm.board_id = target_board_id
  ) recipient
  where recipient.user_id is not null
    and (target_actor_id is null or recipient.user_id <> target_actor_id)
  on conflict (recipient_id, source_key)
  do update set
    actor_id = excluded.actor_id,
    subject = excluded.subject,
    metadata = excluded.metadata,
    created_at = excluded.created_at,
    read_at = null;
end;
$$;

create or replace function public.notify_board_activity()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  notification_type text;
begin
  notification_type := case new.event_type
    when 'task_created' then 'task_created'
    when 'task_moved' then 'task_moved'
    when 'task_assigned' then 'task_updated'
    when 'task_updated' then 'task_updated'
    when 'comment_added' then 'comment_added'
    else null
  end;

  if notification_type is null then
    return new;
  end if;

  perform public.notify_board_members(
    new.board_id,
    new.actor_id,
    notification_type,
    new.task_id,
    new.subject,
    new.metadata || jsonb_build_object('activity_id', new.id),
    'activity:' || new.id::text
  );

  return new;
end;
$$;

drop trigger if exists board_activity_notify_members on public.board_activity;
create trigger board_activity_notify_members
after insert on public.board_activity
for each row execute function public.notify_board_activity();

create or replace function public.notify_board_message()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  perform public.notify_board_members(
    new.board_id,
    new.author_id,
    'chat',
    null,
    left(new.body, 120),
    jsonb_build_object('message_id', new.id),
    'chat:' || new.board_id::text || ':' || coalesce(new.author_id::text, 'unknown')
  );

  return new;
end;
$$;

drop trigger if exists board_messages_notify_members on public.board_messages;
create trigger board_messages_notify_members
after insert on public.board_messages
for each row execute function public.notify_board_message();

create or replace function public.notify_board_mentions(
  target_board_id uuid,
  target_actor_id uuid,
  target_body text,
  target_task_id uuid,
  target_message_id uuid,
  target_comment_id uuid,
  target_subject text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  actor_email text;
  actor_display_name text;
  mention_record record;
begin
  if target_body is null or target_body = '' then
    return;
  end if;

  if target_actor_id is not null then
    select
      u.email::text,
      nullif(up.display_name, '')
    into actor_email, actor_display_name
    from auth.users u
    left join public.user_profiles up on up.user_id = u.id
    where u.id = target_actor_id
    limit 1;
  end if;

  for mention_record in
    select distinct lower(matches.match[1]) as username
    from regexp_matches(target_body, '@([a-z0-9_]{3,24})', 'gi') as matches(match)
  loop
    insert into public.notifications (
      recipient_id,
      board_id,
      actor_id,
      notification_type,
      task_id,
      subject,
      metadata,
      source_key,
      created_at,
      read_at
    )
    select
      up.user_id,
      target_board_id,
      target_actor_id,
      'mention',
      target_task_id,
      target_subject,
      jsonb_strip_nulls(
        jsonb_build_object(
          'mentioned_username', mention_record.username,
          'message_id', target_message_id,
          'comment_id', target_comment_id,
          'actor_email', actor_email,
          'actor_display_name', actor_display_name
        )
      ),
      'mention:' || coalesce(target_message_id::text, target_comment_id::text) || ':' || up.user_id::text,
      now(),
      null
    from public.user_profiles up
    where lower(up.username) = mention_record.username
      and up.user_id is not null
      and (target_actor_id is null or up.user_id <> target_actor_id)
      and exists (
        select 1
        from public.boards b
        left join public.board_members bm
          on bm.board_id = b.id
          and bm.user_id = up.user_id
        where b.id = target_board_id
          and (b.owner_id = up.user_id or bm.user_id = up.user_id)
      )
    on conflict (recipient_id, source_key)
    do update set
      actor_id = excluded.actor_id,
      subject = excluded.subject,
      metadata = excluded.metadata,
      created_at = excluded.created_at,
      read_at = null;
  end loop;
end;
$$;

create or replace function public.notify_board_message_mentions()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  perform public.notify_board_mentions(
    new.board_id,
    new.author_id,
    new.body,
    null,
    new.id,
    null,
    left(new.body, 120)
  );

  return new;
end;
$$;

drop trigger if exists board_messages_notify_mentions on public.board_messages;
create trigger board_messages_notify_mentions
after insert on public.board_messages
for each row execute function public.notify_board_message_mentions();

create or replace function public.notify_task_comment_mentions()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  perform public.notify_board_mentions(
    new.board_id,
    new.author_id,
    new.body,
    new.task_id,
    null,
    new.id,
    left(new.body, 120)
  );

  return new;
end;
$$;

drop trigger if exists task_comments_notify_mentions on public.task_comments;
create trigger task_comments_notify_mentions
after insert on public.task_comments
for each row execute function public.notify_task_comment_mentions();

create or replace function public.notify_board_invite()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  invited_user_id uuid;
  inviter_email text;
  inviter_display_name text;
begin
  select
    u.email::text,
    nullif(up.display_name, '')
  into inviter_email, inviter_display_name
  from auth.users u
  left join public.user_profiles up on up.user_id = u.id
  where u.id = new.invited_by
  limit 1;

  select u.id
  into invited_user_id
  from auth.users u
  where lower(u.email) = lower(new.email)
  limit 1;

  if invited_user_id is null or invited_user_id = new.invited_by then
    return new;
  end if;

  insert into public.notifications (
    recipient_id,
    board_id,
    actor_id,
    notification_type,
    subject,
    metadata,
    source_key
  )
  values (
    invited_user_id,
    new.board_id,
    new.invited_by,
    'invite',
    new.email,
    jsonb_strip_nulls(
      jsonb_build_object(
        'invite_id', new.id,
        'role', new.role,
        'actor_email', inviter_email,
        'actor_display_name', inviter_display_name
      )
    ),
    'invite:' || new.id::text
  )
  on conflict (recipient_id, source_key)
  do update set
    actor_id = excluded.actor_id,
    subject = excluded.subject,
    metadata = excluded.metadata,
    created_at = now(),
    read_at = null;

  return new;
end;
$$;

drop trigger if exists board_invites_notify_invitee on public.board_invites;
create trigger board_invites_notify_invitee
after insert or update on public.board_invites
for each row
when (new.accepted_at is null)
execute function public.notify_board_invite();

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  requested_username text;
  requested_display_name text;
begin
  requested_username := lower(trim(coalesce(new.raw_user_meta_data ->> 'username', '')));
  requested_display_name := trim(coalesce(new.raw_user_meta_data ->> 'display_name', requested_username));

  if requested_username = '' then
    requested_username := lower(split_part(new.email, '@', 1));
  end if;

  requested_username := regexp_replace(requested_username, '[^a-z0-9_]', '_', 'g');
  requested_username := substring(requested_username from 1 for 24);

  if char_length(requested_username) < 3 then
    requested_username := requested_username || substring(replace(new.id::text, '-', '') from 1 for 3);
    requested_username := substring(requested_username from 1 for 24);
  end if;

  if requested_display_name = '' then
    requested_display_name := requested_username;
  end if;

  insert into public.user_profiles (user_id, username, display_name)
  values (new.id, requested_username, substring(requested_display_name from 1 for 80))
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists auth_users_create_profile on auth.users;
create trigger auth_users_create_profile
after insert on auth.users
for each row execute function public.handle_new_user_profile();

insert into public.user_profiles (user_id, username, display_name)
select
  u.id,
  substring(
    regexp_replace(lower(split_part(u.email, '@', 1)), '[^a-z0-9_]', '_', 'g')
    || '_'
    || substring(replace(u.id::text, '-', '') from 1 for 6)
    from 1 for 24
  ) as username,
  coalesce(nullif(split_part(u.email, '@', 1), ''), 'User') as display_name
from auth.users u
where not exists (
  select 1 from public.user_profiles up where up.user_id = u.id
)
on conflict do nothing;

create or replace function public.login_email_for_username(target_username text)
returns text
language sql
security definer
set search_path = public, auth
stable
as $$
  select u.email::text
  from public.user_profiles up
  join auth.users u on u.id = up.user_id
  where lower(up.username) = lower(trim(target_username))
    and trim(target_username) ~* '^[a-z0-9_]{3,24}$'
  limit 1;
$$;

-- PowerSync recommended publication
drop publication if exists powersync;
create publication powersync for table 
  public.user_profiles,
  public.boards, 
  public.board_members, 
  public.board_invites, 
  public.stages, 
  public.tasks, 
  public.task_comments, 
  public.board_messages,
  public.board_message_reactions,
  public.board_activity,
  public.drive_file_links;

create or replace function public.can_access_board(target_board_id uuid)
returns boolean
language sql
security definer
set search_path = public, auth
stable
as $$
  select exists (
    select 1
    from public.boards p
    left join public.board_members pm on pm.board_id = p.id
    where p.id = target_board_id
      and (p.owner_id = auth.uid() or pm.user_id = auth.uid())
  );
$$;

create or replace function public.can_edit_board(target_board_id uuid)
returns boolean
language sql
security definer
set search_path = public, auth
stable
as $$
  select exists (
    select 1
    from public.boards p
    left join public.board_members pm on pm.board_id = p.id
    where p.id = target_board_id
      and (
        p.owner_id = auth.uid()
        or (pm.user_id = auth.uid() and pm.role in ('owner', 'editor'))
      )
  );
$$;

drop function if exists public.list_board_members(uuid);
create or replace function public.list_board_members(target_board_id uuid)
returns table (
  user_id uuid,
  email text,
  username text,
  display_name text,
  avatar_url text,
  role text,
  created_at timestamptz,
  is_owner boolean
)
language sql
security definer
set search_path = public, auth
stable
as $$
  select
    u.id as user_id,
    u.email::text as email,
    up.username,
    up.display_name,
    up.avatar_url,
    coalesce(pm.role, 'owner') as role,
    coalesce(pm.created_at, p.created_at) as created_at,
    p.owner_id = u.id as is_owner
  from public.boards p
  join auth.users u on u.id = p.owner_id
  left join public.user_profiles up on up.user_id = u.id
  left join public.board_members pm
    on pm.board_id = p.id
    and pm.user_id = u.id
  where p.id = target_board_id
    and public.can_access_board(target_board_id)

  union all

  select
    u.id as user_id,
    u.email::text as email,
    up.username,
    up.display_name,
    up.avatar_url,
    pm.role,
    pm.created_at,
    false as is_owner
  from public.board_members pm
  join public.boards p on p.id = pm.board_id
  join auth.users u on u.id = pm.user_id
  left join public.user_profiles up on up.user_id = u.id
  where pm.board_id = target_board_id
    and pm.user_id <> p.owner_id
    and public.can_access_board(target_board_id)
  order by 8 desc, 4 asc, 2 asc;
$$;

create or replace function public.list_board_invites(target_board_id uuid)
returns table (
  id uuid,
  email text,
  role text,
  created_at timestamptz,
  accepted_at timestamptz
)
language sql
security definer
set search_path = public, auth
stable
as $$
  select
    pi.id,
    pi.email,
    pi.role,
    pi.created_at,
    pi.accepted_at
  from public.board_invites pi
  where pi.board_id = target_board_id
    and pi.accepted_at is null
    and public.can_access_board(target_board_id)
  order by pi.created_at desc;
$$;

drop function if exists public.invite_board_member_by_email(uuid, text, text);
create or replace function public.invite_board_member_by_email(
  target_board_id uuid,
  target_email text,
  target_role text default 'editor'
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  invited_user_id uuid;
  normalized_email text := lower(trim(target_email));
begin
  if normalized_email is null or normalized_email = '' then
    raise exception 'Email is required.';
  end if;

  if target_role not in ('editor', 'viewer') then
    raise exception 'Role must be editor or viewer.';
  end if;

  if not exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = auth.uid()
  ) then
    raise exception 'Only the board owner can invite collaborators.';
  end if;

  select u.id
  into invited_user_id
  from auth.users u
  where lower(u.email) = normalized_email
  limit 1;

  if invited_user_id is not null and exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = invited_user_id
  ) then
    raise exception 'That user already owns this board.';
  end if;

  if invited_user_id is not null and exists (
    select 1
    from public.board_members pm
    where pm.board_id = target_board_id
      and pm.user_id = invited_user_id
  ) then
    raise exception 'That user is already a collaborator.';
  end if;

  insert into public.board_invites (board_id, email, role, invited_by)
  values (target_board_id, normalized_email, target_role, auth.uid())
  on conflict (board_id, email)
  do update set
    role = excluded.role,
    invited_by = excluded.invited_by,
    accepted_at = null,
    created_at = now();

  return;
end;
$$;

drop function if exists public.accept_pending_board_invites();

drop function if exists public.list_my_pending_board_invites();
create or replace function public.list_my_pending_board_invites()
returns table (
  id uuid,
  board_id uuid,
  board_name text,
  email text,
  role text,
  invited_by uuid,
  inviter_email text,
  created_at timestamptz
)
language sql
security definer
set search_path = public, auth
stable
as $$
  select
    pi.id,
    pi.board_id,
    p.name as board_name,
    pi.email,
    pi.role,
    pi.invited_by,
    u.email::text as inviter_email,
    pi.created_at
  from public.board_invites pi
  join public.boards p on p.id = pi.board_id
  left join auth.users u on u.id = pi.invited_by
  where lower(pi.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and pi.accepted_at is null
  order by pi.created_at desc;
$$;

drop function if exists public.accept_board_invite(uuid);
create or replace function public.accept_board_invite(target_invite_id uuid)
returns table (accepted_board_id uuid)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  invite_record public.board_invites%rowtype;
  current_email text;
begin
  select lower(u.email)
  into current_email
  from auth.users u
  where u.id = auth.uid();

  if auth.uid() is null or current_email is null then
    raise exception 'Sign in before accepting invitations.';
  end if;

  select *
  into invite_record
  from public.board_invites pi
  where pi.id = target_invite_id
    and lower(pi.email) = current_email
    and pi.accepted_at is null;

  if invite_record.id is null then
    raise exception 'Invitation not found.';
  end if;

  insert into public.board_members (board_id, user_id, role)
  values (invite_record.board_id, auth.uid(), invite_record.role)
  on conflict (board_id, user_id)
  do nothing;

  update public.board_invites
  set accepted_at = now()
  where public.board_invites.id = invite_record.id
    and public.board_invites.accepted_at is null;

  return query select invite_record.board_id;
end;
$$;

drop function if exists public.decline_board_invite(uuid);
create or replace function public.decline_board_invite(target_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_email text;
begin
  select lower(u.email)
  into current_email
  from auth.users u
  where u.id = auth.uid();

  if auth.uid() is null or current_email is null then
    raise exception 'Sign in before managing invitations.';
  end if;

  delete from public.board_invites pi
  where pi.id = target_invite_id
    and lower(pi.email) = current_email
    and pi.accepted_at is null;
end;
$$;

create or replace function public.cancel_board_invite(
  target_board_id uuid,
  target_invite_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = auth.uid()
  ) then
    raise exception 'Only the board owner can cancel invitations.';
  end if;

  delete from public.board_invites
  where board_id = target_board_id
    and id = target_invite_id
    and accepted_at is null;
end;
$$;

drop function if exists public.delete_owned_board(uuid);
create or replace function public.delete_owned_board(target_board_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = auth.uid()
  ) then
    raise exception 'Only the board owner can delete this board.';
  end if;

  delete from public.board_activity
  where board_id = target_board_id;

  delete from public.task_comments
  where board_id = target_board_id;

  delete from public.board_messages
  where board_id = target_board_id;

  delete from public.board_invites
  where board_id = target_board_id;

  delete from public.notifications
  where board_id = target_board_id;

  delete from public.board_members
  where board_id = target_board_id;

  delete from public.tasks
  where board_id = target_board_id;

  delete from public.stages
  where board_id = target_board_id;

  delete from public.board_activity
  where board_id = target_board_id;

  delete from public.boards
  where id = target_board_id
    and owner_id = auth.uid();
end;
$$;

create or replace function public.remove_board_member(
  target_board_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = auth.uid()
  ) then
    raise exception 'Only the board owner can remove collaborators.';
  end if;

  if exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = target_user_id
  ) then
    raise exception 'The board owner cannot be removed.';
  end if;

  delete from public.board_members
  where board_id = target_board_id
    and user_id = target_user_id;
end;
$$;

create or replace function public.leave_board(target_board_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in before leaving a board.';
  end if;

  if exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = auth.uid()
  ) then
    raise exception 'The board owner cannot leave their own board.';
  end if;

  delete from public.board_members
  where board_id = target_board_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.update_board_member_role(
  target_board_id uuid,
  target_user_id uuid,
  target_role text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if target_role not in ('editor', 'viewer') then
    raise exception 'Role must be editor or viewer.';
  end if;

  if not exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = auth.uid()
  ) then
    raise exception 'Only the board owner can change collaborator roles.';
  end if;

  if exists (
    select 1
    from public.boards p
    where p.id = target_board_id
      and p.owner_id = target_user_id
  ) then
    raise exception 'The board owner role cannot be changed.';
  end if;

  update public.board_members
  set role = target_role
  where board_id = target_board_id
    and user_id = target_user_id;
end;
$$;

grant execute on function public.list_board_members(uuid) to authenticated;
grant execute on function public.list_board_invites(uuid) to authenticated;
grant execute on function public.invite_board_member_by_email(uuid, text, text) to authenticated;
grant execute on function public.cancel_board_invite(uuid, uuid) to authenticated;
grant execute on function public.delete_owned_board(uuid) to authenticated;
grant execute on function public.remove_board_member(uuid, uuid) to authenticated;
grant execute on function public.leave_board(uuid) to authenticated;
grant execute on function public.update_board_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.list_my_pending_board_invites() to authenticated;
grant execute on function public.accept_board_invite(uuid) to authenticated;
grant execute on function public.decline_board_invite(uuid) to authenticated;
grant execute on function public.login_email_for_username(text) to anon, authenticated;

revoke all on function public.notify_board_members(uuid, uuid, text, uuid, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.notify_board_activity() from public, anon, authenticated;
revoke all on function public.notify_board_message() from public, anon, authenticated;
revoke all on function public.notify_board_invite() from public, anon, authenticated;
revoke all on function public.notify_board_mentions(uuid, uuid, text, uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.notify_board_message_mentions() from public, anon, authenticated;
revoke all on function public.notify_task_comment_mentions() from public, anon, authenticated;

alter table public.user_profiles enable row level security;
alter table public.boards enable row level security;
alter table public.board_members enable row level security;
alter table public.board_invites enable row level security;
alter table public.stages enable row level security;
alter table public.tasks enable row level security;
alter table public.task_comments enable row level security;
alter table public.board_messages enable row level security;
alter table public.board_message_reactions enable row level security;
alter table public.board_activity enable row level security;
alter table public.notifications enable row level security;
alter table public.drive_file_links enable row level security;

drop policy if exists "Task attachments are visible for accessible boards" on storage.objects;
create policy "Task attachments are visible for accessible boards"
  on storage.objects for select
  using (
    bucket_id = 'task-attachments'
    and public.can_access_board((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "Editors can upload task attachments" on storage.objects;
create policy "Editors can upload task attachments"
  on storage.objects for insert
  with check (
    bucket_id = 'task-attachments'
    and public.can_edit_board((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "Editors can update task attachments" on storage.objects;
create policy "Editors can update task attachments"
  on storage.objects for update
  using (
    bucket_id = 'task-attachments'
    and public.can_edit_board((storage.foldername(name))[1]::uuid)
  )
  with check (
    bucket_id = 'task-attachments'
    and public.can_edit_board((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "Editors can delete task attachments" on storage.objects;
create policy "Editors can delete task attachments"
  on storage.objects for delete
  using (
    bucket_id = 'task-attachments'
    and public.can_edit_board((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "Profiles are visible to signed-in users" on public.user_profiles;
create policy "Profiles are visible to signed-in users"
  on public.user_profiles for select
  using (auth.uid() is not null);

drop policy if exists "Users can update their own profile" on public.user_profiles;
create policy "Users can update their own profile"
  on public.user_profiles for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Boards are visible to owners and members" on public.boards;
create policy "Boards are visible to owners and members"
  on public.boards for select
  using (public.can_access_board(id));

drop policy if exists "Users can create owned boards" on public.boards;
create policy "Users can create owned boards"
  on public.boards for insert
  with check (auth.uid() = owner_id);

drop policy if exists "Owners and editors can update boards" on public.boards;
create policy "Owners and editors can update boards"
  on public.boards for update
  using (public.can_edit_board(id))
  with check (public.can_edit_board(id));

drop policy if exists "Owners can delete boards" on public.boards;
create policy "Owners can delete boards"
  on public.boards for delete
  using (auth.uid() = owner_id);

drop policy if exists "Members are visible inside accessible boards" on public.board_members;
create policy "Members are visible inside accessible boards"
  on public.board_members for select
  using (public.can_access_board(board_id) or user_id = auth.uid());

drop policy if exists "Owners can manage members" on public.board_members;
create policy "Owners can manage members"
  on public.board_members for all
  using (
    exists (
      select 1 from public.boards
      where boards.id = board_members.board_id
        and boards.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.boards
      where boards.id = board_members.board_id
        and boards.owner_id = auth.uid()
    )
  );

drop policy if exists "Invitees can accept board membership" on public.board_members;
create policy "Invitees can accept board membership"
  on public.board_members for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.board_invites pi
      where pi.board_id = board_members.board_id
        and lower(pi.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
        and pi.accepted_at is null
        and pi.role = board_members.role
    )
  );

drop policy if exists "Invites are visible inside accessible boards" on public.board_invites;
create policy "Invites are visible inside accessible boards"
  on public.board_invites for select
  using (
    public.can_access_board(board_id)
    or lower(board_invites.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );

drop policy if exists "Owners can manage invites" on public.board_invites;
create policy "Owners can manage invites"
  on public.board_invites for all
  using (
    exists (
      select 1 from public.boards
      where boards.id = board_invites.board_id
        and boards.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.boards
      where boards.id = board_invites.board_id
        and boards.owner_id = auth.uid()
    )
  );

drop policy if exists "Invitees can accept their own invites" on public.board_invites;
create policy "Invitees can accept their own invites"
  on public.board_invites for update
  using (
    lower(board_invites.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and board_invites.accepted_at is null
  )
  with check (
    lower(board_invites.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );

drop policy if exists "Invitees can decline their own invites" on public.board_invites;
create policy "Invitees can decline their own invites"
  on public.board_invites for delete
  using (
    lower(board_invites.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and board_invites.accepted_at is null
  );

drop policy if exists "Stages are visible inside accessible boards" on public.stages;
create policy "Stages are visible inside accessible boards"
  on public.stages for select
  using (public.can_access_board(board_id));

drop policy if exists "Owners and editors can manage stages" on public.stages;
create policy "Owners and editors can manage stages"
  on public.stages for all
  using (public.can_edit_board(board_id))
  with check (public.can_edit_board(board_id));

drop policy if exists "Tasks are visible inside accessible boards" on public.tasks;
create policy "Tasks are visible inside accessible boards"
  on public.tasks for select
  using (public.can_access_board(board_id));

drop policy if exists "Owners and editors can manage tasks" on public.tasks;
create policy "Owners and editors can manage tasks"
  on public.tasks for all
  using (public.can_edit_board(board_id))
  with check (public.can_edit_board(board_id));

drop policy if exists "Comments are visible inside accessible boards" on public.task_comments;
create policy "Comments are visible inside accessible boards"
  on public.task_comments for select
  using (public.can_access_board(board_id));

drop policy if exists "Owners and editors can add comments" on public.task_comments;
create policy "Owners and editors can add comments"
  on public.task_comments for insert
  with check (public.can_edit_board(board_id) and author_id = auth.uid());

drop policy if exists "Comment authors can update comments" on public.task_comments;
create policy "Comment authors can update comments"
  on public.task_comments for update
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

drop policy if exists "Comment authors and owners can delete comments" on public.task_comments;
create policy "Comment authors and owners can delete comments"
  on public.task_comments for delete
  using (
    author_id = auth.uid()
    or exists (
      select 1 from public.boards
      where boards.id = task_comments.board_id
        and boards.owner_id = auth.uid()
    )
  );

drop policy if exists "Messages are visible inside accessible boards" on public.board_messages;
create policy "Messages are visible inside accessible boards"
  on public.board_messages for select
  using (public.can_access_board(board_id));

drop policy if exists "Board collaborators can send messages" on public.board_messages;
create policy "Board collaborators can send messages"
  on public.board_messages for insert
  with check (public.can_access_board(board_id) and author_id = auth.uid());

drop policy if exists "Message authors can update messages" on public.board_messages;
create policy "Message authors can update messages"
  on public.board_messages for update
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

drop policy if exists "Message authors and owners can delete messages" on public.board_messages;
drop policy if exists "Message authors can delete messages" on public.board_messages;
create policy "Message authors can delete messages"
  on public.board_messages for delete
  using (author_id = auth.uid());

drop policy if exists "Message reactions are visible inside accessible boards" on public.board_message_reactions;
create policy "Message reactions are visible inside accessible boards"
  on public.board_message_reactions for select
  using (public.can_access_board(board_id));

drop policy if exists "Board collaborators can add message reactions" on public.board_message_reactions;
create policy "Board collaborators can add message reactions"
  on public.board_message_reactions for insert
  with check (
    public.can_access_board(board_id)
    and user_id = auth.uid()
    and exists (
      select 1 from public.board_messages
      where board_messages.id = board_message_reactions.message_id
        and board_messages.board_id = board_message_reactions.board_id
    )
  );

drop policy if exists "Reaction authors can delete message reactions" on public.board_message_reactions;
create policy "Reaction authors can delete message reactions"
  on public.board_message_reactions for delete
  using (user_id = auth.uid());

drop policy if exists "Activity is visible inside accessible boards" on public.board_activity;
create policy "Activity is visible inside accessible boards"
  on public.board_activity for select
  using (public.can_access_board(board_id));

drop policy if exists "Users can view their own notifications" on public.notifications;
create policy "Users can view their own notifications"
  on public.notifications for select
  using (recipient_id = auth.uid());

drop policy if exists "Users can update their own notifications" on public.notifications;
create policy "Users can update their own notifications"
  on public.notifications for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

drop policy if exists "Drive links are visible inside accessible boards" on public.drive_file_links;
create policy "Drive links are visible inside accessible boards"
  on public.drive_file_links for select
  using (public.can_access_board(board_id));

drop policy if exists "Collaborators can create drive links" on public.drive_file_links;
create policy "Collaborators can create drive links"
  on public.drive_file_links for insert
  with check (
    public.can_access_board(board_id)
    and created_by = auth.uid()
  );

drop policy if exists "Drive link creators and editors can update drive links" on public.drive_file_links;
create policy "Drive link creators and editors can update drive links"
  on public.drive_file_links for update
  using (created_by = auth.uid() or public.can_edit_board(board_id))
  with check (created_by = auth.uid() or public.can_edit_board(board_id));

drop policy if exists "Drive link creators and editors can delete drive links" on public.drive_file_links;
create policy "Drive link creators and editors can delete drive links"
  on public.drive_file_links for delete
  using (created_by = auth.uid() or public.can_edit_board(board_id));
