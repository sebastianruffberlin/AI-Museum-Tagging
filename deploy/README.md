# Deployment-Paket: AI Museum Tagger

> **Stand: 24. Juni 2026**
> Dieses Paket ermöglicht den Aufbau des vollständigen Zwei-Server-Stacks.
> Voraussetzung: Beide Server sind bereits gebucht und SSH-Zugang ist eingerichtet.

---

## Voraussetzungen

### Was du selbst buchen und einrichten musst

**Server 1 — Orchestrierung (z. B. Hetzner CPX52):**
- Frische Ubuntu 24.04 LTS Installation
- SSH-Zugang als root
- Domain mit folgenden DNS-Einträgen (A-Record auf Server-IP):
  - `n8n.YOUR_DOMAIN`
  - `seatable.YOUR_DOMAIN`

**Server 2 — KI-Inferenz (z. B. Scaleway L40S-1-48G):**
- Scaleway GPU OS 13 (Ubuntu 24.04 + NVIDIA Treiber vorinstalliert)
- SSH-Zugang als root
- DNS-Einträge:
  - `llm.YOUR_DOMAIN` (nur von Hetzner-IP erreichbar)
  - `chat.YOUR_DOMAIN` (öffentlich, für Open WebUI)

**Lizenzen & Accounts:**
- SeaTable Enterprise Lizenz
- HuggingFace Account (kostenlos, für Modell-Downloads)

---

## Schritt-für-Schritt

### 1. `.env` ausfüllen
```bash
cp .env.example .env
nano .env
```

### 2. Hetzner-Server einrichten
```bash
scp setup_hetzner.sh root@YOUR_HETZNER_IP:~
ssh root@YOUR_HETZNER_IP
bash setup_hetzner.sh
```

Laufzeit: ~15 Minuten (ohne GND-Import)
GND-Import: ~30-60 Minuten zusätzlich

### 3. Scaleway-Server einrichten
```bash
scp setup_scaleway.sh root@YOUR_SCALEWAY_IP:~
ssh root@YOUR_SCALEWAY_IP
bash setup_scaleway.sh
```

Laufzeit: ~60-120 Minuten (Modell-Downloads: ~118 GB)

### 4. n8n Workflows importieren
1. `n8n.YOUR_DOMAIN` aufrufen
2. Workflows aus `../../workflows/` importieren
3. Credentials anlegen (SeaTable API-Token)
4. Platzhalter ersetzen (siehe `docs/stack_setup.md`)

### 5. SeaTable aufsetzen
Siehe `docs/setup_seatable.md`

---

## Dateien in diesem Paket

```
deploy/
├── README.md              # Diese Datei
├── .env.example           # Konfigurationsvorlage
├── setup_hetzner.sh       # Setup-Skript Server 1
└── setup_scaleway.sh      # Setup-Skript Server 2
```
