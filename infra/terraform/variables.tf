variable "ansible_ssh_public_key" {
  description = "public key (ไม่ใช่ secret) สำหรับให้ container ansible-target เชื่อถือ"
  type        = string
}
