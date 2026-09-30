# Jenkins Pipeline SLO (Lab 09 task 6)

**SLO:** 95% ของ build ต้อง complete ภายใน 6 นาที (360 วินาที) วัดแบบ rolling 7 วัน

- วัดผ่าน panel "p95 Build Duration" ใน Grafana dashboard `Jenkins Pipeline Health`
  (query: `jenkins_job_total_duration{quantile="0.95"}`) — threshold สีแดงตั้งไว้ที่ 360s
- error budget: 5% ของ build ในรอบ 7 วัน ที่อนุญาตให้เกิน 6 นาทีได้

**Alert (symptom-based, ไม่ใช่ raw resource cause):** `JenkinsQueueBacklog`
(`observability/prometheus/alerts.yml`) ยิงเมื่อ queue มี build ค้างต่อเนื่องเกิน 5 นาที
— เป็นอาการ (symptom) ของ "agent capacity ไม่พอสำหรับ demand ปัจจุบัน" ไม่ใช่สาเหตุดิบๆ เช่น
CPU/memory สูง ตรงตามที่โจทย์ต้องการ

## สาธิต saturation + recovery (task 7)

1. ตั้ง Kubernetes cloud `kind-taskflow` ให้ `containerCap=2` (จำกัด pod พร้อมกันสูงสุด 2 ตัว)
2. ยิง build พร้อมกัน 25 ครั้งของ job ที่ใช้ label `k8s-node` (`sleep 90` ต่อ build จำลองงานจริง)
3. ยืนยันด้วย `kubectl get pods` ว่ามี pod รันพร้อมกันไม่เกิน 2 ตัวเสมอ ส่วนที่เหลือ "Waiting for
   next available executor" ใน Jenkins queue
4. `jenkins_queue_size_value` ใน Prometheus ค้างเป็นเลขบวกต่อเนื่องเกิน 5 นาที → alert
   `JenkinsQueueBacklog` เปลี่ยนสถานะ pending → firing
5. เพิ่ม `containerCap` เป็นค่าที่สูงขึ้น → คิวระบายเร็วขึ้น → `jenkins_queue_size_value` กลับสู่ 0
   → alert resolved
