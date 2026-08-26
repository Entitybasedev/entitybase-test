# entitybase-test

Automated infrastructure for benchmarking [EntityBase](https://github.com/Entitybasedev/entitybase-orchestrator) with Wikidata on OVH Public Cloud.

## Architecture

```mermaid
graph TB
    subgraph "OVH Public Cloud (UK1)"
        subgraph "Private Network 10.0.0.0/24"
            B1["backend-1\nc3-4"]
            B2["backend-2\nc3-4"]
            B3["backend-3\nc3-4"]
            B4["backend-4\nc3-4"]
            DB["mariadb\nb3-16\n16GB RAM"]
        end

        LB["OVH Load Balancer\nOctavia :8080"]
        FIP["Floating IP"]
        IMP["import\nc3-4"]
    end

    FIP --> LB
    LB -->|round-robin| B1
    LB -->|round-robin| B2
    LB -->|round-robin| B3
    LB -->|round-robin| B4
    B1 -->|:3306| DB
    B2 -->|:3306| DB
    B3 -->|:3306| DB
    B4 -->|:3306| DB
    IMP -->|"entitybase load"| FIP
```

## Repository Structure

```
entitybase-test/
├── tofu/           # OpenTofu IaC for OVH infrastructure
├── ansible/        # Configuration and deployment playbooks
├── run-test.sh     # End-to-end test orchestration
└── clouds.yaml     # OVH credentials (not committed)
```

## What It Does

`run-test.sh` automates:

1. Create OVH infrastructure via OpenTofu (4 backends + import + MariaDB + LB)
2. Wait for SSH connectivity
3. Install prerequisites on all instances
4. Install EntityBase on backends and import host
5. Configure MariaDB 11.4 (16GB tuned)
6. Download and load the Wikidata lexeme dump (import host only)
7. Run measurements and collect results
8. Optionally destroy the infrastructure

## Instance Roles

| Instance | Flavor | Role |
|----------|--------|------|
| backend-1..4 | c3-4 | EntityBase API server, behind LB |
| import | c3-4 | Downloads dump + runs `entitybase load` |
| mariadb | b3-16 | MariaDB 11.4 (16GB tuned) |

## Requirements

- [OpenTofu](https://opentofu.org/) >= 1.5
- [Ansible](https://www.ansible.com/)
- [just](https://github.com/casey/just) (command runner)
- [jq](https://stedolan.github.io/jq/)
- OVH Public Cloud account
- SSH key registered in OVH

## Setup

1. Place your `clouds.yaml` in `~/.config/openstack/` or the project root:

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://auth.uk1.cloud.ovh.net/v3
      application_credential_id: "YOUR_ID"
      application_credential_secret: "YOUR_SECRET"
    region_name: UK1
```

2. Ensure your SSH public key exists at `tofu/id_ed25519.pub`

3. Edit `tofu/terraform.tfvars` for your configuration:

```hcl
region          = "UK1"
image           = "Ubuntu 24.04"
ssh_key_name    = "entitybase-test"
backend_count   = 4
backend_flavor  = "c3-4"
import_flavor   = "c3-4"
mariadb_flavor  = "b3-16"
```

## Usage

```bash
# Provision infrastructure
just provision

# Deploy EntityBase + load wikidata
just deploy

# Load wikidata lexemes only
just lexemes

# Load wikidata items only (~150GB, takes hours)
just items

# Check infrastructure status
just status

# SSH into instances
just ssh-import
just ssh-mariadb
just ssh-backend 1

# Tear down everything
just destroy
```

## License

GNU General Public License v3.0 or later. See [LICENSE](LICENSE) for details.
