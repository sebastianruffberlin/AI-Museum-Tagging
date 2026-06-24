# Stack Setup: Infrastruktur-Dokumentation

> **Version: 2.0 | Stand: 24. Juni 2026**
> Zwei-Server-Setup: Hetzner (Orchestrierung) + Scaleway L40S (KI-Inferenz).
> Alle Dienste laufen als Docker-Container. Keine Cloud-APIs, keine Daten-Weitergabe.

---

## Übersicht

```
                    ┌─────────────────────────────────┐
                    │        HETZNER CPX52             │
                    │   (Orchestrierung & Daten)        │
                    │                                   │
  Browser / n8n ───│─ Caddy (TLS)                      │
                    │    ├── n8n          :5678          │
                    │    ├── SeaTable     :80            │
                    │    └── SearXNG                    │
                    │                                   │
                    │  OpenSearch (GND)  :9200 intern   │
                    │  MariaDB           :3306 intern   │
                    │  Redis             :6379 intern   │
                    └──────────────┬──────────────────-─┘
                                   │ HTTPS (nur Hetzner-IP)
                                   ▼
                    ┌─────────────────────────────────┐
                    │       SCALEWAY L40S-1-48G        │
                    │        (KI-Inferenz)              │
                    │                                   │
                    │  Caddy (TLS + IP-Firewall)        │
                    │    └── LiteLLM      :4000         │
                    │          └── llama-swap  :8080    │
                    │                └── llama-server   │
                    │                    (GGUF, GPU)    │
                    │                                   │
                    │  GLiNER2            :7070 intern  │
                    └─────────────────────────────────-─┘
```

**Subdomains (Strato DNS):**
* `n8n.YOUR_DOMAIN` → Hetzner (Caddy)
* `lcpp-gpu.YOUR_DOMAIN` → Scaleway (Caddy, nur von Hetzner-IP erreichbar)
* `chat-gpu.YOUR_DOMAIN` → Scaleway (Open WebUI, öffentlich)
* `glider2.YOUR_DOMAIN` → Scaleway (GLiNER2, nur von Hetzner-IP erreichbar)

---

## Server 1: Hetzner (Orchestrierung)

### Hardware
* **Instanz:** CPX52
* **CPU:** 12 vCPU
* **RAM:** 24 GB
* **Disk:** 80 GB NVMe lokal
* **OS:** Ubuntu 24.04.4 LTS (Kernel 6.8.0)

### Software-Versionen (Stand: 24. Juni 2026)
* **Docker:** `29.6.0`, Compose `v5.2.0`
* **n8n:** `2.27.4`
* **SeaTable Enterprise:** `6.1.8` + MariaDB `11.4.3-noble` + Redis `7.2.7-bookworm`
* **OpenSearch:** `latest` (kein fixer Tag — via Update-Script aktuell gehalten)
* **SearXNG:** `latest`
* **Caddy Docker Proxy:** `2.9.2-alpine`

### Docker-Dienste

#### Zentraler Stack (`/root/docker-compose.yml`)

```yaml
# n8n — Workflow-Orchestrierung
n8n:
  image: n8nio/n8n:latest          # aktuell: 2.27.4
  environment:
    N8N_HOST: n8n.YOUR_DOMAIN
    N8N_PROTOCOL: https
    N8N_RUNNERS_MAX_CONCURRENCY: 2
    N8N_EXECUTIONS_DATA_MAX_AGE: 24
    N8N_RUNNERS_TASK_TIMEOUT: 1200
  labels:
    caddy: n8n.YOUR_DOMAIN
    caddy.reverse_proxy: "{{upstreams 5678}}"

# OpenSearch — GND-Normdaten
gnd_opensearch:
  image: opensearchproject/opensearch:latest
  environment:
    OPENSEARCH_JAVA_OPTS: -Xms2g -Xmx2g
    DISABLE_SECURITY_PLUGIN: true
  ports:
    - "127.0.0.1:9200:9200"      # nur lokal erreichbar

# SearXNG — Metasuche
searxng:
  image: searxng/searxng:latest
```

#### SeaTable Stack (`/opt/seatable-server/`)

```yaml
seatable-server:
  image: seatable/seatable-enterprise:6.1.8

mariadb:
  image: mariadb:11.4.3-noble

redis:
  image: redis:7.2.7-bookworm
```

#### Reverse Proxy (`/opt/caddy/`)

```yaml
caddy:
  image: lucaslorentz/caddy-docker-proxy:2.9.2-alpine
  ports:
    - "80:80"
    - "443:443"
```

Caddy liest Labels der anderen Container und konfiguriert sich automatisch. TLS via Let's Encrypt.

### GND-Datenbank

