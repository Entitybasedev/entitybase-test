# Plan: EntityBase Benchmark Implementation

## Context

The `entitybase-test` infrastructure has a benchmark Ansible role that invokes
`python3 -m entitybase benchmark`, but no such CLI exists. We need to implement
the benchmark tool that measures EntityBase backend performance with real Wikidata
data.

## Design Decisions

### Where to put the code

**Recommended: New `entitybase-benchmark` package in `libs/`**

Rationale:
- Keeps benchmark logic separate from backend internals (clean separation)
- Avoids adding test/tooling dependencies to the backend package
- Follows the existing `libs/` convention (entitybase-backend, entitybase-import)
- Can be installed independently on benchmark hosts

Alternative considered: Adding to `entitybase-backend` — rejected because it would
couple test harness with production code and add unnecessary dependencies.

### CLI framework

**Use `argparse`** — consistent with the rest of the codebase (no click/typer used).

### What to measure

The benchmark should test the core operations EntityBase performs:

1. **Entity resolution** — the primary workload (resolving entity graphs via MariaDB)
2. **Bulk insert throughput** — how fast entities can be written
3. **Concurrent read performance** — multiple parallel resolution requests
4. **Query latency distribution** — p50, p95, p99 latencies

### Benchmark methodology

- Warmup phase (discard first N requests to fill connection pools, JIT, etc.)
- Fixed-duration measurement window (e.g., 60 seconds per test)
- Multiple iterations for statistical significance
- Report throughput (ops/sec) and latency percentiles
- JSON output for machine consumption (consumed by Ansible fetch)

## Implementation Plan

### 1. Create `libs/entitybase-benchmark/` package structure

```
libs/entitybase-benchmark/
├── pyproject.toml
├── src/
│   └── entitybase_benchmark/
│       ├── __init__.py
│       ├── __main__.py          # CLI entrypoint
│       ├── cli.py               # argparse CLI
│       ├── metrics.py           # MetricsCollector, latency tracking
│       ├── scenarios/
│       │   ├── __init__.py
│       │   ├── insert.py        # Bulk insert benchmark
│       │   ├── resolve.py       # Entity resolution benchmark
│       │   └── concurrent.py    # Parallel read benchmark
│       └── report.py            # JSON report generation
```

### 2. CLI interface

```
python -m entitybase_benchmark \
    --db-url "mysql://entitybase@10.0.0.1/entitybase" \
    --output /opt/entitybase/results/benchmark.json \
    --duration 60 \
    --warmup 10 \
    --backends http://10.0.0.2:8000,http://10.0.0.3:8000
```

Arguments:
- `--db-url` (required): MariaDB connection string
- `--output` (required): Path to JSON output file
- `--duration` (default: 60): Measurement window in seconds per scenario
- `--warmup` (default: 10): Warmup duration in seconds (discarded from results)
- `--backends` (optional): Comma-separated backend URLs for resolution tests
- `--scenarios` (optional): Comma-separated list of scenarios to run (default: all)

### 3. Metrics collection

Each scenario reports:
```json
{
  "scenario": "entity_resolve",
  "duration_seconds": 60,
  "total_operations": 12345,
  "throughput_ops_sec": 205.7,
  "latency_ms": {
    "min": 1.2,
    "max": 89.3,
    "mean": 4.8,
    "p50": 3.9,
    "p95": 12.1,
    "p99": 45.6
  },
  "errors": 0
}
```

### 4. Scenarios

**a) Insert benchmark** (`scenarios/insert.py`)
- Load sample entities from a fixture file (small set, ~1000 entities)
- Repeatedly insert via the EntityBase API
- Measure write throughput and latency

**b) Resolution benchmark** (`scenarios/resolve.py`)
- Pre-load a set of entity IDs
- Continuously resolve entity graphs through the backend
- Measure read throughput and latency

**c) Concurrent benchmark** (`scenarios/concurrent.py`)
- Spawn N worker threads (configurable, default: number of backends x 2)
- Each worker performs resolution requests
- Measure aggregate throughput and per-thread latency

### 5. Sample data

Create `libs/entitybase-benchmark/fixtures/` with:
- `sample_entities.json` — ~1000 representative entities for insert tests
- `entity_ids.json` — list of known entity IDs for resolution tests

These can be extracted from the Wikidata lexeme dump or created as minimal fixtures.

### 6. Update Ansible benchmark role

Update `ansible/roles/benchmark/tasks/main.yml` to install and invoke the new package:

```yaml
- name: Install entitybase-benchmark
  command: poetry install --no-root
  args:
    chdir: /opt/entitybase-benchmark

- name: Run EntityBase benchmark
  command: >
    python -m entitybase_benchmark
    --db-url "mysql://entitybase@{{ entitybase_mariadb_host }}/entitybase"
    --backends "http://{{ entitybase_lb_host }}:8080"
    --output /opt/entitybase/results/benchmark.json
  args:
    chdir: /opt/entitybase-benchmark
```

### 7. Update `run-test.sh`

Clone the benchmark repo during deploy (or bundle it). Add a step to copy
benchmark package to backend hosts.

## Files to create/modify

| File | Action |
|------|--------|
| `libs/entitybase-benchmark/pyproject.toml` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/__init__.py` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/__main__.py` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/cli.py` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/metrics.py` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/report.py` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/scenarios/__init__.py` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/scenarios/insert.py` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/scenarios/resolve.py` | Create |
| `libs/entitybase-benchmark/src/entitybase_benchmark/scenarios/concurrent.py` | Create |
| `libs/entitybase-benchmark/fixtures/sample_entities.json` | Create |
| `libs/entitybase-benchmark/fixtures/entity_ids.json` | Create |
| `ansible/roles/benchmark/tasks/main.yml` | Modify |
| `ansible/roles/benchmark/handlers/main.yml` | Create (if needed) |

## Open questions

1. **How does EntityBase resolve entities?** Need to understand the API to write
   realistic resolution benchmarks. Is it REST, gRPC, or direct DB queries?

2. **What entity format does EntityBase expect?** For the insert benchmark, we
   need to know the input schema.

3. **Should benchmarks run against the LB or individual backends?** Running
   against the LB measures the full stack; running against individual backends
   isolates backend performance. Recommend: both (configurable via `--backends`).

4. **Where does the benchmark package get cloned?** Currently the entitybase repo
   is cloned to `/opt/entitybase`. The benchmark could be a sibling at
   `/opt/entitybase-benchmark` or part of the same repo.
