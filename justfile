# Vritti infrastructure — task runner (install: `brew install just`).
# Bare `just` lists every recipe. Every recipe wraps `infisical run` so tofu + ansible get secrets.
#
# tofu takes a FOLDER arg — one of the dirs under tofu/, each with its own state:
#   network → reserved IPs, DNS, zero-trust, the shared vritti-core security group
#   cloud   → the cloud control-plane VM
#   apw1    → the apw1 core VM         (copy for apw2, …)
# e.g.  just tf-plan network   ·   just tf-apply cloud   ·   just tf-init apw1

_default:
    @just --list

# Point the admin SSH allow-list at THIS machine's current public IP, then apply the SG roots
# (network = shared vritti-core SG, cloud = vritti-cloud SG). Run after your ISP changes your IP.
ip-update:
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(curl -fsS https://api.ipify.org)
    [ -n "$ip" ] || { echo "could not detect public IP" >&2; exit 1; }
    echo "Current public IP: $ip"
    read -r -p "Set admin SSH allow-list to ${ip}/32 and apply (network + cloud)? [y/N] " ok
    [ "$ok" = y ] || [ "$ok" = Y ] || { echo "aborted (no changes)"; exit 0; }
    for r in network cloud; do
      printf 'ssh_allowed_cidr = "%s/32"\n' "$ip" > "tofu/$r/admin.auto.tfvars"
    done
    for r in network cloud; do
      echo "── applying $r ──"
      (cd "tofu/$r" && infisical run -- tofu apply -auto-approve)
    done
    echo "✓ admin SSH now allowed from ${ip}/32 on the cloud + core VMs — you can run ansi-* now."

# ================================ tofu ================================
# Every deployable folder under tofu/ (auto-discovered; modules/infisical excluded).
tf_folders := `ls -d tofu/*/ 2>/dev/null | xargs -n1 basename | grep -vxE 'modules|infisical' | sort | tr '\n' ' '`

# Plan a folder (menu if omitted) — `just tf-plan` or `just tf-plan network`
tf-plan folder="": (_tf "plan" folder)
# Apply a folder (menu if omitted; tofu then asks y/n) — `just tf-apply` or `just tf-apply cloud`
tf-apply folder="": (_tf "apply" folder)
# Re-init a folder (new folder / module / provider change) — `just tf-init` or `just tf-init apw1`
tf-init folder="": (_tf "init" folder)
# Show a folder's outputs — `just tf-output` or `just tf-output network`
tf-output folder="": (_tf "output" folder)

# Drift check across every folder
tf-plan-all:
    @for r in {{tf_folders}}; do echo "── $r ──"; (cd tofu/$r && infisical run --silent -- tofu plan -no-color 2>&1 | grep -iE "No changes|Plan:" | head -1) || true; done

# Format all tofu files
tf-fmt:
    cd tofu && tofu fmt -recursive

# (internal) run `tofu <cmd>` in a folder; pops a picker menu when folder is blank
_tf cmd folder:
    #!/usr/bin/env bash
    set -euo pipefail
    folder="{{folder}}"
    if [ -z "$folder" ]; then
      echo "Select a tofu folder to {{cmd}}:" >&2
      PS3="> "
      select folder in {{tf_folders}}; do [ -n "$folder" ] && break; done
    fi
    [ -d "tofu/$folder" ] || { echo "no tofu folder '$folder' — one of: {{tf_folders}}" >&2; exit 1; }
    cd "tofu/$folder" && infisical run -- tofu {{cmd}}

# ============================== ansible ===============================
# Core envs: the apwN tofu folders + the cloud dev core (auto-discovered).
core_envs := `(ls -d tofu/*/ 2>/dev/null | xargs -n1 basename | grep -vxE 'modules|infisical|network|cloud'; echo dev) | sort -u | tr '\n' ' '`

# Cloud VM (menu if omitted) — all (full provision) | images (refresh) | nginx (reload).
# e.g. `just ansi-cloud` or `just ansi-cloud all`
ansi-cloud cmd="":
    #!/usr/bin/env bash
    set -euo pipefail
    cmd="{{cmd}}"
    if [ -z "$cmd" ]; then
      echo "Select a cloud action:" >&2; PS3="> "
      select cmd in all images nginx; do [ -n "$cmd" ] && break; done
    fi
    case "$cmd" in
      all)    pb=site.yml;;
      images) pb=update-cloud-images.yml;;
      nginx)  pb=nginx.yml;;
      *) echo "ansi-cloud: cmd must be all | images | nginx (got '$cmd')" >&2; exit 1;;
    esac
    cd ansible/cloud && infisical run -- ansible-playbook "$pb"

# Core agent VM — FULL provision (base + docker + agent). Menu if env omitted.
# e.g. `just ansi-core` or `just ansi-core apw1`   (--path=/agent baked in)
ansi-core env="":
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{env}}"
    if [ -z "$sel" ]; then
      echo "Select a core env:" >&2; PS3="> "
      select sel in {{core_envs}}; do [ -n "$sel" ] && break; done
    fi
    cd ansible/core && infisical run --env="$sel" --path=/agent -- ansible-playbook site.yml

# Roll the AGENT to the latest image only (skips base/docker; force-pulls latest-main + restarts).
# Fast update on an already-bootstrapped core VM; enrollment is preserved. Menu if env omitted.
# (use `just ansi-core <env>` with `-e agent_reset=true` if you need a clean re-enroll instead.)
# e.g. `just ansi-core-agent` or `just ansi-core-agent apw1`
ansi-core-agent env="":
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{env}}"
    if [ -z "$sel" ]; then
      echo "Select a core env:" >&2; PS3="> "
      select sel in {{core_envs}}; do [ -n "$sel" ] && break; done
    fi
    cd ansible/core && infisical run --env="$sel" --path=/agent -- \
      ansible-playbook site.yml --tags agent -e agent_force_restart=true
