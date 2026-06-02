#!/bin/bash

docker compose down

# Volumes
docker volume rm 8mobentis-infrastructure_grafana_data 8mobentis-infrastructure_loki_data 8mobentis-infrastructure_prometheus_data 8mobentis-infrastructure_promtail_positions
