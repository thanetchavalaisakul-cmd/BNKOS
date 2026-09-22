begin;

alter table public.academic_transfer_requests
  add column if not exists official_document_number text,
  add column if not exists official_document_number_updated_by uuid references auth.users(id) on delete set null,
  add column if not exists official_document_number_updated_by_name text,
  add column if not exists official_document_number_updated_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='academic_transfer_official_document_number_length'
      and conrelid='public.academic_transfer_requests'::regclass
  ) then
    alter table public.academic_transfer_requests
      add constraint academic_transfer_official_document_number_length
      check (official_document_number is null or char_length(official_document_number) <= 80);
  end if;
end $$;

create table if not exists private.academic_transfer_official_number_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.academic_transfer_requests(id) on delete cascade,
  previous_number text,
  new_number text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_by_name text not null,
  changed_at timestamptz not null default clock_timestamp()
);

revoke all on table private.academic_transfer_official_number_history from public, anon, authenticated;

create index if not exists academic_transfer_official_number_history_request_idx
  on private.academic_transfer_official_number_history(request_id, changed_at desc);

create or replace function private.can_manage_academic_transfer_official_number()
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select private.is_active_user()
    and (
      private.can_manage_academic_registration()
      or private.is_department_head_of('academic')
    );
$$;

revoke all on function private.can_manage_academic_transfer_official_number() from public, anon, authenticated;

create or replace function public.set_academic_transfer_official_number(
  p_request_id uuid,
  p_document_number text
)
returns public.academic_transfer_requests
language plpgsql
security definer
set search_path=''
as $$
declare
  v_row public.academic_transfer_requests%rowtype;
  v_old text;
  v_new text;
  v_actor_name text;
begin
  if not private.can_manage_academic_transfer_official_number() then
    raise exception 'ไม่มีสิทธิ์กำหนดเลขที่ ศธ. ของหนังสือย้ายนักเรียน';
  end if;

  select * into v_row
  from public.academic_transfer_requests r
  where r.id=p_request_id
  for update;

  if not found then raise exception 'ไม่พบคำร้องใบย้ายนักเรียน'; end if;

  v_old := nullif(btrim(v_row.official_document_number), '');
  v_new := nullif(btrim(coalesce(p_document_number,'')), '');

  if v_new is not null then
    v_new := regexp_replace(v_new, '^ศธ[.]?[[:space:]]*', '', 'i');
    v_new := nullif(btrim(v_new), '');
  end if;

  if v_new is not null and char_length(v_new) > 80 then
    raise exception 'เลขที่ ศธ. ยาวเกินไป (ไม่เกิน 80 ตัวอักษร)';
  end if;

  if v_new is not distinct from v_old then return v_row; end if;

  select coalesce(nullif(btrim(p.full_name),''), p.email, 'ผู้ใช้งาน')
  into v_actor_name
  from public.profiles p
  where p.id=auth.uid();

  update public.academic_transfer_requests r
  set official_document_number=v_new,
      official_document_number_updated_by=auth.uid(),
      official_document_number_updated_by_name=coalesce(v_actor_name,'ผู้ใช้งาน'),
      official_document_number_updated_at=clock_timestamp(),
      updated_by=auth.uid(),
      updated_at=clock_timestamp()
  where r.id=p_request_id
  returning * into v_row;

  insert into private.academic_transfer_official_number_history(
    request_id, previous_number, new_number, changed_by, changed_by_name
  ) values (
    p_request_id, v_old, v_new, auth.uid(), coalesce(v_actor_name,'ผู้ใช้งาน')
  );

  return v_row;
end;
$$;

revoke all on function public.set_academic_transfer_official_number(uuid,text) from public, anon;
grant execute on function public.set_academic_transfer_official_number(uuid,text) to authenticated;

create or replace function public.get_academic_transfer_official_number_history(
  p_request_id uuid
)
returns table(
  id uuid,
  previous_number text,
  new_number text,
  changed_by_name text,
  changed_at timestamptz
)
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if not private.can_manage_academic_transfer_official_number() then
    raise exception 'ไม่มีสิทธิ์ดูประวัติเลขที่ ศธ.';
  end if;

  return query
  select h.id,h.previous_number,h.new_number,h.changed_by_name,h.changed_at
  from private.academic_transfer_official_number_history h
  where h.request_id=p_request_id
  order by h.changed_at desc;
end;
$$;

revoke all on function public.get_academic_transfer_official_number_history(uuid) from public, anon;
grant execute on function public.get_academic_transfer_official_number_history(uuid) to authenticated;

commit;
