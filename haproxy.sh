#!/bin/bash
cd "$(dirname "$0")/.."
set -Eeuo pipefail

echo "🔧 HAProxy Backend Setup"
echo ""

# Prompt for backend IP addresses
read -rp "Enter backend IP addresses (comma-separated): " ips_input

# Validate input
if [[ -z "$ips_input" ]]; then
    echo "❌ Error: No IP addresses provided"
    exit 1
fi

# Convert comma-separated to space-separated and build backend entries
IFS=',' read -ra ips_array <<< "$ips_input"

backend_entries=""
index=1
for ip in "${ips_array[@]}"; do
    ip=$(echo "$ip" | xargs)  # trim whitespace
    if [[ -z "$ip" ]]; then
        continue
    fi
    backend_entries+="    server backend${index} ${ip}:8000 check\n"
    ((index++))
done

if [[ -z "$backend_entries" ]]; then
    echo "❌ Error: No valid IP addresses found"
    exit 1
fi

echo ""
echo "📋 Backend servers to configure:"
for ip in "${ips_array[@]}"; do
    ip=$(echo "$ip" | xargs)
    [[ -n "$ip" ]] && echo "   - ${ip}:8000"
done

echo ""
read -rp "Proceed with HAProxy installation? (y/N) " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Aborted"
    exit 0
fi

echo ""
echo "📦 Installing HAProxy..."
sudo apt-get update -qq
sudo apt-get install -y -qq haproxy

echo "📝 Generating HAProxy config..."
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend http_front
    bind *:8080
    default_backend http_back

backend http_back
    balance roundrobin
$(echo -e "$backend_entries")
EOF

echo "🔄 Restarting HAProxy..."
sudo systemctl restart haproxy
sudo systemctl enable haproxy

echo ""
echo "✅ HAProxy installed and running on port 8080"
echo "   Backends: $(echo "${ips_input}" | sed 's/,/, /g')"
