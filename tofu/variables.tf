variable "region" {
  description = "OVH Public Cloud region"
  type        = string
  default     = "UK1"
}

variable "image" {
  description = "Base OS image"
  type        = string
  default     = "Ubuntu 24.04"
}

variable "ssh_key_name" {
  description = "Name of the SSH key in OVH"
  type        = string
  default     = "entitybase-test"
}

variable "backend_count" {
  description = "Number of EntityBase backend instances"
  type        = number
  default     = 4
}

variable "backend_flavor" {
  description = "Flavor for backend instances (c3-4)"
  type        = string
  default     = "c3-4"
}

variable "mariadb_flavor" {
  description = "Flavor for MariaDB instance (b3-16, 16GB RAM)"
  type        = string
  default     = "b3-16"
}

variable "entitybase_repo" {
  description = "Git repository for EntityBase"
  type        = string
  default     = "https://github.com/Entitybasedev/entitybase-orchestrator.git"
}

variable "entitybase_branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
}
