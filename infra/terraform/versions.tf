terraform {
  required_version = ">= 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6.1"
    }
  }

  # remote state ผ่าน S3-compatible backend (LocalStack) — ห้าม commit terraform.tfstate
  # เข้าไปใน git เด็ดขาด (ดู .gitignore) ทุกครั้งที่รัน terraform init ต้องมี bucket
  # "taskflow-tfstate" อยู่ใน LocalStack ก่อนแล้ว (สร้างครั้งเดียวตอน bootstrap)
  backend "s3" {
    bucket                      = "taskflow-tfstate"
    key                         = "taskflow-lab/terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "http://host.docker.internal:4566" }
    access_key                  = "test"
    secret_key                  = "test"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
