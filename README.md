# AI Museum Tagger: Dokumentation

> **Version: 2.0 | Stand: 24. Juni 2026**
> Änderungen gegenüber v1.0: Caption-Pipeline auf parallele Dual-Model-Architektur mit Synthese-Schiedsrichter umgestellt, neuer Repair-Schritt für gelbe Begriffe, LLM3 wechselt von Triage zu Fehlerklassen-System, GND-Abgleich von AI-Agent auf Retrieve-then-Judge umgestellt, alle Modelle von Gemini auf vollständig lokale Open-Source-Modelle (Qwen/Gemma) migriert.

---

## 1. Projektziel und Ansatz

Dieses Projekt stellt eine **Middleware** für Museen bereit. Sie dient der automatisierten Transformation historischer Objektdaten in eine zeitgemäße, barrierearme und ethisch geprüfte Sprache.

Das Stadtmuseum Berlin verwaltet 4,5 Millionen Objekte aus 40 Teilsammlungen. Die Dokumentation dieser Objekte ist über Generationen von Museolog:innen gewachsen — sie ist oft undurchsichtig, voller Fachjargon, und für Nicht-Expert:innen kaum durchsuchbar. Dieses System macht diese Sammlung für die breite Öffentlichkeit auffindbar.

### Unser Ansatz: 40 Teilsammlungen, aber nur ein Workflow

Das System ist bewusst auf **Standardisierung** ausgelegt:

* **Eine Zielgruppe** — Nicht-Expert:innen, keine Sammlungsspezifik
* **Ein Modell-Stack** — kein Finetuning, keine sammlungsspezifischen Anpassungen
* **Ein Metadatenschema** — keine Spezialfelder
* **Eine Normdatenquelle** — (erstmals) nur GND

**Konsistenz** wird erreicht durch:

* Definierte ethische Guardrails (Decolonial Middleware)
* Museologische Regeln kodifiziert in 11 Clustern — das Erfahrungswissen langjähriger Erschließungsarbeit und geltender Museumsstandards
* Begründungspflicht (`why`-Feld) in jedem Schritt — kein Schlagwort ohne belegbare Evidenz
* LLM as a Judge — eine separate Prüfinstanz validiert jeden generierten Begriff
* JSON-Schema als strukturierter Output — maschinell weiterverarbeitbar

Der Prozess basiert auf einer **„Chain of Verification"**: Daten durchlaufen eine Sequenz spezialisierter LLM-Instanzen (Bildanalyse, Generierung, Audit, GND-Abgleich), die sich gegenseitig validieren. Das System ist vollständig **self-hosted und Open Source** — keine Cloud-APIs, keine Daten-Weitergabe an Dritte.

---

## 2. Technische Voraussetzungen

### Infrastruktur (Zwei-Server-Setup)

| Server | Aufgabe | Empfehlung |
| :--- | :--- | :--- |
| **Orchestrierung** | n8n, SeaTable, OpenSearch | Hetzner CPX52 oder vergleichbar (8+ vCPU, 16+ GB RAM) |
| **KI-Inferenz** | llama.cpp, LiteLLM, llama-swap | GPU-Server mit 48 GB VRAM (z. B. Scaleway L40S) |

Beide Server kommunizieren über HTTPS. Der Inferenz-Endpunkt ist per Firewall ausschließlich für den Orchestrierungs-Server erreichbar. Reverse Proxy (Caddy) übernimmt TLS-Terminierung auf beiden Servern.

### Software-Stack

**Orchestrierungs-Server:**
* Ubuntu 24.04 LTS
* Docker + Docker Compose
* **n8n** `2.27.4` — Workflow-Orchestrierung
* **SeaTable Enterprise** `6.1.8` + MariaDB `11.4.3` + Redis `7.2.7` — Datenverwaltung
* **OpenSearch** `latest` — GND-Normdaten-Datenbank (2 GB Heap)
* **SearXNG** `latest` — Metasuche (optional)
* **Caddy** `2.9.2` — Reverse Proxy & TLS

