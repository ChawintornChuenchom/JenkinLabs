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
                withSonarQubeEnv('SonarQube') {
                    sh 'npx --yes sonarqube-scanner -Dsonar.projectKey=taskflow-lab -Dsonar.sources=src -Dsonar.tests=tests -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info'
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
