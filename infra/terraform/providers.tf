# aws provider ชี้เข้า LocalStack (community edition) แทน AWS จริง — ไม่มีค่าใช้จ่าย ไม่ต้องมี
# credential จริง ("test"/"test" เป็นค่า dummy ที่ LocalStack ยอมรับเสมอ)
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://host.docker.internal:4566"
    s3  = "http://host.docker.internal:4566"
  }
}

# docker provider คุยกับ daemon จริงบนเครื่อง (ตัวเดียวกับที่ Jenkins ใช้อยู่แล้ว) ใช้จำลอง
# "provisioned host" ที่ Ansible จะเข้าไป configure จริงๆ เพราะ EC2 ของ LocalStack community
# เป็นแค่ metadata mock ไม่มี OS ให้ SSH เข้าไปจริง
provider "docker" {
  host = "unix:///var/run/docker.sock"
}
