// agent none ที่ระดับบนสุด + ประกาศ agent ชัดเจนแยกทุก stage
// เหตุผล: ถ้าตั้ง agent { docker {...} } ไว้ที่ระดับ pipeline แล้วมี stage ใด override เป็น
// docker image อื่น จะชนบั๊กที่รู้จักกันดีของ Jenkins (JENKINS-30600) — launcher ที่ทำให้ sh
// รันใน container ถูก "decorate" ผิด ทำให้ stage ที่สลับ image ไม่เจอแม้แต่ docker เอง
// (เจอจริงตอนทำ Lab 05: SonarQube Analysis ต้องใช้ node:20 ธรรมดา ไม่ใช่ node:20-alpine)
// วิธีแก้ที่ทางการแนะนำคือให้ทุก stage ประกาศ agent ของตัวเองเสมอ ไม่มี "inherit จาก top-level"
pipeline {
    agent none

    environment {
        APP_NAME = 'taskflow-lab'
        NODE_ENV = 'test'
    }

    options {
        // ป้องกันไม่ให้ npm ci/test ที่ค้าง (hang) ยึด executor ไว้ตลอดไป
        // ถ้าไม่ตั้ง timeout งาน build เดียวที่ hang จะบล็อกคิวทั้งหมดของ node นี้ไม่มีกำหนด
        timeout(time: 15, unit: 'MINUTES')
    }

    stages {
        // ===== Lab 06 — Shift-Left Security Pipeline =====
        // ลำดับ stage ต้องเป็น secrets -> SAST -> SCA -> SBOM -> policy เสมอ (ก่อน stage build/Install)
        // เครื่องมือ opa/syft/cosign เป็น static binary ไม่มี shell ติดมาในอิมเมจ (distroless)
        // ใช้กับ docker.image().inside() ของ Jenkins ไม่ได้เลย (exec เข้าไปไม่ได้ ไม่มี /bin/sh)
        // จึงดาวน์โหลด binary ตรงๆ ด้วย wget ของ busybox (มีอยู่แล้วใน node:20-alpine โดยไม่ต้อง
        // apk add ซึ่งจะติด permission denied เพราะ Jenkins บังคับรัน container ด้วย -u 1000:1000)
        stage('Secrets Detection') {
            // อิมเมจ gitleaks ตั้ง ENTRYPOINT เป็น ["gitleaks"] เอง (ไม่ใช่ shell เปล่า) ถ้าไม่ล้าง
            // entrypoint ออกก่อน คำสั่ง keep-alive "cat" ที่ Jenkins ต่อท้ายให้อัตโนมัติจะกลายเป็น
            // "gitleaks cat" (แปลว่าสั่ง subcommand cat ให้ gitleaks ซึ่งไม่มีจริง) ทำให้ container
            // ตายทันทีก่อน Jenkins จะ exec sh เข้าไปได้ (เจอ error "container ... is not running")
            agent { docker { image 'zricethezav/gitleaks:v8.30.1'; label 'linux-build'; args '--entrypoint=""' } }
            steps {
                checkout scm
                sh 'gitleaks detect --source . --report-format sarif --report-path gitleaks-report.sarif -v'
            }
            post {
                always { archiveArtifacts artifacts: 'gitleaks-report.sarif', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'Secrets Detection' } }
            }
        }

        stage('SAST — ESLint') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            steps {
                checkout scm
                sh 'npm ci'
                sh 'npx eslint --format json --output-file eslint-report.json src/'
            }
            post {
                always { archiveArtifacts artifacts: 'eslint-report.json', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'SAST — ESLint' } }
            }
        }

        stage('SAST — Semgrep') {
            agent { docker { image 'semgrep/semgrep:1.178.0'; label 'linux-build' } }
            steps {
                checkout scm
                sh 'semgrep --config=p/owasp-top-ten --config=p/nodejs --sarif --output=semgrep-report.sarif src/'
            }
            post {
                always { archiveArtifacts artifacts: 'semgrep-report.sarif', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'SAST — Semgrep' } }
            }
        }

        stage('SCA — npm audit') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            steps {
                checkout scm
                sh 'npm ci'
                script {
                    // ห้ามให้ exit code ของ npm audit เองฆ่า stage ตรงๆ (blanket exit-zero ไม่ถูกต้อง
                    // ตามโจทย์) ต้องอ่านค่า critical จาก JSON เองแล้วตัดสินใจ fail/warn เอง
                    sh 'npm audit --audit-level=high --json > audit.json || true'
                    def critical = sh(
                        script: "node -e \"console.log(require('./audit.json').metadata.vulnerabilities.critical)\"",
                        returnStdout: true
                    ).trim().toInteger()
                    if (critical > 0) {
                        error("Blocking: ${critical} critical vulnerabilities found")
                    }
                    echo "SCA passed with 0 critical vulnerabilities (warnings allowed)"
                }
            }
            post {
                always { archiveArtifacts artifacts: 'audit.json', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'SCA — npm audit' } }
            }
        }

        stage('Generate SBOM') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            steps {
                checkout scm
                sh 'npm ci'
                // ดาวน์โหลด binary ไว้ใน workspace เอง ห้ามเขียนที่ /usr/local/bin เพราะ Jenkins
                // รัน container ด้วย -u 1000:1000 (ไม่ใช่ root) เขียนโฟลเดอร์ระบบไม่ได้ (Permission denied)
                sh '''
                    wget -q -O syft.tar.gz https://github.com/anchore/syft/releases/download/v1.52.0/syft_1.52.0_linux_amd64.tar.gz
                    tar xzf syft.tar.gz syft
                    chmod +x syft
                    ./syft scan dir:. -o cyclonedx-json=sbom.cdx.json
                '''
                withCredentials([
                    file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY_FILE'),
                    string(credentialsId: 'cosign-password', variable: 'COSIGN_PASSWORD')
                ]) {
                    sh '''
                        wget -q -O cosign https://github.com/sigstore/cosign/releases/download/v3.1.3/cosign-linux-amd64
                        chmod +x cosign
                        ./cosign sign-blob --key "$COSIGN_KEY_FILE" --bundle sbom.cdx.json.bundle --yes sbom.cdx.json
                    '''
                    // cosign v3 เลิกใช้ --output-signature (.sig เดี่ยวๆ) แล้ว บังคับให้ใช้
                    // --bundle แทน ไฟล์ bundle นี้รวมทั้งลายเซ็นและ verification material ไว้ในตัว
                }
            }
            post {
                always { archiveArtifacts artifacts: 'sbom.cdx.json,sbom.cdx.json.bundle,cosign.pub', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'Generate SBOM' } }
            }
        }

        stage('Policy Gate') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            steps {
                checkout scm
                sh '''
                    wget -q -O opa https://openpolicyagent.org/downloads/v1.21.0/opa_linux_amd64_static
                    chmod +x opa
                    ./opa eval --data policy/security.rego --input audit.json "data.security.deny" --format pretty | tee opa-violations.json
                    VIOLATIONS=$(./opa eval --data policy/security.rego --input audit.json "count(data.security.deny)" --format raw)
                    echo "Policy violations: $VIOLATIONS"
                    if [ "$VIOLATIONS" -gt 0 ]; then
                        echo "Policy Gate: BLOCKED"
                        exit 1
                    fi
                    echo "Policy Gate: PASSED"
                '''
            }
            post {
                always { archiveArtifacts artifacts: 'opa-violations.json', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'Policy Gate' } }
            }
        }
        // ===== จบ Lab 06 =====

        stage('Install') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            steps {
                checkout scm
                sh 'npm ci'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'npm-debug.log*', allowEmptyArchive: true
                }
                failure { script { env.FAILED_STAGE = 'Install' } }
            }
        }

        stage('Lint') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            steps {
                checkout scm
                sh 'npm run lint'
            }
            post {
                failure { script { env.FAILED_STAGE = 'Lint' } }
            }
        }

        stage('Unit Test') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            steps {
                checkout scm
                // jest ถูกตั้งค่าไว้ใน package.json ให้ collectCoverage + ออก junit.xml/cobertura เสมอ
                sh 'npm test'
                stash name: 'coverage-report', includes: 'coverage/**'
            }
            post {
                always {
                    junit testResults: 'reports/junit.xml', allowEmptyResults: true
                    recordCoverage tools: [[parser: 'COBERTURA', pattern: 'coverage/cobertura-coverage.xml']]
                }
                failure { script { env.FAILED_STAGE = 'Unit Test' } }
            }
        }

        stage('SonarQube Analysis') {
            // sonar-scanner-cli ที่ npx ดาวน์โหลดมาพก JRE แบบ glibc มาด้วย รันบน node:20-alpine
            // (musl libc) ไม่ได้เลยแม้ลง gcompat แล้วก็ตาม (JVM ต้องการมากกว่าที่ gcompat ให้ได้)
            // ต้องใช้ node:20 (Debian, glibc) สำหรับ stage นี้โดยเฉพาะ
            agent { docker { image 'node:20'; label 'linux-build' } }
            steps {
                checkout scm
                unstash 'coverage-report'
                // withSonarQubeEnv ตั้ง SONAR_HOST_URL ให้ถูกต้อง แต่ SONAR_AUTH_TOKEN กลับว่างเปล่า
                // (พบว่าเวอร์ชัน SonarQube ตอนแรก 9.9.8 LTS เก่าเกินไปจนไม่รองรับ Bearer-token auth
                // ของ sonar plugin เวอร์ชันใหม่ด้วย ต้องอัปเกรดเป็น community edition 26.9.0 ล่าสุดแทน)
                // จึงดึง token มาเองตรงๆ ผ่าน withCredentials แล้วส่งเป็น sonar.token (มาตรฐานปัจจุบัน)
                withSonarQubeEnv('SonarQube') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        sh 'npx --yes sonarqube-scanner -Dsonar.projectKey=taskflow-lab -Dsonar.sources=src -Dsonar.tests=tests -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=$SONAR_HOST_URL'
                    }
                }
            }
            post {
                failure { script { env.FAILED_STAGE = 'SonarQube Analysis' } }
            }
        }

        stage('Quality Gate') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                failure { script { env.FAILED_STAGE = 'Quality Gate' } }
            }
        }

        stage('E2E') {
            // ไม่ใช้ agent { docker {...} } ตรงนี้ เพราะ image playwright ไม่มี docker CLI ติดมา
            // และ Jenkins บังคับรัน container ด้วย -u 1000:1000 (ไม่ใช่ root) ทำให้ apt-get
            // ติดตั้ง docker เข้าไปเองไม่ได้เลย (Permission denied)
            // ใช้ agent เปล่าบน linux-build (มี docker CLI อยู่แล้ว) รัน docker compose ตรงนั้น
            // แล้วค่อยเข้า container playwright เฉพาะตอนรัน Playwright เอง ผ่าน docker.image().inside()
            agent { label 'linux-build' }
            steps {
                checkout scm
                sh 'docker compose up -d --build'
                script {
                    docker.image('mcr.microsoft.com/playwright:v1.63.0-noble').inside() {
                        sh 'npm ci'
                        // เรียกผ่าน host.docker.internal เพราะ container playwright กับ container API
                        // เป็นคนละ container กัน ไม่ได้อยู่ compose network เดียวกัน (--network=host
                        // ใช้ไม่ได้บน Docker Desktop Windows/Mac)
                        sh 'BASE_URL=http://host.docker.internal:18080 npx playwright test'
                    }
                }
            }
            post {
                always {
                    sh 'docker compose down || true'
                    junit testResults: 'reports/e2e-junit.xml', allowEmptyResults: true
                    publishHTML(target: [
                        reportDir: 'playwright-report',
                        reportFiles: 'index.html',
                        reportName: 'Playwright E2E Report',
                        keepAll: true,
                        alwaysLinkToLastBuild: true,
                    ])
                }
                failure { script { env.FAILED_STAGE = 'E2E' } }
            }
        }

        stage('Deploy — Staging') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            when { branch 'develop' }
            steps {
                sh 'echo deploying to staging...'
            }
        }

        stage('Deploy — Production') {
            agent { docker { image 'node:20-alpine'; label 'linux-build' } }
            // ค่าเริ่มต้นของ Declarative Pipeline คือ beforeInput=false ซึ่งหมายความว่า
            // stage ที่มีทั้ง when และ input จะเจอ input prompt ถามก่อนที่จะเช็ค when เสียอีก!
            // (แม้แต่โค้ดตัวอย่างในเอกสารคอร์สเองก็ไม่ได้ใส่ beforeInput ไว้ ทำให้ branch develop
            // โดนถาม "Deploy to production?" ทั้งที่ควรถูกข้ามไปเพราะไม่ใช่ branch main)
            // ต้องใส่ beforeInput true เพื่อบังคับให้เช็ค when ก่อนเสมอ
            when {
                branch 'main'
                beforeInput true
            }
            input {
                message 'Deploy to production?'
            }
            steps {
                sh 'echo deploying to production...'
            }
        }
    }

    post {
        // ไม่มี agent ระดับบนสุดแล้ว (agent none) จึง echo อย่างเดียวพอ ห้ามแตะไฟล์ในนี้
        success {
            echo "${env.APP_NAME} passed on ${env.NODE_ENV}"
        }
        failure {
            echo "Failed at stage: ${env.FAILED_STAGE ?: env.STAGE_NAME}"
        }
    }
}
