output "lb_ip" {
  description = "Public IP of the load balancer"
  value       = openstack_networking_floatingip_v2.lb.address
}

output "mariadb_ip" {
  description = "Public IP of MariaDB instance"
  value       = openstack_networking_floatingip_v2.mariadb.address
}

output "backend_ips" {
  description = "Public IPs of backend instances"
  value       = [for i in openstack_networking_floatingip_v2.backend : i.address]
}

output "import_ip" {
  description = "Public IP of the import instance"
  value       = openstack_networking_floatingip_v2.import.address
}

output "mariadb_volume_device" {
  description = "Device path of the attached MariaDB data volume"
  value       = openstack_compute_volume_attach_v2.mariadb_data.device
}

output "ssh_user" {
  description = "SSH user for all instances"
  value       = "ubuntu"
}

output "inventory" {
  description = "Ansible inventory in INI format"
  sensitive   = true
  value       = <<-EOT
[mariadb]
${openstack_compute_instance_v2.mariadb.name} ansible_host=${openstack_networking_floatingip_v2.mariadb.address}

[backend]
%{for i, inst in openstack_compute_instance_v2.backend~}
${inst.name} ansible_host=${openstack_networking_floatingip_v2.backend[i].address}
%{endfor~}

[import]
${openstack_compute_instance_v2.import.name} ansible_host=${openstack_networking_floatingip_v2.import.address}

[entitybase:children]
backend

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
entitybase_mariadb_host=${openstack_networking_port_v2.mariadb.all_fixed_ips[0]}
entitybase_lb_host=${openstack_networking_floatingip_v2.lb.address}
EOT
}
