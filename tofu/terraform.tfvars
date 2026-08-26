# Reads credentials from clouds.yaml (see README.md for setup)

region         = "UK1"
image          = "Ubuntu 24.04"
ssh_key_name   = "entitybase-test"
backend_count  = 4
backend_flavor = "c3-4"
mariadb_flavor = "b3-16"

mariadb_storage_size = 1024
mariadb_storage_type = "classic"

import_flavor = "c3-4"

import_storage_size = 200
import_storage_type = "classic"

entitybase_repo   = "https://github.com/Entitybasedev/entitybase-orchestrator.git"
entitybase_branch = "main"

external_network_name = "Ext-Net"
