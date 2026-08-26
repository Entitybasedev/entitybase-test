#!/bin/bash
cd "$(dirname "$0")"
set -euo pipefail

TOFU_DIR="tofu"
ANSIBLE_DIR="ansible"
RESULTS_DIR="results"

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  up        Create infrastructure, deploy, and run tests"
    echo "  deploy    Deploy only (assumes infrastructure exists)"
    echo "  destroy   Tear down all infrastructure"
    echo "  status    Show current infrastructure status"
    echo ""
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
    mkdir -p "$RESULTS_DIR"

    local inventory
    inventory=$(cd "$TOFU_DIR" && tofu output -raw inventory)

    echo "$inventory" > "$ANSIBLE_DIR/inventory/hosts.ini"
    echo "Inventory written to $ANSIBLE_DIR/inventory/hosts.ini"
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
    ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" --tags "common,entitybase,import"

    echo ""
    echo "=== Loading Wikidata ==="
    ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" --tags "wikidata"

    echo ""
    echo "=== Loading Wikidata Items ==="
    ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" --tags "items"

    echo ""
    echo "=== Starting Dashboard ==="
    ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" --tags "dashboard"

    echo ""
    echo "=== Running benchmarks ==="
    ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" --tags "benchmark"

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
    ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" --tags "common,entitybase,import,wikidata,dashboard"
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

case "${1:-}" in
    up)      cmd_up ;;
    deploy)  cmd_deploy ;;
    destroy) cmd_destroy ;;
    status)  cmd_status ;;
    *)       usage ;;
esac
