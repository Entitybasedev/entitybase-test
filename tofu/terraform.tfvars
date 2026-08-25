# OVH Application Credentials (set via environment variables or fill in below)
# export TF_VAR_ovh_application_credential_id="..."
# export TF_VAR_ovh_application_credential_secret="..."

region          = "UK1"
image           = "Ubuntu 24.04"
ssh_key_name    = "entitybase-test"
backend_count   = 4
backend_flavor  = "c3-4"
mariadb_flavor  = "b3-16"

entitybase_repo   = "https://github.com/Entitybasedev/entitybase-orchestrator.git"
entitybase_branch = "main"
