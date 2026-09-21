begin;

grant execute on function private.can_cancel_official_attendance() to authenticated;

commit;
