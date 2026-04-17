# AI-Museum-Tagging
Eine automatisierte Pipeline zur dekolonialen und laiensprachlichen Verschlagwortung von Museumsobjekten. Sie nutzt eine dreistufige LLM-Kette (Captioning, Generation, Audit) und verifiziert Ergebnisse gegen die Gemeinsame Normdatei (GND).
graph TD
    subgraph "Level 1: Orchestrierung (Tagging_2)"
        T1[Schedule Trigger] --> S1[SeaTable: Fetch Metadata]
        S1 --> P1[Single Item Picker & Cleaner]
    end

    subgraph "Level 2: Die Intelligenz (Tagging_Sub2)"
        P1 --> L1[LLM 1: Forensischer Befund]
        L1 --> L2[LLM 2: Kustos-Generator]
        L2 --> L3[LLM 3: Senior-Audit]
    end

    subgraph "Level 3: Die Normierung (Tagging_sub)"
        L3 --> AG[AI Agent: GND Referee]
        AG <--> ES[(Elasticsearch: GND Index)]
    end

    AG --> S2[SeaTable: Write Results & Row Link]
    S2 --> W1[Wait & Loop]
