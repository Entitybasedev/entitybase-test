#!/bin/bash
cd "$(dirname "$0")/.."
set -Eeuo pipefail

echo "🔧 MariaDB Entitybase Setup"
echo ""

echo "📦 Installing MariaDB 11.4..."
sudo apt-get update -qq
sudo apt-get install -y -qq mariadb-server mariadb-client

echo "🔄 Starting MariaDB..."
sudo systemctl start mariadb
sudo systemctl enable mariadb

echo "📝 Configuring MariaDB for 16GB memory / 25 connections..."
sudo tee /etc/mysql/mariadb.conf.d/99-entitybase.cnf > /dev/null <<'EOF'
[mysqld]
# === InnoDB Performance (16GB RAM) ===
# Buffer pool: 12GB (~75% of 16GB)
innodb_buffer_pool_size = 12G
innodb_buffer_pool_instances = 4

# Log buffer and files
innodb_log_buffer_size = 64M
innodb_log_file_size = 2G
innodb_log_files_in_group = 2

# I/O settings
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_flush_method = O_DIRECT
innodb_flush_log_at_trx_commit = 2
innodb_doublewrite = OFF

# Memory settings
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup = 1

# === Connections ===
max_connections = 25
thread_cache_size = 25
wait_timeout = 600
interactive_timeout = 600

# === Thread Settings ===
thread_handling = pool-of-threads
thread_pool_size = 4
thread_pool_stall_limit = 300

# === Query Cache (disabled for InnoDB) ===
query_cache_type = 0
query_cache_size = 0

# === Temp Tables ===
tmp_table_size = 256M
max_heap_table_size = 256M

# === Join Buffer ===
join_buffer_size = 4M
sort_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 4M

# === Table Cache ===
table_open_cache = 4000
table_open_cache_instances = 4

# === Binary Logging (optional) ===
# binlog_format = ROW
# sync_binlog = 0

# === Networking ===
bind_address = 0.0.0.0
port = 3306
socket = /run/mysqld/mysqld.sock

# === Character Set ===
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# === Logging ===
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
log_error = /var/log/mysql/error.log
EOF

echo "🔄 Restarting MariaDB..."
sudo systemctl restart mariadb

echo "👤 Creating entitybase database and user..."
sudo mariadb -e "CREATE DATABASE IF NOT EXISTS entitybase CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mariadb -e "CREATE USER IF NOT EXISTS 'entitybase'@'localhost' IDENTIFIED BY '';"
sudo mariadb -e "GRANT ALL PRIVILEGES ON entitybase.* TO 'entitybase'@'localhost';"
sudo mariadb -e "FLUSH PRIVILEGES;"

echo ""
echo "✅ MariaDB configured successfully"
echo "   Database: entitybase"
echo "   User: entitybase@localhost"
echo "   Max connections: 25"
echo "   Buffer pool: 12GB"
echo "   Port: 3306"
