#!/bin/bash
# ============================================================
# AI Museum Tagger — Scaleway Setup
# KI-Inferenz-Server: llama-swap, LiteLLM, Caddy, GLiNER2
# Ubuntu 24.04 LTS + NVIDIA Treiber (Scaleway GPU OS 13)
# Stand: 24. Juni 2026
# Hinweis: Modell-Downloads ~118 GB, Laufzeit ~60-120 Minuten
# ============================================================

set -e
source .env

echo ""
echo "=================================================="
echo " AI Museum Tagger — Scaleway GPU Setup"
echo "=================================================="
echo ""

# --- 1. DOCKER INSTALLIEREN ---
echo "=== [1/6] Docker installieren ==="
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
fi

# nvidia-docker
if ! dpkg -l | grep -q nvidia-container-toolkit; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update -qq
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
fi

docker --version
nvidia-smi | head -5

# --- 2. VERZEICHNISSE & NETZWERK ---
echo "=== [2/6] Verzeichnisse & Netzwerk anlegen ==="
docker network create ki-netzwerk 2>/dev/null || true

mkdir -p /opt/ki-inferenz/models
mkdir -p /opt/ki-inferenz/llama-swap
mkdir -p /opt/ki-inferenz/litellm
mkdir -p /root/caddy/config
mkdir -p /root/caddy/data

# --- 3. CONFIGS SCHREIBEN ---
echo "=== [3/6] Konfigurationen schreiben ==="

# llama-swap config
cat > /opt/ki-inferenz/llama-swap/config.yaml << LLAMASWAP
healthCheckTimeout: 120

matrix:
  vars:
    a: qwen3.6-27b-mtp
    b: qwen3.6-35b-mtp
    g: gemma-4-31b-it
    h: qwen3.6-35b-a3b-mtp-q4
    i: gemma-4-26b-a4b-qat
    j: gemma-4-12b-qat
  sets:
    default: "a | b | g"
    caption_v2: "h & i"

models:
  "qwen3.6-27b-mtp":
    cmd: llama-server --host 0.0.0.0 --port \${PORT}
      -m /models/qwen3.6-27b-mtp/model.gguf
      --mmproj /models/qwen3.6-27b-mtp/mmproj.gguf
      -c 32768 -ngl 99 --flash-attn on
      --cache-type-k q8_0 --cache-type-v q8_0
      --reasoning-budget 1024 -np 2
      --spec-draft-n-max 2
      --alias qwen3.6-27b-mtp

  "qwen3.6-35b-mtp":
    cmd: llama-server --host 0.0.0.0 --port \${PORT}
      -m /models/qwen3.6-35b-mtp/model.gguf
      --mmproj /models/qwen3.6-35b-mtp/mmproj.gguf
      -c 65536 -ngl 99 --flash-attn on
      --cache-type-k q8_0 --cache-type-v q8_0
      --reasoning-budget 1024 -np 4
      --spec-draft-n-max 2 --spec-draft-p-min 0.75
      --alias qwen3.6-35b-mtp

  "gemma-4-31b-it":
    ttl: 0
    cmd: llama-server --host 0.0.0.0 --port \${PORT}
      -m /models/gemma-4-31b/model.gguf
      --mmproj /models/gemma-4-31b/mmproj.gguf
      -c 32768 -ngl 99 -t 8 --flash-attn on --jinja
      --image-min-tokens 280 --image-max-tokens 560
      --alias gemma-4-31b-it

  "qwen3.6-35b-a3b-mtp-q4":
    ttl: 0
    cmd: llama-server --host 0.0.0.0 --port \${PORT}
      -m /models/qwen3.6-35b-a3b-mtp-q4/model.gguf
      --mmproj /models/qwen3.6-35b-a3b-mtp-q4/mmproj.gguf
      -c 65536 -ngl 99 --flash-attn on
      --cache-type-k q8_0 --cache-type-v q8_0
      --reasoning-budget 1024 -np 8
      --spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-p-min 0.75
      --alias qwen3.6-35b-a3b-mtp-q4

  "gemma-4-26b-a4b-qat":
    ttl: 0
    cmd: llama-server --host 0.0.0.0 --port \${PORT}
      -m /models/gemma-4-26b-a4b-qat/model.gguf
      --mmproj /models/gemma-4-26b-a4b-qat/mmproj.gguf
      -c 32768 -ngl 99 -t 8 --flash-attn on --jinja
      --image-min-tokens 280 --image-max-tokens 560
      --alias gemma-4-26b-a4b-qat

  "gemma-4-12b-qat":
    ttl: 0
    cmd: llama-server --host 0.0.0.0 --port \${PORT}
      -m /models/gemma-4-12b-qat/model.gguf
      --mmproj /models/gemma-4-12b-qat/mmproj.gguf
      -c 32768 -ngl 99 -t 8 --flash-attn on --jinja
      --image-min-tokens 140 --image-max-tokens 280
      --alias gemma-4-12b-qat
LLAMASWAP

