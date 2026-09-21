# Changelog v11.0.24

- เพิ่มหน้า **ลายเซ็นของฉัน** สำหรับครู หัวหน้าฝ่าย และผู้บริหาร
- รองรับเซ็นบนกระดาษ, เซ็นสดในระบบ และอัปโหลดภาพลายเซ็น
- เพิ่มคำแนะนำภาพลายเซ็น PNG/WebP พื้นหลังโปร่งใส
- เพิ่มลายเซ็นหลักต่อผู้ใช้และการ sync ค่า default
- เพิ่ม Reminder ตั้งค่าลายเซ็นสำหรับบัญชีใหม่และบัญชีเดิมที่ยังไม่ตั้งค่า
- เพิ่ม Global Auto Sign และ Auto Approve + Sign โดยต้องยืนยันรหัสผ่านเมื่อเปิดครั้งแรก
- Auto Sign ไม่ส่งงานอัตโนมัติและไม่เขียนทับ Manual Signature
- Auto Approve จำกัดตาม Assignment/Reviewer Role และ registry capability
- เพิ่ม `academic_shared_team_signatures` สำหรับ snapshot ทีมต่อ document version
- ระบบที่ 5 ใช้ Dynamic Signature Layout ตามทีมครูประจำชั้นร่วม
- ระบบที่ 6 ใช้ Dynamic Signature Layout ตามทีมครูที่ปรึกษาชุมนุม
- 1 คนกึ่งกลาง / 2 คนซ้ายขวา / 3 คนซ้ายกลางขวา / 4+ ขึ้นแถวใหม่
- เพิ่ม `club_activity` ให้ Central Signature Visibility รู้จักโดยตรง
- ปรับการลบลายเซ็นให้ตรวจ dependency ก่อนลบ Storage เพื่อไม่ทำลาย asset ที่ถูก snapshot ใช้งานแล้ว
- Backfill snapshot ให้ shared submission ที่ส่งก่อน v11.0.24
- Build/cache version เป็น `11.0.24`
