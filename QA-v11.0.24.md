# QA v11.0.24

## Frontend

- [x] `node --check app.js` ผ่าน
- [x] `APP_BUILD = 11.0.24`
- [x] `index.html` ใช้ `styles.css?v=11.0.24` และ `app.js?v=11.0.24`
- [x] `config.js` import cache เป็น `11.0.24`
- [x] มีหน้า “ลายเซ็นของฉัน”
- [x] มี Paper / Draw / Upload UI
- [x] แสดงคำแนะนำ PNG/WebP พื้นหลังโปร่งใส
- [x] ระบบ 5/6 มี Dynamic Shared Signature Grid

## Database / Security

- [x] `user_signature_preferences` เปิด RLS
- [x] `academic_shared_team_signatures` เปิด RLS
- [x] authenticated ไม่มี direct INSERT/UPDATE/DELETE ทั้งสองตาราง
- [x] RPC ใหม่ `anon_execute=false`
- [x] RPC ใหม่ `authenticated_execute=true`
- [x] Reminder backfill สำเร็จ
- [x] Paper mode ปิด reminder และไม่เรียก automation
- [x] เปิด Auto Sign โดยไม่มี recent password ถูกบล็อก
- [x] Auto runner เมื่อ preference ปิด คืน `{signed:0, approved:0}`
- [x] Shared snapshot แบบ 3 คนได้ 3 แถว ลำดับ 1/2/3
- [x] Backfill รายงานชุมนุมปัจจุบันเก็บลายเซ็นเดิมเป็น snapshot ได้
- [x] Master signature ที่ถูก snapshot ถูกนับเป็น in-use และลบไม่ได้ตามปกติ

## Production migrations

- [x] `20260921032446 bnk_v11_0_24_user_signature_profile`
- [x] `20260921032536 bnk_v11_0_24_shared_signature_snapshots`
- [x] `20260921032625 bnk_v11_0_24_personal_auto_actions`
- [x] `20260921032802 bnk_v11_0_24_signature_consistency_backfill`

## Advisor

Security Advisor ยังมี warning ประเภท authenticated SECURITY DEFINER สำหรับ RPC ใหม่ ซึ่งเป็น endpoint ที่ตั้งใจให้ authenticated เรียกและมีการตรวจสิทธิ์ภายใน RPC พร้อม revoke anon/PUBLIC แล้ว รวมถึง warning เดิมของโครงการ จึงไม่ระบุว่า Advisor clean 100%
- [x] เมื่อจำลอง AMR password ล่าสุด ผู้บริหารสามารถเปิด Auto Sign + Auto Approve ได้สำเร็จใน transaction test
- [x] Academic Submission Workspace เรียก personal auto-action runner เมื่อเปิด/รีเฟรช workspace เพื่อประมวลผลคิวที่ถึงสิทธิ์ผู้ใช้
