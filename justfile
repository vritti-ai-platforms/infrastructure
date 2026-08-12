# Vritti infrastructure — task runner (install: `brew install just`).
# Bare `just` lists every recipe. Every recipe wraps `infisical run` so tofu + ansible get their secrets.
#
# tofu recipes take a FOLDER arg — a dir under tofu/, each with its own state:
#   network → reserved IPs, DNS, zero-trust, the shared vritti-core security group
#   cloud   → the cloud control-plane VM
#   apw1    → the apw1 core/agent VM      (copy for apw2, …)
# ansible recipes take an ENV arg — the deployment (apw1, apw2, …, or `dev`).
# Omit the arg on any recipe to get an interactive picker menu.

_default:
    @just --list

# Point the admin-SSH allow-list at this machine's current public IP and apply it (network + cloud SGs)
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

# tofu plan a folder (network | cloud | apwN) — preview infra changes; picker menu if omitted
tf-plan folder="": (_tf "plan" folder)
# tofu apply a folder — create/update its infra (tofu then confirms); picker menu if omitted
tf-apply folder="": (_tf "apply" folder)
# tofu init a folder — run after a new folder / module / provider change; picker menu if omitted
tf-init folder="": (_tf "init" folder)
# Show a tofu folder's outputs (IPs, IDs, …); picker menu if omitted
tf-output folder="": (_tf "output" folder)
# tofu destroy a folder's resources (tofu then confirms yes/no); picker menu if omitted
tf-destroy folder="": (_tf "destroy" folder)

# Drift check — plan every tofu folder and print its "No changes" / "Plan:" summary
tf-plan-all:
    @for r in {{tf_folders}}; do echo "── $r ──"; (cd tofu/$r && infisical run --silent -- tofu plan -no-color 2>&1 | grep -iE "No changes|Plan:" | head -1) || true; done

# Format all tofu files (tofu fmt -recursive)
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

# Provision the CLOUD control-plane VM — all (full) | images (refresh) | nginx (reload); picker menu if omitted
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

# FULL-provision a core/agent VM — base + docker + agent roles + first enroll; picker menu if env omitted
ansi-core env="":
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{env}}"
    if [ -z "$sel" ]; then
      echo "Select a core env:" >&2; PS3="> "
      select sel in {{core_envs}}; do [ -n "$sel" ] && break; done
    fi
    cd ansible/core && infisical run --env="$sel" --path=/agent/ansible -- ansible-playbook site.yml

# Roll a core VM's agent to the latest image — force-pull latest-main + restart; enrollment kept; menu if omitted
ansi-core-agent env="":
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{env}}"
    if [ -z "$sel" ]; then
      echo "Select a core env:" >&2; PS3="> "
      select sel in {{core_envs}}; do [ -n "$sel" ] && break; done
    fi
    cd ansible/core && infisical run --env="$sel" --path=/agent/ansible -- \
      ansible-playbook site.yml --tags agent -e agent_force_restart=true

# Re-enroll a core VM's agent with a FRESH single-use token — wipes its credential + re-enrolls (regenerate the token first; confirms)
ansi-core-agent-re-enroll env="":
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{env}}"
    if [ -z "$sel" ]; then
      echo "Select a core env:" >&2; PS3="> "
      select sel in {{core_envs}}; do [ -n "$sel" ] && break; done
    fi
    read -r -p "Reset + RE-ENROLL the agent on '$sel'? Wipes its cached credential and consumes a single-use enroll token. [y/N] " ok
    [ "$ok" = y ] || [ "$ok" = Y ] || { echo "aborted (no changes)"; exit 0; }
    cd ansible/core && infisical run --env="$sel" --path=/agent/ansible -- \
      ansible-playbook site.yml --tags agent -e agent_reset=true

# ============================ web servers =============================
# Web servers are their own Infisical project — one env per server (ws1, ws2, …). The env name IS the
# server code, so the target is {env}.vrittiai.com; each env supplies WEB_SERVER_ID, ENROLL_TOKEN, GHCR_*.
# Run these from ansible/webserver (its .infisical.json pins the web-server project).

# FULL-provision a web-server VM — base + docker + ws-agent + first enroll. Pass the env (ws1); prompts if omitted.
ansi-ws env="":
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{env}}"
    [ -n "$sel" ] || read -r -p "Web server env (ws1, ws2, …): " sel
    cd ansible/webserver && infisical run --env="$sel" --path=/agent/ansible -- \
      ansible-playbook site.yml -e target_host="${sel}.vrittiai.com"

# Roll a web server's ws-agent to the latest image — force-pull latest-main + restart; enrollment kept.
ansi-ws-agent env="":
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{env}}"
    [ -n "$sel" ] || read -r -p "Web server env (ws1, ws2, …): " sel
    cd ansible/webserver && infisical run --env="$sel" --path=/agent/ansible -- \
      ansible-playbook site.yml --tags ws-agent -e target_host="${sel}.vrittiai.com" -e ws_agent_force_restart=true

# Re-enroll a web server's ws-agent with a FRESH single-use token — wipes its credential + re-enrolls
# (regenerate the token in the admin console + update the env's ENROLL_TOKEN first; confirms).
ansi-ws-re-enroll env="":
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{env}}"
    [ -n "$sel" ] || read -r -p "Web server env (ws1, ws2, …): " sel
    read -r -p "Reset + RE-ENROLL ws-agent on ${sel}.vrittiai.com? Wipes its cached credential and consumes a single-use enroll token. [y/N] " ok
    [ "$ok" = y ] || [ "$ok" = Y ] || { echo "aborted (no changes)"; exit 0; }
    cd ansible/webserver && infisical run --env="$sel" --path=/agent/ansible -- \
      ansible-playbook site.yml --tags ws-agent -e target_host="${sel}.vrittiai.com" -e ws_agent_reset=true
