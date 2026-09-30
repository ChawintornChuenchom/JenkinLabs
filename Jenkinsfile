// Lab 10 (Capstone) — restructured จาก Lab 03-09:
// - stage ที่เป็นอิสระจากกัน (lint, unit test, SAST, SCA) รวมเป็น parallel block เดียว
//   ("Verify") ตาม fail-fast/parallelize best practice ส่วน build -> scan -> deploy ยังคง
//   sequential เพราะแต่ละ stage "ต้องรอ" ผลลัพธ์ของ stage ก่อนหน้าจริงๆ (immutable image tag,
//   scan ต้องมี image ให้ scan ก่อน, deploy ต้องรอ scan ผ่านก่อน)
// - ทุก stage ที่ทำได้ย้ายไปรันบน Kubernetes dynamic agent (Lab 09 kind-taskflow cloud) แทน
//   static container บน linux-build-agent แล้ว เหลือแค่ 4 stage ที่ "ต้อง" อยู่บน static agent
//   จริงๆ เพราะต้องคุย docker daemon ตรงๆ (Build Image, Container Scan ผ่าน trivy ที่ scan
//   image ในเครื่อง, E2E ที่รัน docker compose, Blue/Green Deploy ที่ยิง kubectl ผ่าน kubeconfig
//   ภายนอก) — เคยลองทำ Docker-in-Docker ซ้อนในเป็น k8s pod จริงจังแล้วใน Lab 08 แต่ Docker
//   Desktop บล็อก unshare()/mount() ที่จำเป็นเสมอ แม้ pod จะ privileged ก็ตาม นี่จึงเป็นข้อจำกัด
//   ของสภาพแวดล้อมจริง ไม่ใช่การเลี่ยงงาน — บันทึกไว้ตรงนี้เพื่อความโปร่งใส
pipeline {
    agent none

    environment {
        APP_NAME = 'taskflow-lab'
        NODE_ENV = 'test'
    }

    options {
        timeout(time: 20, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {
        // ===== Lab 06 — Shift-Left Security Pipeline =====
        // ลำดับต้องเป็น secrets -> SAST -> SCA -> SBOM -> policy เสมอ (ก่อน build) — SAST/SCA
        // ถูกยกเข้าไปอยู่ใน parallel block "Verify" ด้านล่างแล้ว (ยังอยู่ "ก่อน build" เหมือนเดิม
        // แค่รันพร้อมกับ lint/unit test แทนที่จะเรียงทีละตัว)
        stage('Secrets Detection') {
            // ใช้ pod ของ Kubernetes cloud (Lab 09) แทน docker agent เดิม — สั่ง command ตรงๆ ใน
            // pod spec ให้ชัดเจน แทนที่จะพึ่ง args '--entrypoint=""' แบบฝั่ง docker-workflow
            // label ต้องไม่ซ้ำกับ pod อื่นที่ใช้ image คนละตัว — Kubernetes plugin จะ "รวม" pod
            // template ที่ label เดียวกันเข้าด้วยกัน (เจอบั๊กจริงตอนทดสอบ: SAST — Semgrep ที่ควรได้
            // container ชื่อ semgrep กลับกลายเป็น node เพราะ label ชนกับ stage อื่นที่ใช้ node:20-alpine)
            agent {
                kubernetes {
                    label 'k8s-gitleaks'
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: gitleaks
                            image: zricethezav/gitleaks:v8.30.1
                            command: ['cat']
                            tty: true
                    '''
                }
            }
            steps {
                checkout scm
                container('gitleaks') {
                    sh 'gitleaks detect --source . --report-format sarif --report-path gitleaks-report.sarif -v'
                }
            }
            post {
                always { archiveArtifacts artifacts: 'gitleaks-report.sarif', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'Secrets Detection' } }
            }
        }

        // ===== Lab 10 task 1 — parallel block =====
        // lint, unit test, SAST (ESLint + Semgrep), SCA ไม่มีตัวไหนต้องพึ่งผลลัพธ์ของกันและกัน
        // เลย (ต่างคน checkout + npm ci ของตัวเองอิสระ) จึงรันพร้อมกันได้ปลอดภัย ประหยัดเวลารวม
        // ของ pipeline ไปมากเมื่อเทียบกับรันทีละ stage แบบเดิม
        stage('Verify') {
            failFast false
            parallel {
                stage('Lint') {
                    agent {
                        kubernetes {
                            label 'k8s-node'
                            yaml '''
                                apiVersion: v1
                                kind: Pod
                                spec:
                                  containers:
                                  - name: node
                                    image: node:20-alpine
                                    command: ['cat']
                                    tty: true
                            '''
                        }
                    }
                    steps {
                        checkout scm
                        container('node') {
                            sh 'npm run lint'
                        }
                    }
                    post {
                        failure { script { env.FAILED_STAGE = 'Lint' } }
                    }
                }

                stage('Unit Test') {
                    agent {
                        kubernetes {
                            label 'k8s-node'
                            yaml '''
                                apiVersion: v1
                                kind: Pod
                                spec:
                                  containers:
                                  - name: node
                                    image: node:20-alpine
                                    command: ['cat']
                                    tty: true
                            '''
                        }
                    }
                    steps {
                        checkout scm
                        container('node') {
                            // jest ถูกตั้งค่าไว้ใน package.json ให้ collectCoverage + ออก junit.xml/cobertura เสมอ
                            sh 'npm ci && npm test'
                        }
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

                stage('SAST — ESLint') {
                    agent {
                        kubernetes {
                            label 'k8s-node'
                            yaml '''
                                apiVersion: v1
                                kind: Pod
                                spec:
                                  containers:
                                  - name: node
                                    image: node:20-alpine
                                    command: ['cat']
                                    tty: true
                            '''
                        }
                    }
                    steps {
                        checkout scm
                        container('node') {
                            sh 'npm ci'
                            sh 'npx eslint --format json --output-file eslint-report.json src/'
                        }
                    }
                    post {
                        always { archiveArtifacts artifacts: 'eslint-report.json', allowEmptyArchive: true }
                        failure { script { env.FAILED_STAGE = 'SAST — ESLint' } }
                    }
                }

                stage('SAST — Semgrep') {
                    agent {
                        kubernetes {
                            label 'k8s-semgrep'
                            yaml '''
                                apiVersion: v1
                                kind: Pod
                                spec:
                                  containers:
                                  - name: semgrep
                                    image: semgrep/semgrep:1.178.0
                                    command: ['cat']
                                    tty: true
                            '''
                        }
                    }
                    steps {
                        checkout scm
                        container('semgrep') {
                            sh 'semgrep --config=p/owasp-top-ten --config=p/nodejs --sarif --output=semgrep-report.sarif src/'
                        }
                    }
                    post {
                        always { archiveArtifacts artifacts: 'semgrep-report.sarif', allowEmptyArchive: true }
                        failure { script { env.FAILED_STAGE = 'SAST — Semgrep' } }
                    }
                }

                stage('SCA — npm audit') {
                    agent {
                        kubernetes {
                            label 'k8s-node'
                            yaml '''
                                apiVersion: v1
                                kind: Pod
                                spec:
                                  containers:
                                  - name: node
                                    image: node:20-alpine
                                    command: ['cat']
                                    tty: true
                            '''
                        }
                    }
                    steps {
                        checkout scm
                        container('node') {
                            sh 'npm ci'
                            script {
                                // ห้ามให้ exit code ของ npm audit เองฆ่า stage ตรงๆ (blanket exit-zero ไม่ถูกต้อง
                                // ตามโจทย์ Lab 06) ต้องอ่านค่า critical จาก JSON เองแล้วตัดสินใจ fail/warn เอง
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
                        // Policy Gate อยู่คนละ parallel branch/workspace กัน ต้อง stash ไฟล์นี้ส่งต่อ
                        // ให้ชัดเจน จะพึ่ง "workspace เดียวกันเผื่อไว้" แบบตอน sequential ไม่ได้อีกแล้ว
                        stash name: 'audit-json', includes: 'audit.json'
                    }
                    post {
                        always { archiveArtifacts artifacts: 'audit.json', allowEmptyArchive: true }
                        failure { script { env.FAILED_STAGE = 'SCA — npm audit' } }
                    }
                }
            }
        }

        stage('Generate SBOM') {
            agent {
                kubernetes {
                    label 'k8s-node'
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: node
                            image: node:20-alpine
                            command: ['cat']
                            tty: true
                    '''
                }
            }
            steps {
                checkout scm
                container('node') {
                    sh 'npm ci'
                    // ดาวน์โหลด binary ไว้ใน workspace เอง ห้ามเขียนที่ /usr/local/bin เพราะ Jenkins
                    // รัน container ด้วย non-root uid เขียนโฟลเดอร์ระบบไม่ได้ (Permission denied)
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
                            chmod 644 sbom.cdx.json.bundle
                        '''
                        // cosign v3 เลิกใช้ --output-signature (.sig เดี่ยวๆ) แล้ว บังคับให้ใช้
                        // --bundle แทน ไฟล์ bundle นี้รวมทั้งลายเซ็นและ verification material ไว้ในตัว
                        // chmod 644 จำเป็นมาก: cosign เขียนไฟล์ bundle ด้วย permission 0600 (เจ้าของ
                        // อ่านได้คนเดียว) โดยตั้งใจ แต่ container 'jnlp' ที่ทำหน้าที่ส่งไฟล์กลับไป
                        // Jenkins controller (archiveArtifacts) รันเป็นคนละ user กับ container 'node'
                        // ที่รัน cosign แม้จะแชร์ emptyDir volume เดียวกันก็ตาม เลยอ่านไฟล์ 0600 ที่
                        // เจ้าของเป็นอีก user ไม่ได้ ทำให้ archiveArtifacts พังด้วย error ที่แปลผิด
                        // ได้ง่ายว่าเป็นปัญหา timing ("closed at 0 before bytes were written")
                    }
                }
            }
            post {
                always { archiveArtifacts artifacts: 'sbom.cdx.json,sbom.cdx.json.bundle,cosign.pub', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'Generate SBOM' } }
            }
        }

        stage('Policy Gate') {
            agent {
                kubernetes {
                    label 'k8s-node'
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: node
                            image: node:20-alpine
                            command: ['cat']
                            tty: true
                    '''
                }
            }
            steps {
                checkout scm
                unstash 'audit-json'
                container('node') {
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
            }
            post {
                always { archiveArtifacts artifacts: 'opa-violations.json', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'Policy Gate' } }
            }
        }
        // ===== จบ Lab 06 =====

        stage('SonarQube Analysis') {
            // sonar-scanner-cli ที่ npx ดาวน์โหลดมาพก JRE แบบ glibc มาด้วย รันบน alpine (musl libc)
            // ไม่ได้เลย ต้องใช้ node:20 ธรรมดา (Debian, glibc) สำหรับ pod นี้โดยเฉพาะ
            agent {
                kubernetes {
                    label 'k8s-node-glibc'
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: node
                            image: node:20
                            command: ['cat']
                            tty: true
                    '''
                }
            }
            steps {
                checkout scm
                unstash 'coverage-report'
                script {
                    // SonarQube Community Edition ไม่รองรับ branch analysis จริง ทุก branch เลย
                    // แชร์ project เดียวกันไม่ได้ (ชนกันเรื่อง analysis date) แยก project key ต่อ
                    // branch ไปเลย ให้แต่ละ branch มี timeline อิสระ (ดู Lab 07 commit ที่แก้เรื่องนี้)
                    env.SONAR_PROJECT_KEY = "taskflow-lab-${env.BRANCH_NAME.replaceAll('[^A-Za-z0-9_-]', '-')}"
                }
                container('node') {
                    withSonarQubeEnv('SonarQube') {
                        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                            sh 'npx --yes sonarqube-scanner -Dsonar.projectKey=${SONAR_PROJECT_KEY} -Dsonar.sources=src -Dsonar.tests=tests -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=$SONAR_HOST_URL'
                        }
                    }
                }
            }
            post {
                failure { script { env.FAILED_STAGE = 'SonarQube Analysis' } }
            }
        }

        stage('Quality Gate') {
            agent {
                kubernetes {
                    label 'k8s-node'
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: node
                            image: node:20-alpine
                            command: ['cat']
                            tty: true
                    '''
                }
            }
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                failure { script { env.FAILED_STAGE = 'Quality Gate' } }
            }
        }

        // ===== ต่อจากนี้: stage ที่ "ต้อง" คุย docker daemon ตรงๆ หรือ kubeconfig ภายนอก =====
        // เคยพยายามย้ายกลุ่มนี้เข้า k8s pod จริงจังมาแล้ว (Lab 08 provisioned-host ก็เจอปัญหา
        // เดียวกัน) — Docker Desktop ปฏิเสธ unshare()/mount() ที่ nested dockerd ต้องใช้เสมอ ต่อให้
        // pod privileged แล้วก็ตาม จึงคงไว้บน static linux-build-agent ที่มี docker socket จริงอยู่แล้ว
        stage('E2E') {
            agent { label 'linux-build' }
            steps {
                checkout scm
                sh 'docker compose up -d --build'
                script {
                    docker.image('mcr.microsoft.com/playwright:v1.63.0-noble').inside() {
                        sh 'npm ci'
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

        stage('Build Image') {
            agent { label 'linux-build' }
            when { anyOf { branch 'develop'; branch 'main' } }
            steps {
                checkout scm
                script {
                    env.IMAGE_TAG = env.GIT_COMMIT.take(7)
                }
                sh 'docker build -t localhost:5001/taskflow-api:${IMAGE_TAG} .'
                sh 'docker push localhost:5001/taskflow-api:${IMAGE_TAG}'
            }
            post {
                failure { script { env.FAILED_STAGE = 'Build Image' } }
            }
        }

        stage('Container Scan') {
            // ต่างจาก Lab 07: ย้ายมารันเป็น k8s pod ได้แล้ว เพราะ pod ในคลัสเตอร์ kind เข้าถึง
            // kind-registry ตรงๆ ผ่าน cluster DNS ได้เลย (ทดสอบแล้วจริง) ไม่ต้องพึ่ง
            // host.docker.internal เหมือน static agent อีกต่อไป
            agent {
                kubernetes {
                    label 'k8s-trivy'
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: trivy
                            image: aquasec/trivy:0.74.0
                            command: ['cat']
                            tty: true
                    '''
                }
            }
            when { anyOf { branch 'develop'; branch 'main' } }
            steps {
                container('trivy') {
                    sh 'trivy image --cache-dir .trivycache --insecure --exit-code 1 --severity HIGH,CRITICAL --format sarif --output trivy-report.sarif kind-registry:5000/taskflow-api:${IMAGE_TAG}'
                }
            }
            post {
                always { archiveArtifacts artifacts: 'trivy-report.sarif', allowEmptyArchive: true }
                failure { script { env.FAILED_STAGE = 'Container Scan' } }
            }
        }

        stage('Approval') {
            agent none
            when {
                branch 'main'
                beforeInput true
            }
            input {
                message 'Deploy to production (blue/green switch)?'
            }
            steps {
                echo 'Approved — proceeding to Pipeline Health Gate'
            }
        }

        // ===== Lab 10 task 4 — Pipeline Health Gate =====
        // เช็ค build success rate ล่าสุดจาก Prometheus (Lab 09) ก่อนยอมให้ deploy ขึ้น production
        // หมายเหตุความถูกต้อง: Jenkins Prometheus plugin ให้แค่ counter สะสม (total ตั้งแต่ต้น)
        // ไม่มี metric แบบ "20 build ล่าสุด" ตรงๆ จึงประมาณด้วย increase() ในหน้าต่างเวลาล่าสุด
        // (1 ชั่วโมง) แทน — เป็น proxy ที่สมเหตุสมผลที่สุดเท่าที่ metric ที่มีอยู่จะให้ได้
        stage('Pipeline Health Gate') {
            agent {
                kubernetes {
                    label 'k8s-node'
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: node
                            image: node:20-alpine
                            command: ['cat']
                            tty: true
                    '''
                }
            }
            when { branch 'main' }
            steps {
                container('node') {
                    script {
                        def query = "increase(default_jenkins_builds_success_build_count_total%7Bjenkins_job%3D%22taskflow-multibranch%2Fmain%22%7D%5B1h%5D)%20%2F%20increase(default_jenkins_builds_total_build_count_total%7Bjenkins_job%3D%22taskflow-multibranch%2Fmain%22%7D%5B1h%5D)"
                        def response = sh(
                            script: "wget -qO- 'http://host.docker.internal:9090/api/v1/query?query=${query}'",
                            returnStdout: true
                        ).trim()
                        echo "Prometheus response: ${response}"
                        def matcher = (response =~ /"value":\[[0-9.]+,"([0-9.]+)"\]/)
                        if (!matcher.find()) {
                            echo "No recent build data in Prometheus yet — treating as healthy (nothing to gate on)"
                            return
                        }
                        def rate = matcher.group(1).toDouble()
                        echo "Rolling build success rate (last 1h): ${rate * 100}%"
                        if (rate < 0.9) {
                            error("Pipeline Health Gate: BLOCKED — success rate ${rate * 100}% is below the 90% threshold")
                        }
                        echo "Pipeline Health Gate: PASSED"
                    }
                }
            }
            post {
                failure { script { env.FAILED_STAGE = 'Pipeline Health Gate' } }
            }
        }

        stage('Blue/Green Deploy') {
            agent { label 'linux-build' }
            when { anyOf { branch 'develop'; branch 'main' } }
            steps {
                withCredentials([file(credentialsId: 'k8s-credentials', variable: 'KUBECONFIG')]) {
                    script {
                        def current = sh(
                            script: "/home/jenkins/agent/kubectl get svc taskflow -o jsonpath='{.spec.selector.color}'",
                            returnStdout: true
                        ).trim()
                        def next = (current == 'blue') ? 'green' : 'blue'
                        env.PREVIOUS_COLOR = current
                        env.NEXT_COLOR = next

                        sh "/home/jenkins/agent/kubectl set image deployment/taskflow-${next} taskflow-api=localhost:5001/taskflow-api:${env.IMAGE_TAG}"
                        sh "/home/jenkins/agent/kubectl rollout status deployment/taskflow-${next} --timeout=60s"

                        // smoke test พุ่งตรงไปที่สี next ผ่าน Service เฉพาะสี ข้าม Service หลักไปเลย
                        sh "/home/jenkins/agent/kubectl run smoke-${BUILD_NUMBER} --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- curl -sf http://taskflow-${next}:8080/health"

                        sh "/home/jenkins/agent/kubectl patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${next}\"}}}'"
                        echo "Switched traffic from ${current} to ${next}"
                    }
                }
            }
            post {
                failure {
                    withCredentials([file(credentialsId: 'k8s-credentials', variable: 'KUBECONFIG')]) {
                        sh "/home/jenkins/agent/kubectl patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${env.PREVIOUS_COLOR}\"}}}'"
                    }
                    echo "Automatic rollback: Service selector restored to ${env.PREVIOUS_COLOR}"
                    script { env.FAILED_STAGE = 'Blue/Green Deploy' }
                }
            }
        }
    }

    // Lab 10 task 5 — เหตุผลเลือก email-ext แทน Slack: ดู comment เดียวกันใน mobile/Jenkinsfile.mobile
    post {
        success {
            echo "${env.APP_NAME} passed on ${env.NODE_ENV}"
            emailext(
                subject: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.BRANCH_NAME})",
                body: "Build SUCCESS\nJob: ${env.JOB_NAME}\nBranch: ${env.BRANCH_NAME}\nBuild: #${env.BUILD_NUMBER}\nURL: ${env.BUILD_URL}",
                to: '$DEFAULT_RECIPIENTS'
            )
        }
        failure {
            echo "Failed at stage: ${env.FAILED_STAGE ?: env.STAGE_NAME}"
            emailext(
                subject: "FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.BRANCH_NAME}) — ${env.FAILED_STAGE ?: env.STAGE_NAME}",
                body: "Build FAILURE at stage: ${env.FAILED_STAGE ?: env.STAGE_NAME}\nJob: ${env.JOB_NAME}\nBranch: ${env.BRANCH_NAME}\nBuild: #${env.BUILD_NUMBER}\nURL: ${env.BUILD_URL}",
                to: '$DEFAULT_RECIPIENTS'
            )
        }
    }
}
