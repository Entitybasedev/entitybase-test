# Observability Plan: Self-Hosted Infra-Level Monitoring

## Goal

Infra-level observability for the entitybase-test OVH Public Cloud infrastructure,
self-hosted on the import host, brought up with the infra via `just provision` /
`just deploy`. No alerting. Python-level instrumentation (via the
`entitybase-observability` lib) is out of scope.

## Stack

| Component        | Location    | Purpose                                          |
|------------------|-------------|--------------------------------------------------|
| Prometheus       | import host | Metrics scrape + storage                         |
| Loki             | import host | Log aggregation                                  |
| Grafana          | import host | Dashboards (port 3000)                           |
| node_exporter    | all hosts   | CPU / RAM / disk / network                       |
| mysqld_exporter  | mariadb     | MariaDB metrics (read-only metrics user)         |
| Grafana Alloy    | all hosts   | Ship journalctl (systemd units) to Loki (promtail successor) |

All traffic stays on the private network (10.0.0.0/24) except the Grafana UI on
port 3000. State is intentionally ephemeral — destroyed with `just destroy`; the
durable record remains the `results/` benchmark JSONs.

## Changes

### 1. OpenTofu (`tofu/`)

- Add security group rule for Grafana on the import host (port **3000**),
  mirroring the existing `dashboard_in` rule (`tofu/main.tf:88-94`).
- No other IaC changes; `import_ip` output already exists.

### 2. New Ansible role `roles/observability`

Follow existing role conventions (systemd units + handlers for daemon-reload /
restart, as in `roles/dashboard`).

**All hosts:**

- Install `node_exporter` and `promtail`.
- Template promtail config shipping journal logs for units: `entitybase`,
  `mariadb`, `entitybase-dashboard`, plus import/benchmark logs, to Loki on the
  import host.

**Import host (server components):**

- **Prometheus**: scrape targets generated from Ansible inventory —
  `node_exporter:9100` (all hosts), `mysqld_exporter:9104` (mariadb), and a
  blackbox HTTP probe of the LB `:8080` health endpoint (backend up/down).
- **Loki**: log aggregation, no alerting rules.
- **Grafana**: port 3000; provisioned datasources (Prometheus, Loki) and a
  minimal benchmark dashboard via provisioning YAML in `templates/`:
  - CPU / RAM / disk on mariadb + backends
  - MariaDB connections / InnoDB
  - Import throughput
  - LB probe up/down

**MariaDB host:**

- Install `mysqld_exporter`, create read-only metrics DB user.

### 3. `ansible/site.yml`

- New play: `hosts: all` → `observability` role, tag `[observability]`,
  included in the default deploy sequence after `dashboard`.

### 4. `justfile`

- `just observability` — run playbook with `--tags observability` (pattern of
  existing `just dashboard`).
- Extend `_deploy-sequence` to run the observability tag after dashboard.
- Update final echo to print Grafana URL: `http://$import_ip:3000`.
- `just destroy` requires no change (packages/systemd units only, no state).

### 5. Docs

- README: architecture note + Grafana URL in usage.

## Out of Scope

- Alerting / Alertmanager
- Python instrumentation via `entitybase-observability` lib
- External / managed endpoints; metrics history survives teardown
