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
                sh 'npm test'
            }
            post {
                failure { script { env.FAILED_STAGE = 'Unit Test' } }
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
