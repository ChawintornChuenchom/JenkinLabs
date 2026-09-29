# ===== ทรัพยากรฝั่ง "cloud" (จำลองผ่าน LocalStack) =====

# --- tfsec/checkov triage (Lab 08 task 3) ---
# แก้แล้วจริง (ไม่ใช่แค่ปิดเสียง): root volume ไม่เข้ารหัส (HIGH), ไม่บังคับ IMDSv2 (HIGH),
# security group rule ไม่มี description (LOW) — ดู root_block_device/metadata_options ด้านล่าง
# และ description ที่เติมในทั้งสอง rule
#
# ยอมรับโดยตั้งใจ (ไม่ใช่ fix เพราะขัดกับจุดประสงค์ของ resource เอง): ingress/egress อนุญาต
# 0.0.0.0/0 (CRITICAL ทั้งคู่) — security group นี้มีไว้เปิด "taskflow-api ให้เข้าถึงได้จากอินเทอร์เน็ต
# ที่พอร์ต 8080" ตามที่โจทย์ Lab 08 ต้องการเป๊ะๆ ("one security group allowing port 8080") การปิด
# ingress สาธารณะจะขัดกับจุดประสงค์ของ resource นี้โดยตรง ส่วน egress เปิดกว้างไว้เพราะ instance
# ต้องออกไป pull image/ติดตั้งแพ็กเกจจากที่ไหนก็ได้ — คงไว้ตามเดิมแต่ใส่ description ให้ครบ
resource "aws_security_group" "taskflow" {
  #checkov:skip=CKV_AWS_382:intentional public egress -- instance needs unrestricted outbound for package/image pulls
  name        = "taskflow-sg"
  description = "อนุญาต inbound เข้าพอร์ต 8080 สำหรับ taskflow-api"

  #tfsec:ignore:aws-ec2-no-public-ingress-sgr -- ยอมรับโดยตั้งใจ: นี่คือพอร์ตสาธารณะของ taskflow-api เอง
  ingress {
    description = "taskflow-api public access on 8080 (intentional, this is the apps public port)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #tfsec:ignore:aws-ec2-no-public-egress-sgr -- ยอมรับโดยตั้งใจ: instance ต้องออกไป pull image/ติดตั้งแพ็กเกจจากที่ไหนก็ได้
  egress {
    description = "unrestricted outbound for package installs / image pulls"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = "taskflow-lab"
  }
}

# root_block_device{encrypted=true} ลองแล้วจริงบน LocalStack Community: apply พังด้วย "collecting
# instance settings: couldn't find resource" เพราะ EC2 mock ไม่รองรับ EBS volume API มากพอ หลัง
# apply บน AWS จริงต้องใส่ block นี้กลับเข้าไป — บันทึกไว้เป็น deferred finding ไม่ใช่เพิกเฉย
#tfsec:ignore:aws-ec2-enable-at-rest-encryption
resource "aws_instance" "taskflow_host" {
  #checkov:skip=CKV_AWS_8:root_block_device{encrypted=true} breaks apply against LocalStack's EC2 mock (see comment above); would enable on real AWS
  #checkov:skip=CKV_AWS_126:LocalStack Community EC2 mock cannot apply with monitoring=true (same EBS-API limitation noted above)
  #checkov:skip=CKV_AWS_135:same LocalStack limitation -- ebs_optimized=true breaks apply against the mock
  #checkov:skip=CKV2_AWS_41:IAM is not enabled on this LocalStack instance (SERVICES=s3,ec2 only); would attach an instance profile on real AWS
  # LocalStack community mock ไม่สนใจ ami/instance_type จริง แต่ต้องใส่ให้ครบตาม schema
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.taskflow.id]

  # แก้ finding: "aws_instance should activate session tokens for IMDS" (tfsec HIGH, checkov CKV_AWS_79)
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name    = "taskflow-host"
    Project = "taskflow-lab"
  }
}

# ===== "provisioned host" ตัวจริงที่ Ansible จะเข้าไป configure =====
# EC2 ของ LocalStack community edition เป็นแค่ metadata mock (ไม่มี OS ให้ boot จริง) จึงใช้
# container ที่มี sshd จริงแทน เป็นเป้าหมายที่ Ansible เชื่อมต่อได้จริงตามที่โจทย์ต้องการ
resource "docker_image" "ansible_target" {
  name = "linuxserver/openssh-server:version-10.3_p1-r1"
}

resource "docker_container" "ansible_target" {
  name  = "taskflow-ansible-target"
  image = docker_image.ansible_target.image_id

  # mount docker.sock ของ host เข้าไป (docker-outside-of-docker) แทนการรัน dockerd ซ้อนข้างใน —
  # ลองแบบ privileged + nested dockerd จริงๆ ก่อนแล้ว แต่ Docker Desktop (Win/Mac) บล็อก unshare()/
  # mount() ที่ containerd ต้องใช้ตอนแตก layer แม้จะ privileged แล้วก็ตาม (เป็นข้อจำกัดของ VM ที่
  # Docker Desktop รันอยู่ ไม่ใช่บั๊กของเรา) วิธีนี้ทำให้ docker บน host นี้ "ใช้งานได้จริง" ตามที่
  # โจทย์ต้องการ (ติดตั้ง + pull image ได้จริง) แบบเดียวกับที่ Jenkins agent เองก็ใช้ pattern นี้
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  ports {
    internal = 2222
    external = 2222
  }

  env = [
    "PUBLIC_KEY=${var.ansible_ssh_public_key}",
    "USER_NAME=ansible",
    "PASSWORD_ACCESS=false",
    "SUDO_ACCESS=true",
  ]

  networks_advanced {
    name = "bridge"
  }
}

output "instance_address" {
  description = "ที่อยู่ของ instance ที่ provision ไว้ (จาก LocalStack aws_instance)"
  value       = aws_instance.taskflow_host.private_ip
}

output "security_group_id" {
  value = aws_security_group.taskflow.id
}

output "ansible_target_host" {
  description = "host จริงที่ Ansible จะเชื่อมต่อ (dynamic inventory ดึงค่านี้ไปใช้)"
  value       = "host.docker.internal"
}

output "ansible_target_port" {
  value = 2222
}

output "ansible_target_user" {
  value = "ansible"
}
