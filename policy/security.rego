package security

import rego.v1

# input = ผลลัพธ์ JSON จาก `npm audit --json` (stage SCA)
# deny เมื่อพบช่องโหว่ระดับ CRITICAL อย่างน้อย 1 รายการ
deny contains msg if {
	input.metadata.vulnerabilities.critical > 0
	msg := sprintf("Policy Gate: found %d CRITICAL vulnerability(ies) in dependencies (npm audit)", [input.metadata.vulnerabilities.critical])
}
