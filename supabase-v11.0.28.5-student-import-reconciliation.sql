begin;

create table if not exists public.student_import_reconciliation_sessions (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null,
  semester integer not null check (semester in (1,2,3)),
  source_filename text not null,
  existing_total integer not null default 0 check (existing_total >= 0),
  file_total integer not null default 0 check (file_total >= 0),
  missing_count integer not null default 0 check (missing_count >= 0),
  new_count integer not null default 0 check (new_count >= 0),
  room_change_count integer not null default 0 check (room_change_count >= 0),
  imported_rows integer not null default 0 check (imported_rows >= 0),
  inserted_count integer not null default 0 check (inserted_count >= 0),
  updated_count integer not null default 0 check (updated_count >= 0),
  status text not null default 'prepared' check (status in ('prepared','pending_review','reviewed','failed')),
  import_error text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz
);

create index if not exists student_import_reconciliation_sessions_period_idx
  on public.student_import_reconciliation_sessions(academic_year,semester,created_at desc);

create table if not exists public.student_import_reconciliation_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.student_import_reconciliation_sessions(id) on delete cascade,
  issue_type text not null check (issue_type in ('missing_from_file','new_to_term','room_change')),
  student_id uuid references public.students(id) on delete set null,
  enrollment_id uuid references public.student_enrollments(id) on delete set null,
  student_code text,
  student_name text not null,
  from_class_label text,
  to_class_label text,
  resolution_code text check (
    resolution_code is null or resolution_code in (
      'keep_active','transferred_out','not_continuing','withdrawn','over_criteria',
      'graduated','deceased','invalid_record','other'
    )
  ),
  resolution_note text,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_by_name text,
  resolved_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists student_import_reconciliation_items_session_idx
  on public.student_import_reconciliation_items(session_id,issue_type,created_at);
create index if not exists student_import_reconciliation_items_student_idx
  on public.student_import_reconciliation_items(student_id,created_at desc);

alter table public.student_import_reconciliation_sessions enable row level security;
alter table public.student_import_reconciliation_items enable row level security;

drop policy if exists student_import_reconciliation_sessions_select on public.student_import_reconciliation_sessions;
create policy student_import_reconciliation_sessions_select
on public.student_import_reconciliation_sessions for select
to authenticated
using ((select private.can_manage_student_master()));

drop policy if exists student_import_reconciliation_items_select on public.student_import_reconciliation_items;
create policy student_import_reconciliation_items_select
on public.student_import_reconciliation_items for select
to authenticated
using ((select private.can_manage_student_master()));

revoke all on public.student_import_reconciliation_sessions from anon, public;
revoke all on public.student_import_reconciliation_items from anon, public;
grant select on public.student_import_reconciliation_sessions to authenticated;
grant select on public.student_import_reconciliation_items to authenticated;

create or replace function public.create_student_import_reconciliation(
  p_academic_year text,
  p_semester integer,
  p_source_filename text,
  p_file_total integer,
  p_missing jsonb,
  p_new jsonb,
  p_room_changes jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_session_id uuid;
  v_existing_total integer;
  v_item jsonb;
begin
  if auth.uid() is null or not private.can_manage_student_master() then
    raise exception 'ไม่มีสิทธิ์สร้างรายการตรวจสอบการนำเข้านักเรียน';
  end if;
  if p_semester not in (1,2,3) then raise exception 'ภาคเรียนไม่ถูกต้อง'; end if;
  if jsonb_typeof(coalesce(p_missing,'[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_new,'[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_room_changes,'[]'::jsonb)) <> 'array' then
    raise exception 'ข้อมูลเปรียบเทียบไม่ถูกต้อง';
  end if;

  select count(*) into v_existing_total
  from public.student_enrollments e
  where e.academic_year=btrim(p_academic_year)
    and e.semester=p_semester
    and e.enrollment_status='active';

  insert into public.student_import_reconciliation_sessions(
    academic_year,semester,source_filename,existing_total,file_total,
    missing_count,new_count,room_change_count,status,created_by
  ) values (
    btrim(p_academic_year),p_semester,
    coalesce(nullif(btrim(p_source_filename),''),'student_import.xlsx'),
    v_existing_total,greatest(coalesce(p_file_total,0),0),
    jsonb_array_length(coalesce(p_missing,'[]'::jsonb)),
    jsonb_array_length(coalesce(p_new,'[]'::jsonb)),
    jsonb_array_length(coalesce(p_room_changes,'[]'::jsonb)),
    'prepared',auth.uid()
  ) returning id into v_session_id;

  for v_item in select value from jsonb_array_elements(coalesce(p_missing,'[]'::jsonb))
  loop
    insert into public.student_import_reconciliation_items(
      session_id,issue_type,student_id,enrollment_id,student_code,student_name,from_class_label
    ) values (
      v_session_id,'missing_from_file',
      nullif(v_item->>'student_id','')::uuid,
      nullif(v_item->>'enrollment_id','')::uuid,
      nullif(btrim(coalesce(v_item->>'student_code','')),''),
      coalesce(nullif(btrim(coalesce(v_item->>'student_name','')),''),'ไม่ทราบชื่อ'),
      nullif(btrim(coalesce(v_item->>'class_label','')),'')
    );
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(p_new,'[]'::jsonb))
  loop
    insert into public.student_import_reconciliation_items(
      session_id,issue_type,student_code,student_name,to_class_label
    ) values (
      v_session_id,'new_to_term',
      nullif(btrim(coalesce(v_item->>'student_code','')),''),
      coalesce(nullif(btrim(coalesce(v_item->>'student_name','')),''),'ไม่ทราบชื่อ'),
      nullif(btrim(coalesce(v_item->>'class_label','')),'')
    );
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(p_room_changes,'[]'::jsonb))
  loop
    insert into public.student_import_reconciliation_items(
      session_id,issue_type,student_id,enrollment_id,student_code,student_name,from_class_label,to_class_label
    ) values (
      v_session_id,'room_change',
      nullif(v_item->>'student_id','')::uuid,
      nullif(v_item->>'enrollment_id','')::uuid,
      nullif(btrim(coalesce(v_item->>'student_code','')),''),
      coalesce(nullif(btrim(coalesce(v_item->>'student_name','')),''),'ไม่ทราบชื่อ'),
      nullif(btrim(coalesce(v_item->>'from','')),''),
      nullif(btrim(coalesce(v_item->>'to','')),'')
    );
  end loop;

  return v_session_id;