# LiteLLM config
cat > /opt/ki-inferenz/litellm/config.yaml << LITELLM
model_list:
  - model_name: qwen3.6-27b-mtp
    litellm_params:
      model: openai/qwen3.6-27b-mtp
      api_base: http://llama-swap-gpu:8080/v1
      api_key: "${LLM_API_KEY}"
      supports_vision: true
  - model_name: qwen3.6-35b-mtp
    litellm_params:
      model: openai/qwen3.6-35b-mtp
      api_base: http://llama-swap-gpu:8080/v1
      api_key: "${LLM_API_KEY}"
      supports_vision: true
  - model_name: gemma-4-31b-it
    litellm_params:
      model: openai/gemma-4-31b-it
      api_base: http://llama-swap-gpu:8080/v1
      api_key: "${LLM_API_KEY}"
      supports_vision: true
  - model_name: qwen3.6-35b-a3b-mtp-q4
    litellm_params:
      model: openai/qwen3.6-35b-a3b-mtp-q4
      api_base: http://llama-swap-gpu:8080/v1
      api_key: "${LLM_API_KEY}"
      supports_vision: true
  - model_name: gemma-4-26b-a4b-qat
    litellm_params:
      model: openai/gemma-4-26b-a4b-qat
      api_base: http://llama-swap-gpu:8080/v1
      api_key: "${LLM_API_KEY}"
      supports_vision: true
  - model_name: gemma-4-12b-qat
    litellm_params:
      model: openai/gemma-4-12b-qat
      api_base: http://llama-swap-gpu:8080/v1
      api_key: "${LLM_API_KEY}"
      supports_vision: true

general_settings:
  master_key: "${LLM_API_KEY}"

litellm_settings:
  drop_params: true
LITELLM

# Caddyfile
cat > /root/caddy/Caddyfile << CADDYFILE
llm.${DOMAIN} {
    @blocked not remote_ip ${HETZNER_IP}
    respond @blocked "Access Denied - Museum Network Only" 403
    reverse_proxy litellm:4000
}

chat.${DOMAIN} {
    reverse_proxy open-webui:8080
}
CADDYFILE

# Docker Compose
cat > /root/docker-compose.yml << COMPOSE
services:
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - /root/caddy/config:/config
      - /root/caddy/data:/data
      - /root/caddy/Caddyfile:/etc/caddy/Caddyfile
    command: caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
    networks:
      - ki-netzwerk

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: always
    volumes:
      - /opt/ki-inferenz/litellm/config.yaml:/app/config.yaml
    command: --config /app/config.yaml
    networks:
      - ki-netzwerk

networks:
  ki-netzwerk:
    external: true
COMPOSE

# --- 4. LLAMA-SWAP BAUEN & STARTEN ---
echo "=== [4/6] llama-swap starten ==="
docker run -d \
  --name llama-swap-gpu \
  --restart always \
  --gpus all \
  -v /opt/ki-inferenz/llama-swap/config.yaml:/app/config.yaml \
  -v /opt/ki-inferenz/models:/models \
  --network ki-netzwerk \
  ghcr.io/mostlygeek/llama-swap:cuda \
  -config /app/config.yaml

cd /root && docker compose up -d

# --- 5. MODELLE HERUNTERLADEN ---
echo "=== [5/6] Modelle herunterladen (~118 GB) ==="
echo "Das dauert 60-120 Minuten je nach Anbindung."
echo ""

download_model() {
  local dir=$1
  local model_url=$2
  local mmproj_url=$3

  mkdir -p "/opt/ki-inferenz/models/${dir}"
  echo "↓ ${dir}/model.gguf"
  wget -q --show-progress -O "/opt/ki-inferenz/models/${dir}/model.gguf" "$model_url"
  if [ -n "$mmproj_url" ]; then
    echo "↓ ${dir}/mmproj.gguf"
    wget -q --show-progress -O "/opt/ki-inferenz/models/${dir}/mmproj.gguf" "$mmproj_url"
  fi
}

# Caption A
download_model "qwen3.6-35b-a3b-mtp-q4" \
  "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf" \
  "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/mmproj-BF16.gguf"

# Caption B
download_model "gemma-4-26b-a4b-qat" \
  "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF/resolve/main/gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf" \
  "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF/resolve/main/mmproj-BF16.gguf"

# Synthese + Repair
download_model "gemma-4-12b-qat" \
  "https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF/resolve/main/gemma-4-12B-it-qat-UD-Q4_K_XL.gguf" \
  "https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF/resolve/main/mmproj-BF16.gguf"

# Tagging LLM2
download_model "qwen3.6-27b-mtp" \
  "https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF/resolve/main/Qwen3.6-27B-UD-Q6_K_XL.gguf" \
  "https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF/resolve/main/mmproj-BF16.gguf"

# Audit LLM3
download_model "gemma-4-31b" \
  "https://huggingface.co/unsloth/gemma-4-31B-it-GGUF/resolve/main/gemma-4-31B-it-UD-Q4_K_XL.gguf" \
  "https://huggingface.co/unsloth/gemma-4-31B-it-GGUF/resolve/main/mmproj-BF16.gguf"

# GND LLM4
download_model "qwen3.6-35b-mtp" \
  "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q6_K_XL.gguf" \
  "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/mmproj-BF16.gguf"

# --- 6. HEALTHCHECK ---
echo "=== [6/6] Healthcheck ==="
sleep 10
docker ps --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "=================================================="
echo " ✅ Scaleway Setup abgeschlossen!"
echo ""
echo " LLM-Endpunkt: https://llm.${DOMAIN}/v1"
echo " (nur von ${HETZNER_IP} erreichbar)"
echo "=================================================="
