# mobentis-infrastructure

Infrastructure-as-code and ops configuration for the mobentis platform — a self-healing infrastructure stack with automated service recovery across six escalation levels (L0–L6).

## Architecture

### Three-plane design

| Plane         | Purpose                              | Location            |
|---------------|--------------------------------------|---------------------|
| **Control**   | Central services (DB, cache)         | This host           |
| **Data**      | Agents and exporters on target hosts | Remote hosts (Ansible) |
| **Recovery**   | Isolated Selenium worker for L5     | Separate VM         |

### Service map

```
                         Cloudflare Tunnel (cloudflared)
                         TLS termination + subdomain routing
                                    │
              ┌─────────────────────┼─────────────────────┐
              │   control_net       │   monitoring_net     │
              │                     │                      │
              │  ┌──────────┐       │  ┌────────────────┐  │
              │  │ Postgres │       │  │  Prometheus    │  │
              │  │   :5432  │       │  │     :9090      │  │
              │  └──────────┘       │  └───────┬────────┘  │
              │                     │          │ scrape     │
              │  ┌──────────┐       │  ┌───────▼────────┐  │
              │  │  Redis   │       │  │  Alertmanager  │  │
              │  │   :6379  │       │  │     :9093      │  │
              │  └──────────┘       │  └────────────────┘  │
              │                     │                      │
              └─────────────────────┤  ┌────────────────┐  │
                                    │  │      Loki      │  │
                                    │  │      :3100     │  │
                                    │  └───────▲────────┘  │
                                    │          │ push      │
                                    │  ┌───────┴────────┐  │
                                    │  │    Promtail    │  │
                                    │  │ (Docker logs + │  │
                                    │  │    journal)    │  │
                                    │  └────────────────┘  │
                                    │                      │
                                    │  ┌────────────────┐  │
                                    │  │    Grafana     │  │
                                    │  │     :3000      │  │
                                    │  └────────────────┘  │
                                    └──────────────────────┘
```

## Prerequisites

- **Docker Engine** 24+ and **Docker Compose** v2+
- **Cloudflare Tunnel** (`cloudflared`) running and connected
- **Domain** managed via Cloudflare DNS
- **Linux host** (Ubuntu 22.04+ or Debian 12+ recommended)
- **sudo** access for volume permission setup

No inbound ports required — Cloudflare Tunnel is outbound-only.

## Quick start

```bash
# 1. Clone the repo
git clone <repo-url> && cd mobentis-infrastructure

# 2. Configure environment
cp .env.example .env
# Edit .env — required: DOMAIN, POSTGRES_PASSWORD, REDIS_PASSWORD, GRAFANA_ADMIN_PASSWORD

# 3. Configure Cloudflare Tunnel (see below)

# 4. Run setup
./scripts/setup.sh

# 5. Verify
./scripts/healthcheck.sh
```

### Cloudflare Tunnel configuration

Ensure `cloudflared` is on the `monitoring_net` Docker network, then configure subdomain routing in the Cloudflare Zero Trust dashboard or via `config.yml`:

```yaml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: grafana.<domain>
    service: http://grafana:3000
  - hostname: prometheus.<domain>
    service: http://prometheus:9090
  - hostname: alerts.<domain>
    service: http://alertmanager:9093
  - service: http_status:404
```

Once DNS resolves, access:
- **Grafana**: `https://grafana.<your-domain>`
- **Prometheus**: `https://prometheus.<your-domain>`
- **Alertmanager**: `https://alerts.<your-domain>`

## Configuration reference

### Environment variables (`.env`)

| Variable               | Required | Default       | Description                          |
|------------------------|----------|---------------|--------------------------------------|
| `DOMAIN`               | yes      | —             | Public domain (used for subdomain routing) |
| `POSTGRES_USER`        | no       | mobentis      | Postgres superuser                   |
| `POSTGRES_PASSWORD`    | yes      | —             | Postgres password                    |
| `POSTGRES_DB`          | no       | mobentis      | Default database                     |
| `REDIS_PASSWORD`       | yes      | —             | Redis AUTH password                  |
| `GRAFANA_ADMIN_USER`   | no       | admin         | Grafana admin username               |
| `GRAFANA_ADMIN_PASSWORD` | yes    | —             | Grafana admin password               |
| `SMTP_HOST`            | yes*     | —             | SMTP server for alerts               |
| `SMTP_PORT`            | yes*     | 587           | SMTP port                            |
| `SMTP_FROM`            | yes*     | —             | Alert sender email                   |
| `SMTP_USER`            | yes*     | —             | SMTP auth user                       |
| `SMTP_PASSWORD`        | yes*     | —             | SMTP auth password                   |
| `ALERT_EMAIL_TO`       | yes*     | —             | Where alerts are sent                |
| `DATA_DIR`             | no       | /data         | Host path for persistent volumes     |

*Required only if using email alerts.

### Prometheus (`config/prometheus/`)

- **`prometheus.yml`** — scrape targets (self, Alertmanager, Grafana, Loki) and alertmanager endpoint. Edit `scrape_configs` to add node-exporters or custom targets.
- **`rules/alerts.yml`** — alerting rules. Pre-configured: service down, disk/memory/CPU thresholds. Add custom rules here.

### Alertmanager (`config/alertmanager/`)

- **`alertmanager.yml`** — routing tree and receivers. Default: all alerts go to email. Uncomment `recovery-controller-webhook` receiver to forward alerts to the Recovery Controller.

### Loki + Promtail (`config/loki/`, `config/promtail/`)

- **`loki-config.yml`** — 30-day retention, filesystem storage under `/loki`. Tune `retention_period` in `limits_config`.
- **`promtail-config.yml`** — collects Docker container logs via socket and systemd journal. Add `static_configs` for custom log files.

