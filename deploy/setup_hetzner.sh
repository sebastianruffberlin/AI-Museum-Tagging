#!/bin/bash
# ============================================================
# AI Museum Tagger — Hetzner Setup
# Stand: 24. Juni 2026
#
# Verifizierte Struktur:
# - Caddy:      /opt/caddy/docker-compose.yml
# - OpenSearch + SearXNG + n8n: /root/docker-compose.yml
# - SeaTable:   /opt/seatable-compose/ (offizielles SeaTable Compose)
# - Netzwerke:  frontend-net, root_museum-internal, backend-seatable-net
# ============================================================

set -e
source .env

echo ""
echo "=================================================="
echo " AI Museum Tagger — Hetzner Setup"
echo "=================================================="
echo ""

# --- 1. SYSTEM UPDATE ---
echo "=== [1/6] System-Update ==="
apt-get update -qq && apt-get upgrade -y -qq

# --- 2. DOCKER & PYTHON ---
echo "=== [2/6] Docker & Python installieren ==="
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
fi
apt-get install -y screen -qq
pip install opensearch-py tqdm --break-system-packages -q
docker --version

# --- 3. NETZWERKE ---
echo "=== [3/6] Netzwerke anlegen ==="
docker network create frontend-net 2>/dev/null || true
docker network create museum-internal 2>/dev/null || true
docker network create backend-seatable-net 2>/dev/null || true

# --- 4. CADDY ---
echo "=== [4/6] Caddy starten ==="
mkdir -p /opt/caddy
cat > /opt/caddy/docker-compose.yml << 'CADDY'
version: "3.7"
services:
  caddy:
    image: lucaslorentz/caddy-docker-proxy:2.9.2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - 80:80
      - 443:443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - frontend-net

networks:
  frontend-net:
    name: frontend-net
    external: true
CADDY

cd /opt/caddy && docker compose up -d

# --- 5. OPENSEARCH + SEARXNG + N8N ---
echo "=== [5/6] OpenSearch, SearXNG, n8n starten ==="

mkdir -p /root/searxng /root/gnd_import

cat > /root/searxng/settings.yml << SEARXNG
use_default_settings: true
server:
    port: 8080
    bind_address: "0.0.0.0"
    secret_key: "${SEARXNG_SECRET_KEY}"
search:
    formats:
        - json
engines:
  - name: startpage
    engine: startpage
    weight: 2
  - name: brave
    engine: brave
    weight: 1
  - name: duckduckgo
    engine: duckduckgo
    weight: 1
  - name: wikidata
    engine: wikidata
    weight: 2.5
    disabled: false
  - name: worldcat
    engine: worldcat
    weight: 2.0
    disabled: false
  - name: archive.org
    engine: archive
    weight: 1.5
    disabled: false
  - name: openlibrary
    engine: openlibrary
    weight: 1.0
    disabled: false
  - name: europeana
    engine: europeana
    weight: 1.5
    disabled: false
  - name: google scholar
    engine: google_scholar
    weight: 1.0
    disabled: false
  - name: wikipedia de
    engine: wikipedia
    language: de
    weight: 2.0
    disabled: false
SEARXNG

