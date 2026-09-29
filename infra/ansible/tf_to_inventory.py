#!/usr/bin/env python3
"""สร้าง Ansible inventory (INI) จาก `terraform output -json` (Lab 08 task 5)"""
import json
import sys


def main():
    tf_output = json.load(sys.stdin)
    host = tf_output["ansible_target_host"]["value"]
    port = tf_output["ansible_target_port"]["value"]
    user = tf_output["ansible_target_user"]["value"]

    print("[taskflow]")
    print(f"taskflow-host ansible_host={host} ansible_port={port} ansible_user={user}")


if __name__ == "__main__":
    main()
