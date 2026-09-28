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
        }
        stage('Lint') {
            steps {
                sh 'npm run lint'
            }
        }
        stage('Unit Test') {
            steps {
                sh 'npm test'
            }
        }
    }

    post {
        success {
            echo "${env.APP_NAME} passed on ${env.NODE_ENV}"
        }
        failure {
            echo "Failed at stage: ${env.STAGE_NAME}"
        }
        always {
            archiveArtifacts artifacts: 'npm-debug.log*', allowEmptyArchive: true
        }
    }
}