### Grafana provisioning (`config/grafana/provisioning/`)

- **`datasources/datasource.yml`** — auto-configures Prometheus (default) and Loki data sources.
- **`dashboards/dashboard.yml`** — file-based dashboard provider. Drop JSON dashboard files into `config/grafana/provisioning/dashboards/`.

## Directory layout

```
mobentis-infrastructure/
├── .env                          # Environment variables (not committed)
├── .env.example                  # Template (copy to .env)
├── docker-compose/
│   ├── control-plane.yml         # Postgres, Redis
│   └── observability.yml         # Prometheus, Alertmanager, Loki, Promtail, Grafana
├── config/
│   ├── prometheus/
│   │   ├── prometheus.yml        # Scrape config
│   │   └── rules/alerts.yml      # Alerting rules
│   ├── alertmanager/
│   │   └── alertmanager.yml      # Routing + receivers
│   ├── loki/loki-config.yml      # Log aggregation config
│   ├── promtail/promtail-config.yml  # Log collection config
│   └── grafana/provisioning/
│       ├── datasources/datasource.yml  # Auto data sources
│       └── dashboards/dashboard.yml    # Dashboard provider
├── scripts/
│   ├── setup.sh                  # One-command bootstrap
│   └── healthcheck.sh            # Service health verification
└── ansible/inventory/            # Future agent/exporter playbooks
```

## Maintenance tasks

### Daily

```bash
# Check all services are healthy
./scripts/healthcheck.sh

# Check Prometheus alerts (requires cloudflared routing)
open https://prometheus.<domain>/alerts
```

### Weekly

```bash
# Pull latest images and restart
docker compose -f docker-compose/control-plane.yml pull
docker compose -f docker-compose/observability.yml pull
docker compose -f docker-compose/control-plane.yml up -d
docker compose -f docker-compose/observability.yml up -d

# Check disk usage
df -h /data
docker system df
```

### Backup

```bash
# Postgres
docker exec postgres pg_dumpall -U mobentis > backup_$(date +%Y%m%d).sql

# Redis (if persistence needed beyond RDB)
docker exec redis redis-cli --rdb /data/dump.rdb SAVE
# Then copy from /data/redis/dump.rdb

# Grafana dashboards (export via UI or API)
# Prometheus TSDB: back up /data volume or use remote_write
```

### Restore

```bash
# Postgres
cat backup.sql | docker exec -i postgres psql -U mobentis

# Redis — copy dump.rdb to /data/redis/ and restart
```

### Adding a new service

1. Add the service to the appropriate docker-compose file.
2. Add a route in Cloudflare Tunnel ingress config:
   ```yaml
   - hostname: newservice.<domain>
     service: http://newservice:<port>
   ```
3. Restart cloudflared or wait for config sync.

### Adding a Prometheus scrape target

Add a `static_configs` block under `scrape_configs` in `config/prometheus/prometheus.yml`, then reload:
```bash
docker exec prometheus wget -qO- --post-data="" http://localhost:9090/-/reload
```

### Rotating logs

Logs are retained 30 days by Loki. To rotate sooner, reduce `retention_period` in `config/loki/loki-config.yml` and restart Loki.

## Troubleshooting

| Symptom                                 | Check                                                                                     |
|-----------------------------------------|-------------------------------------------------------------------------------------------|
| Cloudflare Tunnel can't reach services  | Verify cloudflared is on `monitoring_net`. Check: `docker network inspect monitoring_net` |
| Prometheus shows "target down"          | Service may be on wrong network. All services must be on `monitoring_net`.                |
| No logs in Grafana/Loki                 | Promtail needs `/var/run/docker.sock` mounted. Verify: `docker logs promtail`             |
| Grafana login fails                     | Check `GF_SECURITY_ADMIN_PASSWORD` in `.env` matches what was set at first startup.       |
| Postgres connection refused             | Verify credentials in `.env`. Check: `docker exec postgres pg_isready`                    |
| Redis connection refused                | Check password in `.env`. Test: `docker exec redis redis-cli -a $REDIS_PASSWORD ping`     |

### Logs

```bash
# All services
docker compose -f docker-compose/control-plane.yml logs -f
docker compose -f docker-compose/observability.yml logs -f

# Single service
docker logs -f grafana
docker logs -f prometheus
```

### Full restart

```bash
docker compose -f docker-compose/control-plane.yml down
docker compose -f docker-compose/observability.yml down
docker compose -f docker-compose/control-plane.yml up -d
docker compose -f docker-compose/observability.yml up -d
```

## Alerting rules

| Alert                      | Condition                                    | Severity |
|----------------------------|----------------------------------------------|----------|
| `ServiceDown`              | Any service unreachable for 2m               | critical |
| `PrometheusTargetMissing`  | Prometheus scraping missing                  | critical |
| `WebsiteDown`              | Website HTTP probe fails for 2m              | critical |
| `DiskSpaceLow`             | Host disk <10% free for 5m                   | warning  |
| `HighMemoryUsage`          | Host memory >90% for 5m                      | warning  |
| `HighCPUUsage`             | Host CPU >80% for 10m                        | warning  |
| `WebsiteSlow`              | Website response >3s for 2m                  | warning  |
| `WebsiteSSLCertExpiring`   | SSL cert expires within 7 days               | warning  |

## Future additions (not yet implemented)

- **Portainer CE** — Docker management UI
- **Authentik/Keycloak** — OIDC authentication for Grafana and other UIs
- **Selenium worker** — isolated VM for L5 recovery (server reboot via IONOS dashboard)
- **Ansible playbooks** — agent/exporter installation on target hosts
- **Recovery Controller** — Python/FastAPI in sibling `platform-controller/` repo
