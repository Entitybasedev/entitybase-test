# entitybase-test - just commands

set shell := ["bash", "-cu"]

# List available commands
default:
    @just --list

# --- Infrastructure ---

# Provision infrastructure (tofu apply + generate inventory)
provision:
    ./run-test.sh up

# Deploy only (assumes infrastructure exists)
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
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags {{tag}}

# Run benchmarks
bench:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags benchmark

# Start dashboard
dashboard:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags dashboard

# Tail logs on all backends
logs:
    ansible all -i ansible/inventory/hosts.ini -m shell -a "journalctl -u entitybase -f --no-pager"

# --- Wikidata ---

# Download lexeme dump (~600MB)
download-lexemes:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags download-lexemes

# Import lexemes into EntityBase
import-lexemes:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags import-lexemes

# Download items dump (~150GB)
download-items:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags download-items

# Import items into EntityBase
import-items:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags import-items

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
