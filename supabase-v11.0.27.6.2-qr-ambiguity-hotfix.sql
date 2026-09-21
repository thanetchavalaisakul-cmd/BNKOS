-- BNK School OS v11.0.27.6.2
-- Fix ambiguous attendance_date in QR rotation/ensure functions.

begin;

create or replace function private.ensure_today_official_attendance_qr()
returns private.official_attendance_qr_tokens
language plpgsql
security definer
set search_path=''
as $$
declare
  v_date date := (clock_timestamp() at time zone 'Asia/Bangkok')::date;
  v_row private.official_attendance_qr_tokens%rowtype;
begin
  select q.*
    into v_row
    from private.official_attendance_qr_tokens q
   where q.attendance_date = v_date;

  if not found then
    insert into private.official_attendance_qr_tokens(attendance_date,created_by)
    values(v_date,auth.uid())
    returning * into v_row;
  elsif not v_row.is_active then
    update private.official_attendance_qr_tokens q
       set token=gen_random_uuid(),
           generation=q.generation+1,
           is_active=true,
           rotated_by=auth.uid(),
           rotated_at=clock_timestamp()
     where q.attendance_date=v_date
     returning * into v_row;
  end if;

  return v_row;
end;
$$;

create or replace function public.rotate_official_attendance_today_qr()
returns table(
  attendance_date date,
  token text,
  generation integer,
  is_active boolean,
  created_at timestamptz,
  rotated_at timestamptz
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_date date := (clock_timestamp() at time zone 'Asia/Bangkok')::date;
  v_row private.official_attendance_qr_tokens%rowtype;
begin
  if not private.can_manage_official_attendance() then
    raise exception 'ไม่มีสิทธิ์สร้าง QR ลงเวลาใหม่';
  end if;

  if private.official_attendance_effective_mode(v_date) <> 'qr' then
    raise exception 'วันนี้ไม่ได้ใช้โหมด QR Code + GPS';
  end if;

  insert into private.official_attendance_qr_tokens(
    attendance_date,token,generation,is_active,created_by,created_at,rotated_by,rotated_at
  )
  values(
    v_date,gen_random_uuid(),1,true,auth.uid(),clock_timestamp(),auth.uid(),clock_timestamp()
  )
  on conflict on constraint official_attendance_qr_tokens_pkey
  do update set
    token=gen_random_uuid(),
    generation=private.official_attendance_qr_tokens.generation+1,
    is_active=true,
    rotated_by=auth.uid(),
    rotated_at=clock_timestamp()
  returning * into v_row;

  return query
  select
    v_row.attendance_date,
    v_row.token::text,
    v_row.generation,
    v_row.is_active,
    v_row.created_at,
    v_row.rotated_at;
end;
$$;

revoke all on function public.rotate_official_attendance_today_qr() from public,anon;
grant execute on function public.rotate_official_attendance_today_qr() to authenticated;

commit;
