# Deploy

Setup-Skripte für den vollständigen Zwei-Server-Stack (Hetzner + Scaleway).

📖 **Vollständige Anleitung:** [`docs/stack_setup.md`](../docs/stack_setup.md)

## Schnellstart

```bash
# 1. Konfiguration ausfüllen
cp .env.example .env
nano .env

# 2. Hetzner-Server einrichten
scp setup_hetzner.sh import_gnd.py root@YOUR_HETZNER_IP:~
ssh root@YOUR_HETZNER_IP "bash setup_hetzner.sh"

# 3. Scaleway-Server einrichten (~60-120 Min, Modell-Downloads 118 GB)
scp setup_scaleway.sh root@YOUR_SCALEWAY_IP:~
ssh root@YOUR_SCALEWAY_IP "bash setup_scaleway.sh"
```

## Dateien

| Datei | Zweck |
| :--- | :--- |
| `.env.example` | Konfigurationsvorlage — kopieren und ausfüllen |
| `setup_hetzner.sh` | Richtet Orchestrierungs-Server ein (n8n, SeaTable, OpenSearch) |
| `setup_scaleway.sh` | Richtet GPU-Inferenz-Server ein (llama-swap, LiteLLM, Modelle) |
| `import_gnd.py` | Importiert GND-Sachbegriffe in OpenSearch |
