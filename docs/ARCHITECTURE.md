# Taskflow CI/CD Architecture (Lab 10 Capstone)

สองพาย์ไลน์แยกอิสระจากกัน แชร์ repo เดียวกัน (`JenkinLabs`, multibranch job คนละตัว คนละ
`scriptPath`) — `taskflow-multibranch` (`Jenkinsfile` ที่ repo root, สำหรับ taskflow-api)
และ `taskflow-mobile` (`mobile/Jenkinsfile.mobile`, สำหรับ taskflow-mobile Flutter app)

## taskflow-api — `Jenkinsfile`

```mermaid
flowchart TD
    A[Secrets Detection<br/>gitleaks] --> B{{Verify — parallel}}
    B --> B1[Lint]
    B --> B2[Unit Test]
    B --> B3[SAST — ESLint]
    B --> B4[SAST — Semgrep]
    B --> B5[SCA — npm audit]
    B1 & B2 & B3 & B4 & B5 --> C[Generate SBOM<br/>syft + cosign sign]
    C --> D[Policy Gate<br/>OPA: opa eval security.rego]
    D --> E[SonarQube Analysis]
    E --> F{Quality Gate<br/>waitForQualityGate}
    F --> G[E2E<br/>Playwright, static agent]
    G --> H{develop/main?}
    H -->|no| Z1[stop — feature/hotfix branches end here]
    H -->|yes| I[Build Image<br/>docker build + push]
    I --> J[Container Scan<br/>Trivy HIGH/CRITICAL]
    J --> K{branch == main?}
    K -->|no develop| N[Blue/Green Deploy]
    K -->|yes| L[[Approval — manual input]]
    L --> M{Pipeline Health Gate<br/>Prometheus success-rate ≥ 90%}
    M -->|blocked| Z2[abort — no deploy]
    M -->|passed| N
    N --> O[Email Notification<br/>success/failure + branch + build URL]
```

**Gate ทั้งหมดเรียงตามลำดับจริง:**
1. Secrets Detection (gitleaks) — บล็อกทันทีถ้าเจอ secret หลุดใน commit
2. Verify (parallel) — Lint / Unit Test / SAST ×2 / SCA ต้องผ่านทุกตัว
3. Generate SBOM + เซ็นด้วย cosign (ไม่ block แต่เป็น supply-chain evidence)
4. Policy Gate — OPA deny ถ้ามี CVE critical จาก SCA
5. SonarQube Analysis → Quality Gate — code quality/coverage threshold
6. E2E (Playwright) — เฉพาะหลังผ่าน Quality Gate
7. Build Image + Container Scan (Trivy) — เฉพาะ `develop`/`main`
8. Approval (manual, เฉพาะ `main`) — ต้องมีคนกด approve ก่อน production
9. Pipeline Health Gate (เฉพาะ `main`) — เช็ค build success rate จาก Prometheus ก่อนปล่อย
10. Blue/Green Deploy — สลับ traffic, rollback อัตโนมัติถ้า smoke test fail
11. Email Notification — ทุกผลลัพธ์ (success/failure)

## taskflow-mobile — `mobile/Jenkinsfile.mobile`

```mermaid
flowchart TD
    A[Checkout] --> B[Dependencies<br/>flutter pub get]
    B --> C{{Quality — parallel}}
    C --> C1[Analyze<br/>--fatal-infos --fatal-warnings]
    C --> C2[Format Check<br/>dart format]
    C1 & C2 --> D[Test & Coverage<br/>flutter test + lcov→cobertura]
    D --> E[Security — SCA<br/>osv-scanner + trivy fs]
    E --> F[Build Debug APK<br/>ทุก branch]
    F --> G{branch == main?}
    G -->|no| I[Email Notification]
    G -->|yes| H[Build Release AAB — signed<br/>key.properties จาก Jenkins credentials<br/>ลบทิ้งใน post cleanup เสมอ]
    H --> H2[Distribute — ปิดไว้เป็นค่าเริ่มต้น<br/>ไม่มี Firebase/Play Store จริงใน lab]
    H2 --> I
```

## ทำไมสอง pipeline ถึงแยกกัน

- คนละ runtime/toolchain (Node.js vs Flutter/Android SDK ~5GB) — รวมกันจะทำให้ agent image
  ใหญ่และช้าโดยไม่จำเป็นสำหรับแอปที่ไม่เกี่ยวข้อง
- คนละจังหวะการ deploy จริง (taskflow-api deploy ขึ้น k3d ทุก merge, taskflow-mobile ต้อง build
  AAB ให้คนโหลดไปทดสอบ ไม่ได้ deploy อัตโนมัติแบบเดียวกัน)
- Approval/health gate ของฝั่ง production deploy (blue/green) ไม่เกี่ยวกับ mobile release เลย

## Agent placement

| Stage กลุ่ม | agent | เหตุผล |
|---|---|---|
| Secrets/Lint/Test/SAST/SCA/SBOM/Policy/Sonar/Quality Gate (api) | Kubernetes dynamic pod (`kind-taskflow` cloud) | Stateless, ไม่ต้องคุย docker daemon ตรงๆ |
| E2E, Build Image, Container Scan(นอกเหนือจาก Trivy pod), Blue/Green Deploy | static `linux-build-agent` | ต้องคุย docker daemon/kubeconfig ภายนอกจริง — Docker Desktop บล็อก nested DinD ใน k8s pod (ดู comment ใน Jenkinsfile) |
| ทุก stage ของ taskflow-mobile | static `linux-build-agent` (docker agent เดียวตลอด pipeline) | pub-cache/.gradle ต้องอยู่ container เดียวกันตลอด ไม่งั้นหายระหว่าง stage |

## Observability & Notification

- Prometheus (`/prometheus/` metrics endpoint) + Grafana dashboard "Jenkins Pipeline Health"
  (Lab 09) — ข้อมูลที่ Pipeline Health Gate query มาใช้ตัดสินใจ
- MailHog (container `mailhog`, network เดียวกับ `jenkins-lab01`) เป็น SMTP catcher local —
  ดู notification จริงได้ที่ http://localhost:8025 โดยไม่ต้องมี Slack workspace/token จริง
