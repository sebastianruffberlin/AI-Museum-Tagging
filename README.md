# 🏛️ AI Museum Tagger: Dokumentation

## 1. Beschreibung der Architektur-Idee und des Ziels
Die Grundidee dieses Projekts ist die Schaffung einer **„Decolonial Middleware“** für Museen. Ziel ist es, historische Objektdaten, die oft von Experten-Jargon und kolonialen Biases geprägt sind, automatisiert in eine moderne, laienverständliche und ethisch sensible Sprache zu transformieren. 

Die Architektur folgt dem Prinzip einer **„Chain of Verification“**: Anstatt einem einzelnen KI-Aufruf zu vertrauen, durchlaufen die Daten eine Kette von spezialisierten LLM-Instanzen (Captioning, Generation, Audit), die sich gegenseitig kontrollieren. Das Ergebnis ist eine hochwertige Verschlagwortung, die sowohl fachlich fundiert (**GND-konform**) als auch für die breite Öffentlichkeit (**Folksonomie-Ansatz**) zugänglich ist.

---

## 2. Voraussetzungen technisch & System-Versionen
Das System wurde auf folgenden Versionen erfolgreich getestet und dokumentiert (Stand: April 2026):

* **n8n:** Version **2.16.1** (Self-hosted via Docker).
* **SeaTable:** **Enterprise Edition 6.0.10**.
* **Elasticsearch:** Version **8.13** (Vektor- und Suchdatenbank für Normdaten).
* **GND-Bestand:** Datenstand vom **10.04.2026** (Importiert in Elasticsearch).
* **KI-Schnittstellen:** Zugriff auf LLMs (z. B. via OpenRouter) für **Gemini 2.5 Pro/Flash**.

---

## 3. Self-Hosting & Infrastruktur
Das System läuft vollständig isoliert in **3 Docker-Containern** auf einem gemeinsamen VPS-Host. Dies gewährleistet Datensouveränität und eine performante Verarbeitung großer Batches.

**Hardware-Spezifikationen (Empfohlenes Setup):**
* **VPS:** Hetzner CX43
* **CPU:** 8 vCPU
* **RAM:** 16 GB RAM
* **Disk:** 80 GB lokale Disk

**Container-Struktur:**
1. **n8n:** Orchestrierung, JavaScript-Logik und API-Management.
2. **SeaTable:** Lokale Instanz für Datenmanagement und Workflow-Steuerung.
3. **Elasticsearch:** Indexierung und Bereitstellung der GND-Normdaten.

---

## 4. Aufbau der Pipeline (SeaTable, n8n, Elasticsearch)
Die Pipeline verbindet drei spezialisierte Ebenen zu einem modularen Stack:
* **SeaTable** dient als primäre Datenquelle (Metadaten) und Zielspeicher für die generierten Resultate.
* **n8n** orchestriert den Prozess, bereitet Daten via JavaScript auf und steuert die spezialisierten LLM-Phasen.
* **Elasticsearch** ermöglicht dem AI Agenten den Echtzeit-Abgleich der Schlagworte mit der Gemeinsamen Normdatei (GND).

---

## 5. Beschreibung der Komponenten

### 5.1. SeaTable - Spalten und Daten
Zur Erleichterung des Setups können die Spaltenköpfe als CSV importiert werden. Die Spaltentypen müssen danach manuell angepasst werden.

**Quelltabelle (`metadata`):**
* **Inv Nr**: Text (Eindeutiger Primärschlüssel).
* **processed**: Text (Status-Flag; der Workflow sucht nach Zeilen, in denen dieser Wert nicht „ok“ ist).
* **Bildlink**: URL zum Objektbild.
* **Titel / Beschreibung**: Textfelder mit historischen Kontextinformationen.

**Zieltabelle (`tags_gemini_2.5_pro`):**
* **cluster**: Einzelauswahl (z. B. Objekttyp, Thema, Emotion, Form).
* **schlagwort**: Das final validierte Schlagwort.
* **status**: Einzelauswahl (green, yellow, red) basierend auf dem Audit-Urteil.
* **gnd_id / gnd_name**: Die verifizierten Normdaten aus der GND.
* **llm2 bis llm4**: Textfelder zur Speicherung der Begründungskette (Data Lineage).
* **audit1 bis audit5**: Detaillierte Audit-Logs zur dekolonialen Prüfung.

### 5.2. n8n - Beschreibung der Verarbeitungsschritte
* **5.2.1. Import und Splitting**: Der Workflow `Tagging_2` ruft unbearbeitete Daten ab und isoliert via Code-Node genau ein Item pro Durchlauf.
* **5.2.2. Bildbeschreibung (Captioning)**: Im Sub-Workflow `Tagging_Sub2` erstellt LLM 1 einen rein objektiven visuellen Befund („Ground Truth“).
* **5.2.3. Erstellung von Keywords**: LLM 2 generiert Schlagworte in 11 Clustern unter Berücksichtigung des „Folksonomie-Gebots“ (Brückenschlag zur Alltagssprache).
* **5.2.4. Judge LLM**: LLM 3 (Senior Auditor) prüft die Ergebnisse auf museologische Regeln wie Singular-Zwang und Material-Verbot.
* **5.2.5. De:bias**: Ein JavaScript-Node prüft Begriffe gegen eine `DE_BIAS_MAP` und bereinigt koloniale Sprache automatisch.
* **5.2.6. Weiche**: Trennung der Ergebnisse: Fehlerhafte Begriffe („red“) werden aussortiert; valide Begriffe („green/yellow“) werden weiterverarbeitet.
* **5.2.7. GND Validierung (Subflow)**: Der Workflow `Tagging_sub` verarbeitet Schlagworte in Batches von 10 via AI Agent und Elasticsearch.
* **5.2.8. Zusammenführen**: Ein zentraler Code-Node („Wedding“) harmonisiert alle Datenstränge (GND-Treffer und Audit-Ergebnisse).
* **5.2.9. Zurückschreiben**: Das System erzeugt für jedes Schlagwort eine Zeile in SeaTable, verknüpft diese via `parent_id` und setzt den Status des Objekts auf „ok“.

### 5.3. SeaTable Resultat
Das Endergebnis ist eine flache, auditierbare Liste. Zu jedem Schlagwort existiert eine lückenlose „Data Lineage“ sowie ein fünfstufiges dekoloniales Audit-Protokoll zur Nachvollziehbarkeit der KI-Entscheidungen.

---

## 6. Potential für Weiterentwicklung
* **6.1. Open Source Modelle**: Umstellung der LLM-Nodes auf lokale Modelle (z. B. via Ollama) für volle Datensouveränität.
* **6.2. Weiteres Vokabular**: Integration zusätzlicher Wörterbücher im De-bias-Node für weitere Diskriminierungsformen.

---

## 7. Variablen & Anpassung (Customization)
Das System lässt sich flexibel an verschiedene museale Kontexte anpassen:
* **7.1. Daten in SeaTable**: Spaltennamen und Tabellen-IDs können in den n8n-Nodes global angepasst werden.
* **7.2. Bildbeschreibung**: Der System-Prompt in `01_captions` kann verändert werden, um den Fokus der Analyse zu verschieben.
* **7.3. Keyword-Prompt**: Modifikation der 11 Cluster-Definitionen im Node `02_keywords`.
* **7.4. Judge-Anpassung**: Ergänzung neuer Audit-Regeln im System-Prompt von `03_evaluation`.
* **7.5. GND Agent**: Der AI Agent in `Tagging_sub` kann um Werkzeuge für weitere Normvokabulare ergänzt werden.
