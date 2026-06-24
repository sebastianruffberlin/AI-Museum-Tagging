# AI Museum Tagger: Dokumentation

> **Version: 2.0 | Stand: 24.Juni 2026**
> Änderungen gegenüber v1.0: Caption-Pipeline auf parallele Dual-Model-Architektur mit Synthese-Schiedsrichter umgestellt, neuer Repair-Schritt für gelbe Begriffe, LLM3 wechselt von Triage zu Fehlerklassen-System, GND-Abgleich von AI-Agent auf Retrieve-then-Judge umgestellt, alle Modelle von Gemini auf lokale Modelle (Qwen/Gemma) migriert.

---

## 1. Projektziel und Ansatz

Dieses Projekt stellt eine **Middleware** für Museen bereit. Sie dient der automatisierten Transformation historischer Objektdaten in eine zeitgemäße, barrierearme und ethisch geprüfte Sprache.

Der Prozess basiert auf einer **„Chain of Verification"**: Daten durchlaufen eine Sequenz spezialisierter LLM-Instanzen (Analyse, Generierung, Audit), um eine gegenseitige Validierung zu gewährleisten. Das System liefert eine Verschlagwortung, die sowohl **GND-konform** (Gemeinsame Normdatei) als auch nach dem **Folksonomie-Prinzip** (nutzerorientiert) aufgebaut ist.

---

## 2. Technische Voraussetzungen und Versionen

Das System wurde mit folgenden Komponenten getestet (Stand: Juni 2026):

* **n8n:** Version **2.16.1** (Self-hosted via Docker).
* **SeaTable:** **Enterprise Edition 6.0.10**.
* **Elasticsearch:** Version **8.13** (Vektor- und Suchdatenbank für Normdaten).
* **GND-Datenbestand:** Stand **10.04.2026**.
* **KI-Modelle:** Lokale Modelle via eigenem LLM-Endpunkt (llama-swap):
  * `qwen3.6-35b-a3b-mtp-q4` — Caption A
  * `gemma-4-26b-a4b-qat` — Caption B
  * `gemma-4-12b-qat` — Synthese / Repair
  * `qwen3.6-27b-mtp` — Tagging (LLM2)
  * `gemma-4-31b-it` — Audit (LLM3)
  * `qwen3.6-35b-mtp` — GND-Abgleich (LLM4)

---

## 3. Infrastruktur und Deployment

Das System wird als Multi-Container-Setup (3 Instanzen via Docker Compose) auf einem VPS betrieben.

### Hardware-Spezifikationen (Empfehlung)
* **VPS:** 8 vCPU (optimiert für parallele Reasoning-Tasks).
* **RAM:** 16 GB.
* **Speicher:** 80 GB NVMe.

### Systemauslastung (Betriebswerte)
| Dienst | Funktion | RAM-Nutzung | CPU-Last |
| :--- | :--- | :--- | :--- |
| **n8n** | Orchestrierung & API-Management | ~523 MiB | 0.42% |
| **SeaTable** | Datenverwaltung & Workflow-Steuerung | ~1.43 GiB | 3.51% |
| **Elasticsearch** | Indizierung der GND-Daten | ~1.54 GiB | 0.71% |
| **Gesamt** | **Host-System** | **~4.1 GiB** | **0.13 (Idle)** |

---

## 4. Pipeline-Architektur

Der Stack besteht aus drei Ebenen:
1. **SeaTable:** Datenquelle für Metadaten und Zielspeicher für Ergebnisse.
2. **n8n:** Steuerung der Logik, Datenaufbereitung via JavaScript und LLM-Sequenzierung.
3. **Elasticsearch:** Bereitstellung der Normdaten für den deterministischen GND-Abgleich.

### Pipeline-Überblick (v2)

```
SeaTable (metadata)
        │
        ▼
[Tagging_Main] Pick_and_Clean_Item
        │
        ▼
[Tagging_Sub]
  ├── Phase 1a: Caption A (Qwen) ──┐
  ├── Phase 1a: Caption B (Gemma) ─┤ parallel
  │                                 ▼
  ├── Phase 1b: Synthese LLM1b → master_caption
  │
  ├── Phase 2:  Tagging LLM2 → 11 Cluster / Schlagworte + why
  │
  ├── Phase 3:  Audit LLM3 → Fehlerklassen (kein Status!)
  │                 │
  │           Code: Status aus Fehlerklassen berechnen
  │                 │
  │         ┌───────┴────────┐
  │       Grün             Gelb
  │         │                │
  │         │         Phase 3b: Repair-Kustos
  │         │                │
  │         │         ┌──────┴──────┐
  │         │      Repariert    Nicht reparierbar
  │         │       → Grün        → verworfen
  │         │
  ├── Phase 4:  GND-Abgleich [Tagging_GND]
  │             OpenSearch _msearch → 5 Kandidaten pro Begriff
  │             LLM4 Retrieve-then-Judge (Concurrency 8)
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
│   └── setup_seatable.md
└── README.md
```

