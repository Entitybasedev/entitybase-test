output "lb_ip" {
  description = "Public IP of the load balancer"
  value       = openstack_networking_floatingip_v2.lb.address
}

output "mariadb_ip" {
  description = "Private IP of MariaDB instance"
  value       = openstack_compute_instance_v2.mariadb.access_ip_v4
}

output "backend_ips" {
  description = "Private IPs of backend instances"
  value       = [for i in openstack_compute_instance_v2.backend : i.access_ip_v4]
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
${openstack_compute_instance_v2.mariadb.name} ansible_host=${openstack_compute_instance_v2.mariadb.access_ip_v4}

[backend]
%{for i, inst in openstack_compute_instance_v2.backend~}
${inst.name} ansible_host=${inst.access_ip_v4}
%{endfor~}

[entitybase:children]
backend

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
entitybase_mariadb_host=${openstack_compute_instance_v2.mariadb.access_ip_v4}
entitybase_lb_host=${openstack_networking_floatingip_v2.lb.address}
EOT
}