end;
$$;

revoke all on function public.create_student_import_reconciliation(text,integer,text,integer,jsonb,jsonb,jsonb) from public, anon;
grant execute on function public.create_student_import_reconciliation(text,integer,text,integer,jsonb,jsonb,jsonb) to authenticated;

create or replace function public.finalize_student_import_reconciliation(
  p_session_id uuid,
  p_imported_rows integer,
  p_inserted_count integer,
  p_updated_count integer
)
returns public.student_import_reconciliation_sessions
language plpgsql
security definer
set search_path=''
as $$
declare v_row public.student_import_reconciliation_sessions%rowtype;
begin
  if auth.uid() is null or not private.can_manage_student_master() then
    raise exception 'ไม่มีสิทธิ์บันทึกผลการนำเข้านักเรียน';
  end if;
  update public.student_import_reconciliation_sessions s
     set imported_rows=greatest(coalesce(p_imported_rows,0),0),
         inserted_count=greatest(coalesce(p_inserted_count,0),0),
         updated_count=greatest(coalesce(p_updated_count,0),0),
         status=case when s.missing_count>0 then 'pending_review' else 'reviewed' end,
         import_error=null,
         completed_at=case when s.missing_count=0 then clock_timestamp() else null end,
         updated_at=clock_timestamp()
   where s.id=p_session_id
   returning * into v_row;
  if not found then raise exception 'ไม่พบรายการตรวจสอบการนำเข้า'; end if;
  return v_row;
end;
$$;

revoke all on function public.finalize_student_import_reconciliation(uuid,integer,integer,integer) from public, anon;
grant execute on function public.finalize_student_import_reconciliation(uuid,integer,integer,integer) to authenticated;

create or replace function public.fail_student_import_reconciliation(
  p_session_id uuid,
  p_error text
)
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not private.can_manage_student_master() then
    raise exception 'ไม่มีสิทธิ์บันทึกผลการนำเข้านักเรียน';
  end if;
  update public.student_import_reconciliation_sessions
     set status='failed',import_error=nullif(btrim(coalesce(p_error,'')),''),updated_at=clock_timestamp()
   where id=p_session_id;
end;
$$;

revoke all on function public.fail_student_import_reconciliation(uuid,text) from public, anon;
grant execute on function public.fail_student_import_reconciliation(uuid,text) to authenticated;

