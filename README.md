# entitybase-test

Automated infrastructure for benchmarking [EntityBase](https://github.com/Entitybasedev/entitybase-orchestrator) with Wikidata on OVH Public Cloud.

## Architecture

```
                OVH Public Cloud
                      │
                OpenTofu/Terraform
                      │
      ┌───────────────┼───────────────┐
      ▼               ▼               ▼
  instance-1      instance-2      instance-N
      │               │               │
      └───────────────┼───────────────┘
                      │ SSH
                   Ansible
                      │
             EntityBase + Wikidata
```

## Repository Structure

```
entitybase-test/
├── tofu/          # OpenTofu IaC for OVH instances
├── ansible/       # Configuration and deployment playbooks
└── run-test.sh    # End-to-end test orchestration
```

## What It Does

`run-test.sh` automates:

1. Create N OVH instances via OpenTofu
2. Wait for SSH connectivity
3. Install prerequisites
4. Install and configure EntityBase
5. Download and load the Wikidata lexeme dump
6. Run measurements and collect results
7. Optionally destroy the instances

## Requirements

- [OpenTofu](https://opentofu.org/) (or Terraform)
- [Ansible](https://www.ansible.com/)
- OVH Public Cloud account and API credentials
- SSH key registered in OVH

## Configuration

Edit `tofu/terraform.tfvars` to set:

- `instance_count` - number of instances
- `flavor` - OVH instance size
- `image` - base OS image
- `region` - OVH region (e.g. GRA, SBG)
- `ssh_key` - name of registered SSH key

## License

GNU General Public License v3.0 or later. See [LICENSE](LICENSE) for details.
