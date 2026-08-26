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

variable "mariadb_storage_size" {
  description = "Size of MariaDB block storage volume in GB"
  type        = number
  default     = 1024
}

variable "mariadb_storage_type" {
  description = "OVH block storage type (classic, high-speed, high-speed-gen2)"
  type        = string
  default     = "classic"
}

variable "import_flavor" {
  description = "Flavor for import instance (c3-4)"
  type        = string
  default     = "c3-4"
}

variable "import_storage_size" {
  description = "Size of import block storage volume in GB"
  type        = number
  default     = 200
}

variable "import_storage_type" {
  description = "OVH block storage type for import (classic, high-speed, high-speed-gen2)"
  type        = string
  default     = "classic"
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

variable "external_network_name" {
  description = "Name of the external network for floating IPs"
  type        = string
  default     = "Ext-Net"
}