cat > /root/docker-compose.yml << COMPOSE
version: '3.8'
services:
  gnd_opensearch:
    image: opensearchproject/opensearch:latest
    container_name: gnd_opensearch
    restart: unless-stopped
    environment:
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - OPENSEARCH_JAVA_OPTS=-Xms2g -Xmx2g
      - DISABLE_INSTALL_DEMO_CONFIG=true
      - DISABLE_SECURITY_PLUGIN=true
      - indices.memory.index_buffer_size=15%
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - os_data:/usr/share/opensearch/data
    ports:
      - "127.0.0.1:9200:9200"
    networks:
      - museum-internal

  searxng:
    image: searxng/searxng:latest
    container_name: searxng
    restart: unless-stopped
    networks:
      - museum-internal
      - frontend-net
    volumes:
      - /root/searxng:/etc/searxng
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-museum
    restart: unless-stopped
    environment:
      - N8N_HOST=n8n.${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_SECURE_COOKIE=true
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - NODE_OPTIONS=--max-old-space-size=1024
      - N8N_RUNNERS_MAX_CONCURRENCY=2
      - N8N_EXECUTIONS_DATA_PRUNE=true
      - N8N_EXECUTIONS_DATA_MAX_AGE=24
      - NODE_FUNCTION_ALLOW_BUILTIN
      - NODE_FUNCTION_ALLOW_EXTERNAL
      - N8N_RUNNERS_TASK_TIMEOUT=1200
      - WEBHOOK_URL=https://n8n.${DOMAIN}
      - GENERIC_TIMEZONE=Europe/Berlin
      - DB_TYPE=sqlite
      - EXECUTIONS_DATA_PRUNE=true
    volumes:
      - n8n_n8n_data:/home/node/.n8n
    networks:
      - museum-internal
      - frontend-net
    labels:
      caddy: n8n.${DOMAIN}
      caddy.reverse_proxy: "{{upstreams 5678}}"
      caddy.reverse_proxy.flush_interval: "-1"
      caddy.encode: gzip
      caddy.header.Strict-Transport-Security: "max-age=31536000; includeSubDomains; preload"
      caddy.header.X-Content-Type-Options: "nosniff"
      caddy.header.X-Frame-Options: "DENY"

volumes:
  n8n_n8n_data:
  os_data:

networks:
  museum-internal:
  frontend-net:
    external: true
COMPOSE

cd /root && docker compose up -d

# --- 6. SEATABLE (offizielles SeaTable Compose) ---
echo "=== [6/6] SeaTable einrichten ==="
mkdir -p /opt/seatable-compose /opt/seatable-server /opt/mariadb

# SeaTable Compose herunterladen
cd /opt/seatable-compose
if [ ! -f seatable-server.yml ]; then
    curl -sO https://raw.githubusercontent.com/seatable/seatable-release/main/seatable-server.yml
fi

cat > /opt/seatable-compose/.env << SEATABLE_ENV
COMPOSE_FILE=seatable-server.yml
TIME_ZONE=Europe/Berlin
SEATABLE_SERVER_HOSTNAME=seatable.${DOMAIN}
SEATABLE_SERVER_PROTOCOL=https
SEATABLE_ADMIN_EMAIL=${SEATABLE_ADMIN_EMAIL}
SEATABLE_ADMIN_PASSWORD=${SEATABLE_ADMIN_PASSWORD}
MARIADB_PASSWORD=${SEATABLE_DB_PASSWORD}
MARIADB_ROOT_PASSWORD=${SEATABLE_DB_PASSWORD}
REDIS_PASSWORD=${SEATABLE_REDIS_PASSWORD}
JWT_PRIVATE_KEY=${SEATABLE_JWT_KEY}
SEATABLE_DB_IMAGE=mariadb:11.4.3-noble
SEATABLE_REDIS_IMAGE=redis:7.2.7-bookworm
SEATABLE_ENV

# override für frontend-net
cat > /opt/seatable-compose/docker-compose.override.yml << 'OVERRIDE'
services:
  seatable-server:
    networks:
      - frontend-net
    labels:
      caddy: "${SEATABLE_SERVER_HOSTNAME}"
      caddy.reverse_proxy: "{{upstreams 80}}"
      caddy.header.Strict-Transport-Security: "max-age=31536000; includeSubdomains; preload"
      caddy.header.X-Content-Type-Options: "nosniff"
      caddy.header.X-Frame-Options: "SAMEORIGIN"

networks:
  frontend-net:
    external: true
OVERRIDE

cd /opt/seatable-compose && docker compose up -d

# --- GND-IMPORT ---
echo ""
echo "=== GND-Import ==="
cp /root/import_gnd.py /root/gnd_import/
cd /root/gnd_import

echo "Lade GND-Sachbegriffe (~24 MB)..."
wget -q --show-progress \
  "https://data.dnb.de/opendata/authorities-gnd-sachbegriff_lds.jsonld.gz" \
  -O authorities-gnd-sachbegriff_lds.jsonld.gz

echo "Warte auf OpenSearch..."
until curl -s http://localhost:9200/_cluster/health | \
  grep -q '"status":"green"\|"status":"yellow"'; do
    sleep 5
done

echo "Starte Import im Hintergrund (screen -r gnd_import zum Verfolgen)..."
screen -dmS gnd_import python3 import_gnd.py

echo ""
echo "=================================================="
echo " ✅ Hetzner Setup abgeschlossen!"
echo ""
echo " n8n:        https://n8n.${DOMAIN}"
echo " SeaTable:   https://seatable.${DOMAIN}"
echo " GND-Import: screen -r gnd_import"
echo " Zähler:     curl -s http://localhost:9200/gnd_sachbegriffe/_count"
echo "=================================================="