OpenSearch indexiert die GND-Sachbegriffe der Deutschen Nationalbibliothek:

```bash
# Download (DNB Open Data)
wget https://data.dnb.de/opendata/authorities-gnd-sachbegriff_lds.jsonld.gz

# Import-Script
python3 /root/gnd_import/import.py
```

Index: `gnd-sachbegriffe` — ca. 250.000 Sachbegriffe mit `preferred_name`, `alternate_names`, `definition`.

### Update-Script

```bash
/root/update_all_stacks.sh
```

Führt aus: Ubuntu-Update → Docker Compose Pull & Up (beide Stacks) → SQLite Vacuum (n8n) → Backup-Rotation (7 Tage) → Healthcheck.

---

## Server 2: Scaleway (KI-Inferenz)

### Hardware
* **Instanz:** L40S-1-48G (On-Demand, Pay-per-Minute)
* **GPU:** NVIDIA L40S — 46 GB VRAM
* **RAM:** 96 GB
* **Disk:** 465 GB SSD (Modelle: `/opt/ki-inferenz/models/`, ~329 GB belegt)
* **OS:** Ubuntu 24.04.4 LTS (Kernel 6.8.0-124), Scaleway GPU OS 13

### Software-Versionen (Stand: 24. Juni 2026)
* **Docker:** `29.6.0`, Compose `v5.2.0`
* **NVIDIA Driver:** `580.159.03`
* **CUDA:** `13.0`
* **llama-swap:** Build `223` (2026-06-04), Image `ghcr.io/mostlygeek/llama-swap:cuda`
* **LiteLLM:** `1.82.6`
* **Caddy:** `latest`
* **GLiNER2:** lokal gebaut (`root-gliner2`)

> **Kostenhinweis:** On-Demand-Instanz — nur bei aktivem Betrieb kostenpflichtig.
> Für Produktionsbetrieb empfiehlt sich ein fester Abrechnungszyklus.

### Architektur: llama-swap → LiteLLM → Caddy

```
Anfrage von Hetzner (n8n)
        │
        ▼ HTTPS (IP-gesperrt)
      Caddy
        │
        ▼
    LiteLLM :4000        ← OpenAI-kompatibler Router
        │
        ▼
   llama-swap :8080      ← On-Demand Model-Switcher
        │                   max. 1 großes Modell im VRAM
        ▼
  llama-server           ← llama.cpp GGUF-Inferenz
     (GPU, VRAM)
```

**llama-swap Matrix** — steuert welche Modelle gemeinsam geladen werden dürfen:

```yaml
default:   phi4_mini | qwen3.6_27b_mtp | qwen3.6_35b_mtp
           # | = alternativ, nur eines gleichzeitig im VRAM
```

### Docker-Dienste (`/root/docker-compose.yml`)

```yaml
llama-swap:
  # Model-Switcher, bindet /opt/ki-inferenz/models als /models
  # Config: /opt/ki-inferenz/llama-swap/config.yaml

litellm:
  image: ghcr.io/berriai/litellm:main-latest
  # Config: /opt/ki-inferenz/litellm/config.yaml

caddy:
  image: caddy:latest
  # Caddyfile: /root/caddy/Caddyfile

gliner2:
  # NER-Service, erreichbar unter glider2.YOUR_DOMAIN
```

### Firewall (Caddy)

```
lcpp-gpu.YOUR_DOMAIN {
    @blocked not remote_ip YOUR_HETZNER_IP
    respond @blocked "Access Denied" 403
    reverse_proxy litellm:4000
}
```

Nur Anfragen von der Hetzner-IP werden durchgelassen. Alle anderen erhalten 403.

---

## Modelle

Alle Modelle liegen unter `/opt/ki-inferenz/models/` als GGUF-Dateien.

### Im Workflow aktiv

Kette: **n8n Workflow-ID → LiteLLM model_name → llama-swap key → GGUF**

| Workflow-ID | Vollname | Quant | Größe | GGUF-Pfad | Matrix-Set | Aufgabe |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `qwen3.6-35b-a3b-mtp-q4` | Qwen3.6-35B-A3B-MTP | UD-Q4_K_XL | 22 GB + 861 MB | `/models/qwen3.6-35b-a3b-mtp-q4/` | `caption_v2` | Caption A (Phase 1a, parallel) |
| `gemma-4-26b-a4b-qat` | Gemma-4-26B-A4B-it-QAT | UD-Q4_K_XL | 14 GB + 1.2 GB | `/models/gemma-4-26b-a4b-qat/` | `caption_v2` | Caption B (Phase 1a, parallel) |
| `gemma-4-12b-qat` | Gemma-4-12B-it-QAT | UD-Q4_K_XL | 6.3 GB + 168 MB | `/models/gemma-4-12b-qat/` | on-demand | Synthese LLM1b (Phase 1b) + Repair (Phase 3b) |
| `qwen3.6-27b-mtp` | Qwen3.6-27B-MTP | UD-Q6_K_XL | 25 GB + 889 MB | `/models/qwen3.6-27b-mtp/` | `default` | Tagging LLM2 (Phase 2) |
| `gemma-4-31b-it` | Gemma-4-31B-it | UD-Q4_K_XL | 18 GB + 1.2 GB | `/models/gemma-4-31b/` | `default` | Audit LLM3 (Phase 4) |
| `qwen3.6-35b-mtp` | Qwen3.6-35B-A3B-MTP | UD-Q6_K_XL | 31 GB + 861 MB | `/models/qwen3.6-35b-mtp/` | `default` | GND-Abgleich LLM4 (Phase 5) |

