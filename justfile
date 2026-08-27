# entitybase-test - just commands
#
# All orchestration lives here (formerly run-test.sh).

set shell := ["bash", "-cu"]

export TOFU_DIR    := "tofu"
export ANSIBLE_DIR := "ansible"
export RESULTS_DIR := "results"
export INVENTORY   := ANSIBLE_DIR + "/inventory/hosts.ini"
export GRAFANA_ADMIN_PASSWORD := env_var_or_default("GRAFANA_ADMIN_PASSWORD", "")

# List available commands
default:
    @just --list

# --- Helpers (internal) ---

# Verify required tools and OpenStack credentials
_require-vars:
    #!/usr/bin/env bash
    set -euo pipefail
    missing=0
    for cmd in tofu ansible-playbook jq; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "ERROR: Required command '$cmd' not found in PATH."
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
    if [[ ! -f "$HOME/.config/openstack/clouds.yaml" && ! -f "./clouds.yaml" ]]; then
        echo "ERROR: clouds.yaml not found."
        echo "Expected at ~/.config/openstack/clouds.yaml or ./clouds.yaml"
        missing=1
    fi
    if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
        echo "ERROR: GRAFANA_ADMIN_PASSWORD is not set."
        echo "  export GRAFANA_ADMIN_PASSWORD=... (Grafana UI at http://<import_ip>:3000)"
        missing=1
    fi
    if [[ ! -s tofu/id_ed25519.pub && -z "${TF_VAR_ssh_public_key:-}" ]]; then
        echo "ERROR: no SSH public key found."
        echo "  Expected tofu/id_ed25519.pub (or set TF_VAR_ssh_public_key)."
        missing=1
    fi
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi

# Generate Ansible inventory from tofu output
_generate-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Generating Ansible inventory from tofu output..."
    mkdir -p "$RESULTS_DIR" "$ANSIBLE_DIR/inventory"
    inventory=$(cd "$TOFU_DIR" && tofu output -raw inventory)
    echo "$inventory" > "$INVENTORY"
    echo "Inventory written to $INVENTORY"

# Wait for SSH on all instances (60 x 5s per host)
_wait-for-ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Waiting for SSH on all instances..."
    mapfile -t backend_ips < <(cd "$TOFU_DIR" && tofu output -json backend_ips | jq -r '.[]')
    mariadb_ip=$(cd "$TOFU_DIR" && tofu output -raw mariadb_ip)
    import_ip=$(cd "$TOFU_DIR" && tofu output -raw import_ip)
    hosts=("${backend_ips[@]}" "$mariadb_ip" "$import_ip")
    for host in "${hosts[@]}"; do
        echo -n "  Waiting for $host..."
        for i in $(seq 1 60); do
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$host" true 2>/dev/null; then
                echo " ready"
                break
            fi
            if [[ $i -eq 60 ]]; then
                echo " timeout!"
                exit 1
            fi
            sleep 5
        done
    done

# Graceful MariaDB shutdown (best-effort, never blocks teardown)
_stop-mariadb:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f "$INVENTORY" ]]; then
        echo "No inventory found; skipping graceful MariaDB shutdown"
        exit 0
    fi
    echo "=== Graceful MariaDB shutdown ==="
    ansible-playbook -i "$INVENTORY" "$ANSIBLE_DIR/site.yml" --tags teardown-prep \
        || echo "WARNING: graceful MariaDB shutdown failed; continuing teardown"

# Deploy EntityBase + optional imports + dashboard + benchmark
_deploy-sequence *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    skip_imports=false
    skip_benchmark=false
    set -- {{flags}}
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-imports)   skip_imports=true ;;
            --skip-benchmark) skip_benchmark=true ;;
            *) echo "Unknown option: $1"
               echo "Usage: just up|deploy [--skip-imports] [--skip-benchmark]"
               exit 1 ;;
        esac
        shift
    done
    run_playbook() {
        ansible-playbook -i "$INVENTORY" "$ANSIBLE_DIR/site.yml" --tags "$1"
    }
    echo ""
    echo "=== Deploying EntityBase ==="
    run_playbook "common,entitybase,import"
    if [[ "$skip_imports" == false ]]; then
        echo ""
        echo "=== Loading Wikidata ==="
        run_playbook "wikidata,items"
    fi
    echo ""
    echo "=== Starting Dashboard ==="
    run_playbook "dashboard"
    echo ""
    echo "=== Deploying Observability ==="
    run_playbook "observability"
    if [[ "$skip_benchmark" == false ]]; then
        echo ""
        echo "=== Running benchmarks ==="
        run_playbook "benchmark"
    fi
    echo ""
    echo "=== Done ==="
    lb_ip=$(cd "$TOFU_DIR" && tofu output -raw lb_ip)
    import_ip=$(cd "$TOFU_DIR" && tofu output -raw import_ip)
    echo "Load balancer: http://$lb_ip:8080"
    echo "Dashboard: http://$import_ip"
    echo "Grafana: http://$import_ip:3000 (admin / $GRAFANA_ADMIN_PASSWORD)"
    echo "Results saved in $RESULTS_DIR/"

# --- Infrastructure ---