**KI-Inferenz-Server:**
* Ubuntu 24.04 LTS + NVIDIA Treiber
* Docker + nvidia-docker
* **llama-swap** — On-Demand Model-Switcher (max. 1 großes Modell gleichzeitig im VRAM)
* **LiteLLM** `main-latest` — OpenAI-kompatibler Proxy-Router
* **llama.cpp** (llama-server) — GGUF-Inferenz-Backend
* **Caddy** `latest` — Reverse Proxy & IP-Firewall
* **Ollama** `latest` — optional, für kleine Hilfsmodelle

### KI-Modelle (aktiv im Workflow)

Alle Modelle laufen lokal als GGUF via llama.cpp. Kein Cloud-API-Zugriff erforderlich.

| Workflow-ID | Vollname | Quant | Größe | Aufgabe | HuggingFace |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `qwen3.6-35b-a3b-mtp-q4` | Qwen3.6-35B-A3B-MTP | UD-Q4_K_XL | 22 GB + 861 MB | Caption A (Phase 1a, parallel) | [unsloth](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF) |
| `gemma-4-26b-a4b-qat` | Gemma-4-26B-A4B-it-QAT | UD-Q4_K_XL | 14 GB + 1.2 GB | Caption B (Phase 1a, parallel) | [unsloth](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF) |
| `gemma-4-12b-qat` | Gemma-4-12B-it-QAT | UD-Q4_K_XL | 6.3 GB + 168 MB | Synthese LLM1b (Phase 1b) + Repair (Phase 3b) | [unsloth](https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF) |
| `qwen3.6-27b-mtp` | Qwen3.6-27B-MTP | UD-Q6_K_XL | 25 GB + 889 MB | Tagging LLM2 (Phase 2) | [unsloth](https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF) |
| `gemma-4-31b-it` | Gemma-4-31B-it | UD-Q4_K_XL | 18 GB + 1.2 GB | Audit LLM3 (Phase 4) | [unsloth](https://huggingface.co/unsloth/gemma-4-31B-it-GGUF) |
| `qwen3.6-35b-mtp` | Qwen3.6-35B-A3B-MTP | UD-Q6_K_XL | 31 GB + 861 MB | GND-Abgleich LLM4 (Phase 5, np 4) | [unsloth](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF) |

Vollständige Modell-Dokumentation inkl. llama-swap Flags und Download-Links: `docs/stack_setup.md`

---

## 3. Kosten & Geschwindigkeit

Das System läuft auf einem Scaleway L40S GPU-Server (On-Demand, Pay-per-Minute). Die Kosten beziehen sich auf die reine GPU-Serverzeit — keine API-Gebühren, keine Daten-Weitergabe.

| Einheit | Zeit | Kosten |
| :--- | :--- | :--- |
| 1 Schlagwort | ~12 Sekunden | ~0,5 Ct |
| 1 Objekt (30 Schlagworte) | ~6 Minuten | ~15 Ct |
| 100 € Budget | ~68 Stunden | ~20.400 Schlagworte |
| 1.000 Objekte | ~100 Stunden | ~147 € |

*Basierend auf Scaleway L40S Serverpreisen und gemessener Inferenz-Geschwindigkeit des Stacks, Stand: 24. Juni 2026.*

---

## 4. Pipeline-Architektur

```
SeaTable (metadata)
        │
        ▼
[Tagging_Main] Pick_and_Clean_Item
        │
        ▼
[Tagging_Sub]
  ├── Phase 1a: Caption A (Qwen3.6-35B) ──┐
  ├── Phase 1a: Caption B (Gemma-4-31B)  ──┤ parallel
  │                                         ▼
  ├── Phase 1b: Synthese LLM1b (Gemma-4-31B) → master_caption
  │
  ├── Phase 2:  Tagging LLM2 (Qwen3.6-27B) → 11 Cluster
  │
  ├── Phase 3:  Audit LLM3 (Gemma-4-31B) → Fehlerklassen
  │                 │
  │           Code: Status aus Fehlerklassen berechnen
  │                 │
  │         ┌───────┴────────┐
  │       Grün             Gelb
  │         │                │
  │         │     Phase 3b: Repair-Kustos (Gemma-4-12B)
  │         │                │
  │         │         ┌──────┴──────┐
  │         │      Repariert    Nicht reparierbar
  │         │       → Grün        → verworfen
  │         │
  ├── Phase 4:  GND-Abgleich [Tagging_GND]
  │             OpenSearch _msearch → 5 Kandidaten
  │             LLM4 (Qwen3.6-35B-MTP, Concurrency 8)
  │
  └── Export → SeaTable (tags_gemini_2.5_pro) + Status-Update
```

---

## 5. Repository-Struktur

```
.
├── prompts/                # System- & User-Prompts für LLM-Instanzen
│   ├── 01a_caption_parallel.md    # Parallele Caption: Qwen + Gemma
│   ├── 01b_caption_synthese.md    # Synthese-Schiedsrichter (LLM1b)
│   ├── 02_kustos_generator.md     # Schlagwort-Generator (LLM2)
│   ├── 03_repair_kustos.md        # Repair-Kustos für gelbe Begriffe
│   ├── 04_senior_auditor.md       # Fehlerklassen-Audit (LLM3)
│   └── 05_gnd_referee.md          # GND-Abgleich Retrieve-then-Judge (LLM4)
├── workflows/              # n8n Workflow-Exporte (JSON)
│   ├── Tagging_Main.json          # Haupt-Workflow: Datenabruf & Orchestrierung
│   ├── Tagging_Sub.json           # Sub-Workflow: Caption → Tagging → Audit → Export
│   └── Tagging_GND.json           # Sub-Workflow: GND-Abgleich
├── templates/              # CSV-Importvorlagen für SeaTable
│   ├── metadata_template.csv
│   └── results_template.csv
├── docs/                   # Technische Dokumentation
│   ├── setup_seatable.md          # SeaTable Tabellen & Import
│   └── stack_setup.md             # Server-Setup: Hetzner + Scaleway
└── README.md
```

---

## 6. Komponentenbeschreibung

### 5.1. SeaTable Datenstruktur

Detaillierte Anleitungen zum Import und zur Konfiguration: `docs/setup_seatable.md`

**Tabelle `metadata` (Eingabe):**
* **Inv Nr** — Eindeutiger Primärschlüssel
* **processed** — Status-Indikator (Workflow verarbeitet Zeilen ungleich „ok")
* **Bildlink** — URL zum Objektbild
* **Titel / Beschreibung** — Historische Kontextdaten
* **newest** — Wird automatisch vom Workflow gesetzt

**Tabelle `tags_gemini_2.5_pro` (Ausgabe):**
* **cluster** — Klassifizierung (Objekttyp, Thema, Emotion, …)
* **schlagwort** — Validierter Begriff
* **status** — Audit-Bewertung (green / yellow / red)
* **gnd_id / gnd_name / confidence** — Referenzierte Normdaten
* **llm2 / llm3 / llm4** — Data Lineage der Zwischenschritte
* **hinweis** — Kritischer Hinweis des Senior-Auditors
* **audit1–audit5** — Decolonial Audit Log (5 Dimensionen)
* **status2** — Protokoll-Status (Open Access / Restricted / Sensitive)
* **config** — Automatisch befüllte Versions- und Modell-Konfiguration

### 5.2. n8n Verarbeitungsschritte

1. **Import & Splitting** — Abruf aus SeaTable, Single-Item-Picking
2. **Caption A + B (parallel)** — Qwen + Gemma erstellen unabhängige visuelle Befunde
3. **Synthese (LLM1b)** — Schiedsrichter konsolidiert, verwirft Halluzinationen, bereinigt Bias → `master_caption`
4. **Tagging (LLM2)** — 11 Cluster, Schlagworte mit Begründung (`why`)
5. **Fehlerklassen-Audit (LLM3)** — Klassifizierung statt Status; Code berechnet grün/gelb/rot deterministisch
6. **DE_BIAS_MAP** — Automatisierte Bereinigung diskriminierender Begriffe via JavaScript
7. **Repair-Kustos** — Gelbe Begriffe formal reparieren (Singular, Kompositum, Brücke)
8. **GND-Abgleich (Retrieve-then-Judge)** — OpenSearch liefert 5 Kandidaten, LLM4 wählt aus
9. **Aggregation & Export** — Zusammenführung, SeaTable-Export, Statusaktualisierung

---

## 7. Einrichtung

Dieses Repository kann auf drei Ebenen genutzt werden — je nach vorhandener Infrastruktur:

---

### Option 1: Nur die Prompts verwenden

Die System-Prompts in `prompts/` sind unabhängig vom restlichen Stack nutzbar. Sie funktionieren mit jedem OpenAI-kompatiblen LLM-Endpunkt (OpenRouter, OpenAI, lokale Modelle).

1. Prompt-Dateien aus `prompts/` herunterladen
2. System-Prompts in eigene LLM-Calls oder Agenten-Frameworks einbinden
3. Die 11 Cluster-Definitionen und Audit-Logik sind vollständig dokumentiert

---

### Option 2: n8n-Workflows mit eigenem Server

Die Workflow-JSONs aus `workflows/` sind sofort importierbar und funktionieren mit jedem OpenAI-kompatiblen Endpunkt — egal ob Cloud-API oder eigener Server.

1. SeaTable aufsetzen und Tabellen via CSV-Templates anlegen → `docs/setup_seatable.md`
2. Die drei JSON-Dateien in n8n importieren (`Tagging_Main.json`, `Tagging_Sub.json`, `Tagging_GND.json`)
3. Platzhalter in den Workflows ersetzen:
   - `YOUR_LLM_ENDPOINT` → eigener LLM-Endpunkt
   - `YOUR_API_KEY` → eigener API-Key
   - `YOUR_SEATABLE_CREDENTIAL_ID` → SeaTable API-Token
4. GND-Sachbegriffe in OpenSearch indexieren (Dump der DNB, Import-Script liegt bei)

---

### Option 3: Vollständigen Stack nachbauen

Der komplette Zwei-Server-Stack (Hetzner + Scaleway) kann gemäß `docs/stack_setup.md` nachgebaut werden. Das ist die empfohlene Option für Museen die Datensouveränität und volle Kontrolle wollen.

1. `docs/stack_setup.md` lesen — alle Versionen, Configs und Modell-Links sind dokumentiert
2. Hetzner-Server aufsetzen (n8n, SeaTable, OpenSearch, Caddy)
3. Scaleway GPU-Server aufsetzen (llama-swap, LiteLLM, Caddy)
4. Modelle herunterladen und in `/opt/ki-inferenz/models/` ablegen
5. Firewall konfigurieren: Inferenz-Endpunkt nur von Hetzner-IP erreichbar
6. Workflows importieren und Platzhalter ersetzen

---

### Anpassung

* **Analyse-Fokus** — System-Prompt in `01a_caption_parallel.md` anpassen
* **Klassifizierung** — 11 Cluster-Definitionen in `02_kustos_generator.md` modifizieren
* **Audit-Regeln** — Fehlerklassen-Katalog in `04_senior_auditor.md` erweitern
* **Bias-Filter** — `DE_BIAS_MAP` im Node `Parse_LLM3_and_Debias` (Tagging_Sub.json) ergänzen
* **SeaTable-Spalten** — Spaltennamen sind in den n8n-Nodes konfigurierbar; Vorlage in `templates/`

---

## 8. Potenzial für Weiterentwicklung

* **One-Click-Deployment** — Docker Compose Paket für Hetzner + Scaleway in Arbeit
* **Batch-Modus** — Parallele Verarbeitung mehrerer Objekte (setzt mehr VRAM als L40S voraus)
* **Monitoring** — Einbau von Langfuse (LLM-Tracing) und Grafana (Infrastruktur-Metriken)
* **Feedback-Loop** — Rückspeisung manuell korrigierter Schlagworte zur Prompt-Optimierung
* **DE_BIAS_MAP erweitern** — Ausbau auf ~800–1.200 Terme aus maschinenlesbaren Quellen (DE-BIAS/Europeana, Words Matter, Hurtlex, HateCheck u. a.) mit Dreischicht-Architektur: harte Ersetzung → Kontextualisierung → Flagging
* **Weitere Normdaten** — Integration von AAT (Getty), LCSH oder Wikidata

---

## 9. Lizenz

MIT License — siehe `LICENSE`
