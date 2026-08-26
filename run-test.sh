#!/bin/bash
cd "$(dirname "$0")"
set -euo pipefail

TOFU_DIR="tofu"
ANSIBLE_DIR="ansible"
RESULTS_DIR="results"
INVENTORY="$ANSIBLE_DIR/inventory/hosts.ini"

# Default flags
SKIP_IMPORTS=false
SKIP_BENCHMARK=false

usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  up        Create infrastructure, deploy, and run tests"
    echo "  deploy    Deploy only (assumes infrastructure exists)"
    echo "  destroy   Tear down all infrastructure"
    echo "  status    Show current infrastructure status"
    echo ""
    echo "Options (for 'up' and 'deploy'):"
    echo "  --skip-imports     Skip Wikidata download and import"
    echo "  --skip-benchmark   Skip benchmark execution"
    echo ""
}

require_vars() {
    local missing=0
    for cmd in tofu ansible-playbook jq; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "ERROR: Required command '$cmd' not found in PATH."
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
    check_clouds_yaml
}

check_clouds_yaml() {
    if [[ ! -f "$HOME/.config/openstack/clouds.yaml" ]] && \
       [[ ! -f "./clouds.yaml" ]]; then
        echo "ERROR: clouds.yaml not found."
        echo "Expected at ~/.config/openstack/clouds.yaml or ./clouds.yaml"
        exit 1
    fi
}

generate_inventory() {
    echo "Generating Ansible inventory from tofu output..."
    mkdir -p "$RESULTS_DIR" "$ANSIBLE_DIR/inventory"

    local inventory
    inventory=$(cd "$TOFU_DIR" && tofu output -raw inventory)

    echo "$inventory" > "$INVENTORY"
    echo "Inventory written to $INVENTORY"
}

wait_for_ssh() {
    echo "Waiting for SSH on all instances..."
    local hosts
    hosts=$(cd "$TOFU_DIR" && tofu output -json backend_ips | jq -r '.[]')
    hosts="$hosts
$(cd "$TOFU_DIR" && tofu output -raw mariadb_ip)
$(cd "$TOFU_DIR" && tofu output -raw import_ip)"

    for host in $hosts; do
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
}

run_playbook() {
    local tags="$1"
    ansible-playbook -i "$INVENTORY" "$ANSIBLE_DIR/site.yml" --tags "$tags"
}

cmd_up() {
    require_vars

    echo "=== Provisioning infrastructure ==="
    cd "$TOFU_DIR"
    tofu init
    tofu apply -auto-approve
    cd ..

    generate_inventory
    wait_for_ssh

    echo ""
    echo "=== Deploying EntityBase ==="
    run_playbook "common,entitybase,import"

    if [[ "$SKIP_IMPORTS" == false ]]; then
        echo ""
        echo "=== Loading Wikidata Lexemes ==="
        run_playbook "wikidata"

        echo ""
        echo "=== Loading Wikidata Items ==="
        run_playbook "items"
    fi

    echo ""
    echo "=== Starting Dashboard ==="
    run_playbook "dashboard"

    if [[ "$SKIP_BENCHMARK" == false ]]; then
        echo ""
        echo "=== Running benchmarks ==="
        run_playbook "benchmark"
    fi

    echo ""
    echo "=== Done ==="
    local lb_ip import_ip
    lb_ip=$(cd "$TOFU_DIR" && tofu output -raw lb_ip)
    import_ip=$(cd "$TOFU_DIR" && tofu output -raw import_ip)
    echo "Load balancer: http://$lb_ip:8080"
    echo "Dashboard: http://$import_ip"
    echo "Results saved in $RESULTS_DIR/"
}

cmd_deploy() {
    require_vars
    generate_inventory
    wait_for_ssh

    echo "=== Deploying ==="
    run_playbook "common,entitybase,import"

    if [[ "$SKIP_IMPORTS" == false ]]; then
        run_playbook "wikidata,items"
    fi

    run_playbook "dashboard"
}

cmd_destroy() {
    require_vars
    echo "=== Destroying infrastructure ==="
    cd "$TOFU_DIR"
    tofu destroy -auto-approve
    cd ..
    echo "Infrastructure destroyed."
}

cmd_status() {
    require_vars
    cd "$TOFU_DIR"
    tofu output
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-imports)
            SKIP_IMPORTS=true
            shift
            ;;
        --skip-benchmark)
            SKIP_BENCHMARK=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

case "${1:-}" in
    up)      cmd_up ;;
    deploy)  cmd_deploy ;;
    destroy) cmd_destroy ;;
    status)  cmd_status ;;
    *)       usage ;;
esac
