terraform {
  required_version = ">= 1.5.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

provider "openstack" {
  auth_url                      = "https://auth.uk1.cloud.ovh.net/v3"
  region                        = var.region
  application_credential_id     = var.ovh_application_credential_id
  application_credential_secret = var.ovh_application_credential_secret
}

# --- SSH Key ---

resource "openstack_compute_keypair_v2" "ssh" {
  name       = var.ssh_key_name
  public_key = file("${path.module}/id_rsa.pub")
}

# --- Security Group ---

resource "openstack_networking_secgroup_v2" "entitybase" {
  name        = "entitybase-test"
  description = "Security group for EntityBase test infrastructure"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_in" {
  security_group_id = openstack_networking_secgroup_v2.entitybase.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "lb_http_in" {
  security_group_id = openstack_networking_secgroup_v2.entitybase.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "mariadb_in" {
  security_group_id = openstack_networking_secgroup_v2.entitybase.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3306
  port_range_max    = 3306
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "entitybase_api_in" {
  security_group_id = openstack_networking_secgroup_v2.entitybase.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8000
  port_range_max    = 8000
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "icmp_in" {
  security_group_id = openstack_networking_secgroup_v2.entitybase.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
}

# --- Network (private for LB + backends) ---

resource "openstack_networking_network_v2" "entitybase" {
  name = "entitybase-net"
}

resource "openstack_networking_subnet_v2" "entitybase" {
  name       = "entitybase-subnet"
  network_id = openstack_networking_network_v2.entitybase.id
  cidr       = "10.0.0.0/24"
  ip_version = 4
}

resource "openstack_networking_router_v2" "entitybase" {
  name                = "entitybase-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "entitybase" {
  router_id = openstack_networking_router_v2.entitybase.id
  subnet_id = openstack_networking_subnet_v2.entitybase.id
}

data "openstack_networking_network_v2" "external" {
  name = "Ext-Net"
}

# --- Backend Instances ---

resource "openstack_compute_instance_v2" "backend" {
  count       = var.backend_count
  name        = "entitybase-backend-${count.index + 1}"
  flavor_name = var.backend_flavor
  image_name  = var.image
  key_pair    = openstack_compute_keypair_v2.ssh.name

  network {
    uuid = openstack_networking_network_v2.entitybase.id
  }

  security_groups = [openstack_networking_secgroup_v2.entitybase.name]

  metadata = {
    role = "backend"
  }
}

# --- MariaDB Instance ---

resource "openstack_compute_instance_v2" "mariadb" {
  name        = "entitybase-mariadb"
  flavor_name = var.mariadb_flavor
  image_name  = var.image
  key_pair    = openstack_compute_keypair_v2.ssh.name

  network {
    uuid = openstack_networking_network_v2.entitybase.id
  }

  security_groups = [openstack_networking_secgroup_v2.entitybase.name]

  metadata = {
    role = "mariadb"
  }
}

# --- OVH Load Balancer (Octavia) ---

resource "openstack_lb_loadbalancer_v2" "entitybase" {
  name              = "entitybase-lb"
  vip_subnet_id     = openstack_networking_subnet_v2.entitybase.id
  security_group_ids = [openstack_networking_secgroup_v2.entitybase.id]
}

resource "openstack_lb_listener_v2" "http" {
  name            = "entitybase-http"
  protocol        = "HTTP"
  protocol_port   = 8080
  loadbalancer_id = openstack_lb_loadbalancer_v2.entitybase.id
}

resource "openstack_lb_pool_v2" "backend" {
  name        = "entitybase-backend-pool"
  protocol    = "HTTP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.http.id
}

resource "openstack_lb_member_v2" "backend" {
  count         = var.backend_count
  pool_id       = openstack_lb_pool_v2.backend.id
  address       = openstack_compute_instance_v2.backend[count.index].access_ip_v4
  protocol_port = 8000
  subnet_id     = openstack_networking_subnet_v2.entitybase.id
}

resource "openstack_lb_monitor_v2" "backend" {
  name        = "entitybase-backend-monitor"
  type        = "HTTP"
  pool_id     = openstack_lb_pool_v2.backend.id
  http_method = "GET"
  url_path    = "/"
  delay       = 10
  timeout     = 5
  max_retries = 3
}

# --- Floating IP for LB ---

resource "openstack_networking_floatingip_v2" "lb" {
  pool = "Ext-Net"
}

resource "openstack_networking_floatingip_associate_v2" "lb" {
  floating_ip = openstack_networking_floatingip_v2.lb.address
  port_id     = openstack_lb_loadbalancer_v2.entitybase.vip_port_id
}
