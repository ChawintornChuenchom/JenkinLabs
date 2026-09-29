package security

import rego.v1

test_deny_when_critical_found if {
	count(deny) > 0 with input as {"metadata": {"vulnerabilities": {"critical": 1}}}
}

test_allow_when_no_critical if {
	count(deny) == 0 with input as {"metadata": {"vulnerabilities": {"critical": 0}}}
}
