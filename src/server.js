const { createApp } = require('./app');

// ใช้จำลอง deploy พัง สำหรับสาธิต automatic rollback ของ Blue/Green Deploy stage (Lab 07 task 6)
// เปิดผ่าน env var นี้เท่านั้น ค่า default (ไม่ตั้ง) ไม่กระทบการทำงานปกติเลย
if (process.env.CRASH_ON_START === 'true') {
  console.error('Simulated startup crash (CRASH_ON_START=true) for Lab 07 rollback demo');
  process.exit(1);
}

const PORT = process.env.PORT || 8080;
createApp().listen(PORT, () => {
  console.log(`taskflow-lab API listening on port ${PORT}`);
});