---

## 6. Komponentenbeschreibung

### 6.1. SeaTable Datenstruktur

Die Tabellen müssen zur korrekten Verarbeitung folgende Felder enthalten. Detaillierte Anleitungen zum Import und zur Konfiguration in `docs/setup_seatable.md`.

**Tabelle `metadata` (Eingabe):**
* **Inv Nr**: Eindeutiger Primärschlüssel.
* **processed**: Status-Indikator (Workflow verarbeitet Zeilen ungleich „ok").
* **Bildlink**: URL zum Objektbild.
* **Titel / Beschreibung**: Historische Kontextdaten.
* **newest**: Wird automatisch vom Workflow gesetzt (z. B. `ok_1.3`).

**Tabelle `tags_gemini_2.5_pro` (Ausgabe):**
* **cluster**: Klassifizierung (z. B. Objekttyp, Thema, Emotion).
* **schlagwort**: Validierter Begriff.
* **status**: Audit-Bewertung (green / yellow / red).
* **gnd_id / gnd_name**: Referenzierte Normdaten.
* **confidence**: Konfidenz des GND-Abgleichs.
* **llm2 / llm3 / llm4**: Protokollierung der Zwischenschritte (Data Lineage).
* **hinweis**: Kritischer Hinweis des Senior-Auditors.
* **audit1–audit5**: Decolonial Audit Log (5 Dimensionen).
* **status2**: Protokoll-Status (Open Access / Restricted / Sensitive).
* **config**: Automatisch befüllte Versions- und Modell-Konfiguration.

### 6.2. n8n Verarbeitungsschritte

1. **Import & Splitting**: Abruf der Daten aus SeaTable, Vereinzelung auf einen Datensatz pro Lauf.
2. **Caption A + B** (parallel): Zwei Vision-Modelle (Qwen + Gemma) erstellen unabhängige visuelle Befunde.
3. **Synthese (LLM1b)**: Schiedsrichter-Modell konsolidiert beide Captions, verwirft Halluzinationen, bereinigt Bias → `master_caption`.
4. **Schlagwort-Generierung (LLM2)**: Erstellt Keywords in 11 Clustern auf Basis von master_caption + Metadaten.
5. **Fehlerklassen-Audit (LLM3)**: Ordnet jeden Begriff Fehlerklassen zu (kein Status — deterministischer Code berechnet grün/gelb/rot).
6. **DE_BIAS_MAP**: Automatisierte Bereinigung diskriminierender Begriffe via JavaScript.
7. **Repair-Kustos**: Versucht gelbe Begriffe formal zu reparieren (Singular, Kompositum, Brücke). Reparierte Begriffe werden grün.
8. **GND-Abgleich (Retrieve-then-Judge)**: OpenSearch liefert 5 Kandidaten pro Begriff, LLM4 wählt den besten aus oder gibt no_match zurück. Concurrency 8.
9. **Aggregation & Export**: Zusammenführung aller Stränge, Schreiben nach SeaTable, Statusaktualisierung.

---

## 7. Potenzial für Weiterentwicklung

* **Erweiterte Wörterbücher**: Ausbau der `DE_BIAS_MAP` zur Erkennung weiterer Diskriminierungsformen.
* **Ollama-Integration**: Migration auf vollständig lokale Modelle für erhöhte Datensouveränität.
* **Batch-Modus**: Parallele Verarbeitung mehrerer Objekte statt sequenziellem Single-Item-Picking.
* **Feedback-Loop**: Rückspeisung manuell korrigierter Schlagworte zur Prompt-Optimierung.

---

## 8. Anpassung (Customization)

* **LLM-Endpunkt**: `YOUR_LLM_ENDPOINT` in den Workflow-JSONs durch eigenen Endpunkt ersetzen.
* **Analyse-Fokus**: Anpassung des System-Prompts in `01a_caption_parallel.md` ändert die Bildbeschreibung.
* **Klassifizierung**: Die 11 Cluster-Definitionen im Prompt `02_kustos_generator.md` sind modifizierbar.
* **Audit-Regeln**: Erweiterung des Fehlerklassen-Katalogs im Prompt `04_senior_auditor.md`.
* **Bias-Filter**: Die `DE_BIAS_MAP` im Node `Parse_LLM3_and_Debias` (Tagging_Sub.json) ist erweiterbar.
* **SeaTable-Spalten**: Spaltennamen sind in den n8n-Nodes konfigurierbar; Vorlage in `templates/`.