> **Hinweis:** `gemma-4-31b-it` liegt im Verzeichnis `/models/gemma-4-31b/` — Alias und Ordnername weichen ab.
>
> **caption_v2** = Qwen + Gemma laufen gleichzeitig im VRAM (`&` in llama-swap Matrix).
> **default** = nur eines dieser Modelle gleichzeitig (`|` in llama-swap Matrix).

### Download-Links (aktive Modelle)

**qwen3.6-35b-a3b-mtp-q4** (Caption A, caption_v2 Set):
```
model:   https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
mmproj:  https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/mmproj-BF16.gguf
Ziel:    /models/qwen3.6-35b-a3b-mtp-q4/
Größe:   22 GB (UD-Q4_K_XL) + 861 MB mmproj
```

**gemma-4-26b-a4b-qat** (Caption B, caption_v2 Set):
```
model:   https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF/resolve/main/gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf
mmproj:  https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF/resolve/main/mmproj-BF16.gguf
Ziel:    /models/gemma-4-26b-a4b-qat/
Größe:   14 GB (UD-Q4_K_XL) + 1.2 GB mmproj
```

**gemma-4-12b-qat** (Synthese + Repair):
```
model:   https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF/resolve/main/gemma-4-12B-it-qat-UD-Q4_K_XL.gguf
mmproj:  https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF/resolve/main/mmproj-BF16.gguf
Ziel:    /models/gemma-4-12b-qat/
Größe:   6.3 GB (UD-Q4_K_XL) + 168 MB mmproj
```

**qwen3.6-27b-mtp** (Tagging LLM2):
```
model:   https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF/resolve/main/Qwen3.6-27B-UD-Q6_K_XL.gguf
mmproj:  https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF/resolve/main/mmproj-BF16.gguf
Ziel:    /models/qwen3.6-27b-mtp/
Größe:   25 GB (UD-Q6_K_XL) + 889 MB mmproj
```

**gemma-4-31b-it** (Audit LLM3):
```
model:   https://huggingface.co/unsloth/gemma-4-31B-it-GGUF/resolve/main/gemma-4-31B-it-UD-Q4_K_XL.gguf
mmproj:  https://huggingface.co/unsloth/gemma-4-31B-it-GGUF/resolve/main/mmproj-BF16.gguf
Ziel:    /models/gemma-4-31b/          ← Ordnername weicht vom Alias ab
Größe:   18 GB (UD-Q4_K_XL) + 1.2 GB mmproj
```

**qwen3.6-35b-mtp** (GND-Abgleich LLM4):
```
model:   https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q6_K_XL.gguf
mmproj:  https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/mmproj-BF16.gguf
Ziel:    /models/qwen3.6-35b-mtp/
Größe:   31 GB (UD-Q6_K_XL) + 861 MB mmproj
```

> **Hinweis:** Die HuggingFace-Links können sich ändern. Bitte vor dem Download auf den jeweiligen HuggingFace-Seiten die aktuellen Dateinamen prüfen.

---

## Sicherheit

* Inferenz-Endpunkt per Caddy-Firewall auf Hetzner-IP beschränkt
* Kein öffentlicher Zugriff auf OpenSearch, MariaDB, Redis
* n8n nur über HTTPS erreichbar
* TLS-Zertifikate via Let's Encrypt (automatisch via Caddy)
* DNS bei Strato — Subdomains zeigen auf jeweilige Server-IPs
* API-Keys und Credentials nicht im Repository — Platzhalter in den Workflow-JSONs

---

## Systemauslastung (Betriebswerte Hetzner)

| Dienst | RAM | CPU |
| :--- | :--- | :--- |
| n8n | ~523 MiB | 0.42% |
| SeaTable | ~1.43 GiB | 3.51% |
| OpenSearch | ~1.54 GiB | 0.71% |
| **Gesamt** | **~4.1 GiB** | **0.13 (Idle)** |
