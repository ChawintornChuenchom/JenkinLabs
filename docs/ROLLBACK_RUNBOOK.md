# Rollback Runbook — taskflow-api / taskflow-mobile

คำสั่งทั้งหมดในเอกสารนี้รันได้จริงกับ lab environment นี้ (kind cluster `taskflow-control-plane`,
Jenkins `jenkins-lab01` พอร์ต 8081) — ทดสอบ syntax ทุกคำสั่งแล้ว

## 1. Blue/Green Deploy — production (`taskflow-api`, branch `main`)

### 1.1 กรณีรู้ตัวทันที (pipeline ยังรันอยู่หรือเพิ่งจบ)

Blue/Green Deploy stage มี rollback อัตโนมัติอยู่แล้วใน `post { failure { ... } }` — ถ้า smoke
test หลัง deploy สีใหม่ fail ระบบจะ patch Service กลับไปสีเดิมให้เองโดยไม่ต้องทำอะไร
ตรวจสอบผลจาก Jenkins console log ของ stage "Blue/Green Deploy" ว่ามีบรรทัด
`Automatic rollback: Service selector restored to <color>` หรือไม่

### 1.2 กรณี deploy "สำเร็จ" แต่พบปัญหาทีหลัง (ต้อง rollback ด้วยมือ)

```bash
# ใช้ kubeconfig เดียวกับที่เก็บใน Jenkins credential k8s-credentials
export KUBECONFIG=/path/to/k3d-taskflow.kubeconfig

# 1. เช็คว่าตอนนี้ Service ชี้ไปสีไหน
kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'; echo

# 2. สลับกลับไปสีตรงข้าม (สมมติตอนนี้เป็น "green" ต้องการกลับไป "blue")
kubectl patch svc taskflow -p '{"spec":{"selector":{"color":"blue"}}}'

# 3. ยืนยันว่า traffic ไปสีที่ต้องการแล้วจริง
kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'; echo
curl -s http://taskflow.localhost/health   # หรือ port-forward ถ้าไม่มี ingress host ตั้งไว้

# 4. (ถ้าจำเป็น) scale down deployment สีที่มีปัญหาไม่ให้รับ traffic โดยไม่ตั้งใจ
kubectl scale deployment/taskflow-green --replicas=0
```

**หมายเหตุ:** deployment สีเก่า (สีที่เพิ่งถูกแทนที่) ยังรันค้างอยู่เสมอหลัง deploy ปกติ (ไม่ได้ลบ
ทิ้ง) เพื่อให้ rollback ทำได้ทันทีแบบไม่ต้อง rebuild image ใหม่

### 1.3 กรณี image tag ที่ deploy ไปมีบั๊กร้ายแรง (ต้อง rollback ไป image เก่าจริงๆ ไม่ใช่แค่สลับสี)

```bash
# หา image tag ของ build ก่อนหน้าที่ยังดีอยู่ จาก Jenkins build history (env.IMAGE_TAG = GIT_COMMIT[0..6])
kubectl set image deployment/taskflow-blue taskflow-api=localhost:5001/taskflow-api:<previous-good-tag>
kubectl rollout status deployment/taskflow-blue --timeout=60s
kubectl patch svc taskflow -p '{"spec":{"selector":{"color":"blue"}}}'
```

## 2. Pipeline Health Gate ปฏิเสธ deploy (branch `main`)

ถ้า stage "Pipeline Health Gate" fail (`success rate ... below the 90% threshold`) แปลว่า build
ล่าสุดใน 1 ชั่วโมงที่ผ่านมามีอัตราสำเร็จต่ำเกินไป — **ห้าม bypass ด้วยการรันซ้ำเฉยๆ**
ให้ทำตามนี้ก่อน:

1. เปิด Grafana dashboard "Jenkins Pipeline Health" (`http://localhost:3000`) ดู panel build
   success rate ว่า build ที่ fail ก่อนหน้าเกิดจากอะไร (flaky test? infra ปัญหาจริง?)
2. ถ้าเป็น flaky/สภาพแวดล้อมชั่วคราว (เช่น port ชนจากการรันซ้อน) — แก้ต้นเหตุแล้วค่อยรันใหม่
3. ถ้าเป็นบั๊กจริงในโค้ด — แก้โค้ดก่อน ไม่ใช่ข้าม gate
4. Query Prometheus โดยตรงเพื่อดูตัวเลขสดก่อนตัดสินใจ:
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=increase(default_jenkins_builds_success_build_count_total%7Bjenkins_job%3D%22taskflow-multibranch%2Fmain%22%7D%5B1h%5D)/increase(default_jenkins_builds_total_build_count_total%7Bjenkins_job%3D%22taskflow-multibranch%2Fmain%22%7D%5B1h%5D)'
   ```

## 3. taskflow-mobile — signed release ผิดพลาด

ไม่มี auto-deploy ฝั่ง mobile (Distribute stage ปิดไว้เป็นค่าเริ่มต้นเสมอ) risk จึงต่ำกว่าฝั่ง api
มาก — "rollback" ที่แท้จริงคือ **อย่าเผยแพร่ AAB ตัวที่มีปัญหา**:

1. เช็ค build history ของ `taskflow-mobile/main` ใน Jenkins หา build ล่าสุดที่ "Build Release AAB
   (signed)" เป็นสีเขียว
2. ดาวน์โหลด `app-release.aab` จาก artifacts ของ build นั้น (ไม่ใช่ build ล่าสุดที่พัง)
3. ถ้า AAB ตัวที่มีปัญหาหลุดไปถึงผู้ทดสอบแล้ว (manual distribute) ให้แจ้งถอนตัวนั้นและแจกตัวจาก
   build ที่ดีแทน — ไม่มีกลไก auto-rollback ฝั่งนี้เพราะไม่มี auto-deploy ตั้งแต่แรก

## 4. ตรวจสถานะโดยรวมเร็วๆ (health check ก่อน/หลัง rollback ใดๆ)

```bash
kubectl get pods -n default          # pod ทุกตัวต้อง Running/Ready
kubectl get svc taskflow -o wide     # เช็ค selector color ปัจจุบัน
curl -s http://localhost:8081/api/json?tree=jobs[name,color]   # สถานะล่าสุดของทุก job ใน Jenkins
```