create or replace function public.resolve_student_import_reconciliation(
  p_session_id uuid,
  p_resolutions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_item jsonb;
  v_id uuid;
  v_code text;
  v_note text;
  v_rec public.student_import_reconciliation_items%rowtype;
  v_actor text;
  v_status text;
  v_exit_reason text;
  v_default_note text;
  v_resolved integer:=0;
  v_pending integer:=0;
begin
  if auth.uid() is null or not private.can_manage_student_master() then
    raise exception 'ไม่มีสิทธิ์ยืนยันสถานะนักเรียนจากการนำเข้า';
  end if;
  if jsonb_typeof(coalesce(p_resolutions,'[]'::jsonb)) <> 'array' then
    raise exception 'ข้อมูลการยืนยันสถานะไม่ถูกต้อง';
  end if;

  if not exists(select 1 from public.student_import_reconciliation_sessions where id=p_session_id) then
    raise exception 'ไม่พบรายการตรวจสอบการนำเข้า';
  end if;

  select coalesce(nullif(btrim(p.full_name),''),p.email,'ผู้ใช้งาน')
    into v_actor
  from public.profiles p where p.id=auth.uid();

  for v_item in select value from jsonb_array_elements(coalesce(p_resolutions,'[]'::jsonb))
  loop
    v_id:=nullif(v_item->>'item_id','')::uuid;
    v_code:=nullif(btrim(coalesce(v_item->>'resolution_code','')),'');
    v_note:=nullif(btrim(coalesce(v_item->>'resolution_note','')),'');
    if v_code is null then continue; end if;
    if v_code not in ('keep_active','transferred_out','not_continuing','withdrawn','over_criteria','graduated','deceased','invalid_record','other') then
      raise exception 'สถานะการตรวจสอบไม่ถูกต้อง';
    end if;
    if v_code in ('over_criteria','invalid_record','other') and v_note is null then
      raise exception 'กรุณาระบุรายละเอียดสำหรับรายการที่เลือกเหตุผลเพิ่มเติม';
    end if;

    select * into v_rec
    from public.student_import_reconciliation_items i
    where i.id=v_id and i.session_id=p_session_id and i.issue_type='missing_from_file'
    for update;
    if not found then raise exception 'ไม่พบรายชื่อนักเรียนที่ต้องตรวจสอบ'; end if;

    if v_code='keep_active' then
      v_status:=null; v_exit_reason:=null; v_default_note:='คงสภาพนักเรียนไว้';
    elsif v_code='transferred_out' then
      v_status:='transferred_out'; v_exit_reason:='transferred_out'; v_default_note:='ย้ายสถานศึกษา / ย้ายออก';
    elsif v_code='not_continuing' then
      v_status:='inactive'; v_exit_reason:='not_continuing'; v_default_note:='ไม่เรียนต่อ';
    elsif v_code='withdrawn' then
      v_status:='inactive'; v_exit_reason:='withdrawn'; v_default_note:='ลาออก / พ้นสภาพ';
    elsif v_code='over_criteria' then
      v_status:='inactive'; v_exit_reason:='other'; v_default_note:='เกินเกณฑ์';
    elsif v_code='graduated' then
      v_status:='graduated'; v_exit_reason:='other'; v_default_note:='จบการศึกษา';
    elsif v_code='deceased' then
      v_status:='inactive'; v_exit_reason:='deceased'; v_default_note:='เสียชีวิต';
    elsif v_code='invalid_record' then
      v_status:='inactive'; v_exit_reason:='other'; v_default_note:='ข้อมูลซ้ำ / ไม่มีตัวตนในทะเบียนจริง';
    else
      v_status:='inactive'; v_exit_reason:='other'; v_default_note:='อื่น ๆ';
    end if;

    if v_status is not null and v_rec.enrollment_id is not null then
      update public.student_enrollments e
         set enrollment_status=v_status,
             exit_reason=v_exit_reason,
             exit_note=case when v_note is null then v_default_note else v_default_note||' · '||v_note end,
             ended_at=clock_timestamp(),
             ended_by=auth.uid(),
             updated_at=clock_timestamp()
       where e.id=v_rec.enrollment_id;
    end if;

    update public.student_import_reconciliation_items
       set resolution_code=v_code,
           resolution_note=v_note,
           resolved_by=auth.uid(),
           resolved_by_name=coalesce(v_actor,'ผู้ใช้งาน'),
           resolved_at=clock_timestamp()
     where id=v_id;
    v_resolved:=v_resolved+1;
  end loop;

  select count(*) into v_pending
  from public.student_import_reconciliation_items
  where session_id=p_session_id
    and issue_type='missing_from_file'
    and resolution_code is null;

  update public.student_import_reconciliation_sessions
     set status=case when v_pending=0 then 'reviewed' else 'pending_review' end,
         completed_at=case when v_pending=0 then clock_timestamp() else null end,
         updated_at=clock_timestamp()
   where id=p_session_id;

  return jsonb_build_object('resolved',v_resolved,'pending',v_pending);
end;
$$;

revoke all on function public.resolve_student_import_reconciliation(uuid,jsonb) from public, anon;
grant execute on function public.resolve_student_import_reconciliation(uuid,jsonb) to authenticated;

commit;
