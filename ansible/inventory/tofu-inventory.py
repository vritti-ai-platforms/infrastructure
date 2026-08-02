#!/usr/bin/env python3
# Dynamic Ansible inventory sourced from the tofu compute layer's outputs, so VM IPs are
# never hand-copied. Emits groups vm1 + vm2 (matching group_vars/) with ansible_host set from
# vm{1,2}_public_ipv4. vm2 here is the HOST bootstrap (base/docker/GHCR) via vm2.yml; the agent
# itself is deployed by ../agent/agent.yml, which uses its OWN static inventory (vritti-core env,
# no tofu creds) — so agent/ does not use this script.
#
#   TOFU_DIR   override the compute dir (default: ../../tofu/compute relative to this script)
#   TOFU_BIN   override the binary (default: tofu, falling back to terraform)
#
# Usage (Ansible calls it automatically): tofu-inventory.py --list

import json
import os
import shutil
import subprocess
import sys

HOSTS = {
    "vm1": ("vritti-vm1", "vm1_public_ipv4"),
    "vm2": ("vritti-vm2", "vm2_public_ipv4"),
}


def tofu_dir() -> str:
    if os.environ.get("TOFU_DIR"):
        return os.environ["TOFU_DIR"]
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "..", "tofu", "compute"))


def tofu_bin() -> str:
    if os.environ.get("TOFU_BIN"):
        return os.environ["TOFU_BIN"]
    return "tofu" if shutil.which("tofu") else "terraform"


def read_outputs() -> dict:
    try:
        out = subprocess.run(
            [tofu_bin(), "output", "-json"],
            cwd=tofu_dir(),
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(out.stdout or "{}")
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        detail = getattr(e, "stderr", "") or str(e)
        sys.stderr.write(
            f"[tofu-inventory] could not read tofu outputs from {tofu_dir()}: {detail.strip()}\n"
            "[tofu-inventory] run inside `infisical run -- ...` after `tofu apply`, "
            "or set TOFU_DIR.\n"
        )
        return {}


def build_inventory() -> dict:
    outputs = read_outputs()
    inv = {"_meta": {"hostvars": {}}}
    for group, (host, output_key) in HOSTS.items():
        entry = outputs.get(output_key)
        ip = entry.get("value") if isinstance(entry, dict) else None
        inv[group] = {"hosts": []}
        if ip:
            inv[group]["hosts"].append(host)
            inv["_meta"]["hostvars"][host] = {"ansible_host": ip}
        else:
            sys.stderr.write(f"[tofu-inventory] output {output_key} not found — {group} has no host\n")
    return inv


def main() -> None:
    if "--host" in sys.argv:
        print(json.dumps({}))
        return
    print(json.dumps(build_inventory(), indent=2))


if __name__ == "__main__":
    main()
