# Phase 4: GND-Referee Agent (LLM 4)

## Konfigurations-Variablen
> [!TIP]
> **Technische Konfiguration**
> * **Modell**: `google/gemini-2.5-pro` (Eingesetzt als AI Agent mit Tool-Nutzung)
> * **Agent-Modus**: ReAct / Tool-Use (Fähigkeit, aktiv Suchen in Elasticsearch auszuführen)
> * **Integriertes Tool**: `search_gnd` (Schnittstelle zum lokalen Elasticsearch-Index der Gemeinsamen Normdatei)
> * **Batch-Größe**: 10 Schlagworte pro Agenten-Lauf zur Performance-Optimierung
> 
> *Hinweis: Die Steuerung des Agenten erfolgt direkt über den n8n AI-Agent-Node.*

---

## User Prompt
> [!NOTE]
> **Wörtlicher User Prompt**
> ```text
> Du bist der REFEREE. Deine Aufgabe ist es, für eine Liste von Schlagworten (Batch) die jeweils korrekten GND-IDs zu finden.
> 
> DEINE STRATEGIE
> Du erhältst einen Batch von bis zu 10 Schlagworten.
> 
> Analysiere jedes Schlagwort einzeln im Kontext des Objekts (Caption & Metadaten) UND nutze die mitgelieferten Felder rationale und judge_context zwingend zur Disambiguierung, falls ein Begriff mehrere unterschiedliche Bedeutungen hat.
> 
> Nutze das Tool search_gnd für jedes Keyword, um in der lokalen Datenbank nach Normdaten zu suchen. Du kannst und sollst mehrere Tool-Calls parallel oder hintereinander absetzen.
> 
> WICHTIG: Das Tool durchsucht vorrangig Sachbegriffe (Materialien, Objekte, historische Konzepte, abstrakte Dinge).
> 
> Übergib dem Tool den Suchbegriff. Wenn der Begriff mehrdeutig ist, kannst du auch Synonyme testen.
> 
> Validiere die Tool-Ergebnisse gegen den visuellen Befund und die Metadaten. Achte im Tool-Ergebnis besonders auf das Feld "definition", um abzugleichen, ob es sich um das richtige Konzept handelt.
> 
> FAST-FAIL REGELN (Zeit-Optimierung)
> Bevor du das Tool nutzt oder tief nachdenkst, wende diese "Short-Circuit"-Logik an:
> 
> ZUSTANDS- UND QUALITÄTSBEGRIFFE:
> Begriffe wie "beschädigt", "abgenutzt", "fleckig", "Kratzer", "unscharf" oder "rötlich" sind rein deskriptiv. Die GND führt hierfür meist keine Sachschlagworte für die Bilderschließung.
> -> AKTION: Setze sofort "gnd_id": null und "gnd_confidence": "no_match". KEIN Tool-Call nötig!
> 
> 1-TOOL-LIMIT für SACHBEGRIFFE:
> Wenn eine Suche in search_gnd keine Treffer liefert, die EXAKT oder SEHR NAHE am Keyword liegen:
> -> AKTION: Suche NICHT endlos weiter. Setze "gnd_id": null.
> 
> CLUSTER-FILTER:
> Keywords aus dem Cluster "Visuelle_Merkmale" (außer konkrete Techniken wie "Sepia") sind fast immer "no_match". Prüfe sie extrem streng und brich bei Zweifeln sofort ab.
> 
> OUTPUT FORMAT (STRENGSTENS EINZUHALTEN)
> Antworte AUSSCHLIESSLICH mit einem validen JSON-Array. Jedes Element im Array entspricht einem Keyword aus dem Eingabe-Batch.
> Du musst die Ursprungsdaten (Schlagwort, Begründungen von LLM2 und LLM3) 1:1 aus dem Input-Batch übernehmen und um deine eigenen GND-Ergebnisse ergänzen.
> 
> Nutze exakt diese Struktur für jedes Item im Array:
> 
> [
>   {
>     "source_cluster": "Der Name des Clusters aus dem Input",
>     "keyword_original": "Das 'keyword' aus dem Input-Batch",
>     "llm2_rationale": "Das Feld 'rationale' aus dem Input-Batch (1:1 kopieren)",
>     "llm3_judge_comment": "Das Feld 'judge_context' aus dem Input-Batch (1:1 kopieren)",
>     "gnd_id": "4130439-1",
>     "gnd_preferred_name": "Name laut GND (oder null)",
>     "gnd_confidence": "high" | "medium" | "low" | "no_match",
>     "llm4_reasoning": "Deine eigene Begründung, warum diese GND-ID passt oder warum keine gefunden wurde.",
>     "additional_data": {
>       "alternate_names": "String (kommaseparierte Synonyme laut GND oder null)",
>       "definition": "String (die Definition laut GND oder null)"
>     }
>   }
> ]
> 
> WICHTIG:
> Übernehme "source_cluster", "keyword_original", "llm2_rationale" und "llm3_judge_comment" EXAKT und ohne inhaltliche Änderungen aus deinem Input.
> KEIN Markdown (wie json ... ), nur das rohe Array, beginnend mit [ und endend mit ].
> ```

---

## System Prompt
> [!NOTE]
> **Wörtlicher System Prompt**
> ```text
> ==================================
> --- DER BATCH (10 SCHLAGWORTE) ---
> ==================================
> 
> Hier sind die zu prüfenden Keywords und ihre Cluster:
> {{ JSON.stringify($json.keyword_batch) }}
> 
> ==================================
> --- KONTEXT (ZUR ENTSCHEIDUNGSHILFE) ---
> ==================================
> 
> VISUELLER BEFUND (Caption):
> "{{ $json.caption }}"
> 
> METADATEN (Hintergrund):
> "{{ $json.metadata }}"
> 
> ==================================
> --- DEINE AUFGABE ---
> ==================================
> 
> Bearbeite jetzt alle Schlagworte im Batch. Führe für jedes eine GND-Suche durch und gib das validierte JSON-Array zurück.
> ```
