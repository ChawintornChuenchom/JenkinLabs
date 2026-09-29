pipeline {
    agent {
        docker {
            image 'node:20-alpine'
            // บังคับให้รันบน node linux-build เพราะเป็น node เดียวที่มี Docker CLI/socket
            // ให้ agent { docker {...} } เรียก docker run ได้จริง
            label 'linux-build'
        }
    }

    environment {
        APP_NAME = 'taskflow-lab'
        NODE_ENV = 'test'
    }

    options {
        // ป้องกันไม่ให้ npm ci/test ที่ค้าง (hang) ยึด executor ไว้ตลอดไป
        // ถ้าไม่ตั้ง timeout งาน build เดียวที่ hang จะบล็อก queue ทั้งหมดของ node นี้ไม่มีกำหนด
        timeout(time: 10, unit: 'MINUTES')
    }

    stages {
        stage('Install') {
            steps {
                sh 'npm ci'
            }
            // env.STAGE_NAME ใน post ระดับบนสุด (ท้ายไฟล์) ไม่ได้ชี้ไปที่ stage ที่ fail จริง
            // มันจะเป็นชื่อ stage สังเคราะห์ "Declarative: Post Actions" เสมอ เพราะ post{} นั้น
            // รันอยู่ใน context ของตัวเองแยกจาก stage ที่เพิ่ง fail ไป จึงต้องจับชื่อ stage
            // ไว้เองตอนที่ยังอยู่ใน context ของ stage นั้นจริงๆ (ผ่าน post{failure{}} ของแต่ละ stage)
            post {
                failure { script { env.FAILED_STAGE = 'Install' } }
            }
        }
        stage('Lint') {
            steps {
                sh 'npm run lint'
            }
            post {
                failure { script { env.FAILED_STAGE = 'Lint' } }
            }
        }
        stage('Unit Test') {
            steps {
                // jest ถูกตั้งค่าไว้ใน package.json ให้ collectCoverage + ออก junit.xml/cobertura เสมอ
                sh 'npm test'
                // เก็บ coverage ไว้ส่งต่อข้าม agent เพราะ stage ถัดไปที่มี agent ของตัวเอง
                // จะได้ workspace ใหม่เปล่าๆ ไม่เห็นไฟล์จาก stage นี้เลยถ้าไม่ stash
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
            // ต้องเปลี่ยนไปใช้ node:20 (Debian, glibc) เฉพาะ stage นี้แทน
            agent {
                docker {
                    image 'node:20'
                    label 'linux-build'
                }
            }
            steps {
                // stage ที่มี agent ของตัวเองจะได้ workspace ใหม่เปล่าๆ เสมอ ต้อง checkout ซ้ำ
                // แล้วดึง coverage ที่ stash ไว้จาก Unit Test กลับมาด้วย
                checkout scm
                unstash 'coverage-report'
                withSonarQubeEnv('SonarQube') {
                    sh 'npx --yes sonarqube-scanner -Dsonar.projectKey=taskflow-lab -Dsonar.sources=src -Dsonar.tests=tests -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info'
                }
            }
            post {
                failure { script { env.FAILED_STAGE = 'SonarQube Analysis' } }
            }
        }

        stage('Quality Gate') {
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
            agent {
                docker {
                    image 'mcr.microsoft.com/playwright:v1.63.0-noble'
                    label 'linux-build'
                    // ต้อง mount docker socket เข้าไปเพราะ image playwright ไม่มี docker CLI ติดมา
                    // แต่ stage นี้ต้อง `docker compose up -d` เพื่อรัน API จริงก่อนยิง Playwright ใส่
                    args '-v /var/run/docker.sock:/var/run/docker.sock -v /var/run/docker.sock:/run/docker.sock'
                }
            }
            steps {
                // agent ของ stage นี้ก็เป็น workspace ใหม่เปล่าๆ เหมือนกัน ต้อง checkout ซ้ำ
                checkout scm
                sh 'apt-get update -qq && apt-get install -y -qq --no-install-recommends docker.io docker-compose-v2 >/dev/null 2>&1 || apt-get install -y -qq --no-install-recommends docker.io >/dev/null'
                sh 'docker compose up -d --build'
                sh 'npm ci'
                sh 'BASE_URL=http://localhost:8080 npx playwright test'
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
            when { branch 'develop' }
            steps {
                sh 'echo deploying to staging...'
            }
        }

        stage('Deploy — Production') {
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
        success {
            echo "${env.APP_NAME} passed on ${env.NODE_ENV}"
        }
        failure {
            echo "Failed at stage: ${env.FAILED_STAGE ?: env.STAGE_NAME}"
        }
        always {
            archiveArtifacts artifacts: 'npm-debug.log*', allowEmptyArchive: true
        }
    }
}