# Create infrastructure, deploy, and run tests
provision *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    just _require-vars
    echo "=== Provisioning infrastructure ==="
    (cd "$TOFU_DIR" && tofu init && tofu apply -auto-approve)
    just _generate-inventory
    just _wait-for-ssh
    just _deploy-sequence {{flags}}

# Alias: just up == just provision
alias up := provision

# Deploy only (assumes infrastructure exists)
deploy *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    just _require-vars
    just _generate-inventory
    just _wait-for-ssh
    just _deploy-sequence {{flags}}

# Stop MariaDB gracefully, destroy instances + LB + FIPs (keeps volumes)
teardown-instances:
    #!/usr/bin/env bash
    set -euo pipefail
    just _require-vars
    just _stop-mariadb
    echo "=== Tearing down instances, LB and floating IPs (volumes kept) ==="
    (cd "$TOFU_DIR" && tofu destroy -auto-approve \
        -target=openstack_compute_instance_v2.backend \
        -target=openstack_compute_instance_v2.mariadb \
        -target=openstack_compute_instance_v2.import \
        -target=openstack_lb_loadbalancer_v2.entitybase \
        -target=openstack_networking_floatingip_v2.backend \
        -target=openstack_networking_floatingip_v2.mariadb \
        -target=openstack_networking_floatingip_v2.import \
        -target=openstack_networking_floatingip_v2.lb)
    echo "Volumes retained for inspection:"
    (cd "$TOFU_DIR" && tofu state list | grep openstack_blockstorage_volume_v3) || echo "  (none)"
    echo "Instances destroyed. Data volumes are still attached to the project."

# Tear down the data volumes (step 2, after teardown-instances)
teardown-volumes:
    #!/usr/bin/env bash
    set -euo pipefail
    just _require-vars
    echo "=== Tearing down data volumes ==="
    (cd "$TOFU_DIR" && tofu destroy -auto-approve \
        -target=openstack_blockstorage_volume_v3.mariadb_data \
        -target=openstack_blockstorage_volume_v3.import_data)
    echo "Volumes destroyed."

# Stop MariaDB gracefully (if reachable), tear down everything
destroy:
    #!/usr/bin/env bash
    set -euo pipefail
    just _require-vars
    just _stop-mariadb
    echo "=== Destroying infrastructure ==="
    (cd "$TOFU_DIR" && tofu destroy -auto-approve)
    echo "Infrastructure destroyed."

# Show infrastructure status
status:
    #!/usr/bin/env bash
    set -euo pipefail
    just _require-vars
    (cd "$TOFU_DIR" && tofu output)

# Initialize OpenTofu
init:
    cd tofu && tofu init

# Plan infrastructure changes
plan:
    cd tofu && tofu plan

# Apply infrastructure changes
apply:
    cd tofu && tofu apply

# Generate Ansible inventory from tofu output
inventory: _generate-inventory

# --- SSH ---

# SSH into import instance
ssh-import:
    ssh ubuntu@$(cd tofu && tofu output -raw import_ip)

# SSH into mariadb instance
ssh-mariadb:
    ssh ubuntu@$(cd tofu && tofu output -raw mariadb_ip)

# SSH into a backend instance
ssh-backend n="1":
    ssh ubuntu@$(cd tofu && tofu output -json backend_ips | jq -r '.[]' | sed -n '{{n}}p')

# --- Ansible ---

# Run ansible playbook with specific tag
playbook tag:
    ansible-playbook -i {{INVENTORY}} {{ANSIBLE_DIR}}/site.yml --tags {{tag}}

# Run benchmarks
bench:
    ansible-playbook -i {{INVENTORY}} {{ANSIBLE_DIR}}/site.yml --tags benchmark

# Start dashboard
dashboard:
    ansible-playbook -i {{INVENTORY}} {{ANSIBLE_DIR}}/site.yml --tags dashboard

# Deploy observability stack (Prometheus/Loki/Grafana on import, exporters on all)
observability: _require-vars
    ansible-playbook -i {{INVENTORY}} {{ANSIBLE_DIR}}/site.yml --tags observability

# Tail logs on all backends
logs:
    ansible all -i {{INVENTORY}} -m shell -a "journalctl -u entitybase -f --no-pager"

# --- Wikidata ---

# Download lexeme dump (~600MB)
download-lexemes:
    ansible-playbook -i {{INVENTORY}} {{ANSIBLE_DIR}}/site.yml --tags download-lexemes

# Import lexemes into EntityBase
import-lexemes:
    ansible-playbook -i {{INVENTORY}} {{ANSIBLE_DIR}}/site.yml --tags import-lexemes

# Download items dump (~150GB)
download-items:
    ansible-playbook -i {{INVENTORY}} {{ANSIBLE_DIR}}/site.yml --tags download-items

# Import items into EntityBase
import-items:
    ansible-playbook -i {{INVENTORY}} {{ANSIBLE_DIR}}/site.yml --tags import-items

# Download and import lexemes
lexemes: download-lexemes import-lexemes

# Download and import items (WARNING: ~150GB download, takes hours)
items: download-items import-items

# --- Utilities ---

# Format tofu files
fmt:
    cd tofu && tofu fmt

# Validate terraform config
validate:
    cd tofu && tofu validate

# Show all tofu outputs
outputs:
    cd tofu && tofu output
