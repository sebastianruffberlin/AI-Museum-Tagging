# AI Museum Tagger: Dokumentation

## 1. Projektziel und Ansatz
Dieses Projekt stellt eine **Middleware** für Museen bereit. Sie dient der automatisierten Transformation historischer Objektdaten in eine zeitgemäße, barrierearme und ethisch geprüfte Sprache. 

Der Prozess basiert auf einer **„Chain of Verification“**: Daten durchlaufen eine Sequenz spezialisierter LLM-Instanzen (Analyse, Generierung, Audit), um eine gegenseitige Validierung zu gewährleisten. Das System liefert eine Verschlagwortung, die sowohl **GND-konform** (Gemeinsame Normdatei) als auch nach dem **Folksonomie-Prinzip** (nutzerorientiert) aufgebaut ist.

---

## 2. Technische Voraussetzungen und Versionen
Das System wurde mit folgenden Komponenten getestet (Stand: April 2026):

* **n8n:** Version **2.16.1** (Self-hosted via Docker).
* **SeaTable:** **Enterprise Edition 6.0.10**.
* **Elasticsearch:** Version **8.13** (Vektor- und Suchdatenbank für Normdaten).
* **GND-Datenbestand:** Stand **10.04.2026**.
* **KI-Modelle:** **Gemini 2.5 Pro/Flash** (Anbindung via OpenRouter).

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
3. **Elasticsearch:** Bereitstellung der Normdaten für den Echtzeit-Abgleich durch den AI-Agenten.

---

## 5. Repository-Struktur

    .
    ├── prompts/                # System- & User-Prompts für LLM-Instanzen
    │   ├── 01_forensic_caption.md
    │   ├── 02_kustos_generator.md
    │   ├── 03_senior_auditor.md
    │   └── 04_gnd_referee.md
    ├── workflows/              # n8n Workflow-Exporte (JSON)
    │   ├── Tagging_Main.json
    │   └── Tagging_Sub.json
    ├── templates/              # CSV-Importvorlagen für SeaTable
    │   ├── metadata_template.csv
    │   └── results_template.csv
    ├── docs/                   # Technische Dokumentation
    │   └── setup_seatable.md
    └── README.md

---

## 6. Komponentenbeschreibung

### 6.1. SeaTable Datenstruktur
Die Tabellen müssen zur korrekten Verarbeitung folgende Felder enthalten:

**Tabelle `metadata` (Eingabe):**
* **Inv Nr**: Eindeutiger Primärschlüssel.
* **processed**: Status-Indikator (Workflow verarbeitet Zeilen ungleich „ok“).
* **Bildlink**: URL zum Objektbild.
* **Titel / Beschreibung**: Historische Kontextdaten.

**Tabelle `tags_gemini_2.5_pro` (Ausgabe):**
* **cluster**: Klassifizierung (z. B. Objekttyp, Thema, Emotion).
* **schlagwort**: Validierter Begriff.
* **status**: Audit-Bewertung (Farbskala: Grün, Gelb, Rot).
* **gnd_id / gnd_name**: Referenzierte Normdaten.
* **llm2 bis llm4**: Protokollierung der Zwischenschritte (Data Lineage).

### 6.2. n8n Verarbeitungsschritte
1. **Import & Splitting**: Abruf der Daten und Vereinzelung der Datensätze.
2. **Bildanalyse (Captioning)**: Erstellung eines objektiven visuellen Befunds durch LLM 1.
3. **Schlagwort-Generierung**: LLM 2 erstellt Keywords in 11 Clustern.
4. **Validierung (Judge LLM)**: LLM 3 prüft formale Regeln (z. B. Singular-Zwang).
5. **Bias-Filter**: Automatisierte Bereinigung diskriminierender Begriffe via `DE_BIAS_MAP` (JavaScript).
6. **Logische Weiche**: Trennung valider und fehlerhafter Datenströme.
7. **GND-Abgleich**: Batch-Verarbeitung der Schlagworte via AI-Agent gegen Elasticsearch.
8. **Daten-Aggregation**: Zusammenführung der Audit- und GND-Ergebnisse.
9. **Export**: Schreiben der Ergebnisse nach SeaTable und Statusaktualisierung.

---

## 7. Potential für Weiterentwicklung
* **Lokale LLMs**: Umstellung auf Modelle via Ollama zur Erhöhung der Datensouveränität.
* **Erweiterte Wörterbücher**: Ausbau der `DE_BIAS_MAP` zur Erkennung weiterer Diskriminierungsformen.

---

## 8. Anpassung (Customization)
* **Konfiguration**: Spaltennamen und IDs sind global in den n8n-Nodes konfigurierbar.
* **Analyse-Fokus**: Anpassung des System-Prompts in `01_captions` ändert die Bildbeschreibung.
* **Klassifizierung**: Die 11 Cluster-Definitionen im Node `02_keywords` sind modifizierbar.
* **Audit-Regeln**: Erweiterung der Validierungslogik im System-Prompt von `03_evaluation`.
