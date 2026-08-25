# entitybase-test - just commands

# List available commands
default:
    @just --list

# Full run: provision + deploy + benchmark
up:
    ./run-test.sh up

# Deploy only (infrastructure already exists)
deploy:
    ./run-test.sh deploy

# Destroy all infrastructure
destroy:
    ./run-test.sh destroy

# Show infrastructure status
status:
    ./run-test.sh status

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
inventory:
    ./run-test.sh inventory

# Run ansible playbook with specific tag
playbook tag:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags {{tag}}

# SSH into a specific instance
ssh host:
    ssh ubuntu@$(cd tofu && tofu output -json {{host}}_ips 2>/dev/null | jq -r '.[0] // empty' || tofu output -raw {{host}}_ip)

# Tail logs on all backends
logs:
    ansible all -i ansible/inventory/hosts.ini -m shell -a "journalctl -u entitybase -f --no-pager"

# Run benchmarks only
bench:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags benchmark

# Download wikidata dump only
wikidata:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags wikidata

# fmt tofu files
fmt:
    cd tofu && tofu fmt

# Validate terraform config
validate:
    cd tofu && tofu validate

# Show all tofu outputs
outputs:
    cd tofu && tofu output
