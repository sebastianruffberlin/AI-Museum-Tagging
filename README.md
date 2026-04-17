# 🏛️ AI Museum Tagging Workflow

Dieses Projekt bietet eine automatisierte Pipeline zur **ethisch sensiblen und laienverständlichen Verschlagwortung** von Museumsobjekten. Durch eine vierstufige KI-Kette (Chain of Verification) werden historische Metadaten und Bildanalysen kombiniert, gegen dekoloniale Biases geprüft und mit der **Gemeinsamen Normdatei (GND)** verknüpft.

---

## 🛰️ System-Architektur

Das System ist modular aufgebaut und verteilt die Last auf drei spezialisierte n8n-Workflows:

```mermaid
graph TD
    subgraph "Level 1: Orchestrierung (Tagging_2)"
        T1[Schedule Trigger] --> S1[SeaTable: Fetch Metadata]
        S1 --> P1[Single Item Picker & Cleaner]
    end

    subgraph "Level 2: Die Intelligenz (Tagging_Sub2)"
        P1 --> L1[LLM 1: Forensischer Befund]
        L1 --> L2[LLM 2: Kustos-Generator]
        L2 --> L3[LLM 3: Senior-Audit]
        L3 --> DB[De-Bias & Flattening]
    end

    subgraph "Level 3: Die Normierung (Tagging_sub)"
        DB --> AG[AI Agent: GND Referee]
        AG <--> ES[(Elasticsearch: GND Index)]
    end

    AG --> S2[SeaTable: Write Results & Row Link]
    S2 --> W1[Wait & Loop]
