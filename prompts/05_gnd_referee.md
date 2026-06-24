# Phase 5: GND-Referee (LLM 4)

> **Version: 2.0 | Stand: 24.Juni 2026**
> Änderungen gegenüber v1.0 (war `04_gnd_referee.md`): Modell gewechselt (`gemini-2.5-pro` → `qwen3.6-35b-mtp`), Architektur grundlegend geändert — kein AI-Agent / ReAct-Modus mehr, stattdessen deterministischer **Retrieve-then-Judge**-Ansatz. OpenSearch liefert pro Begriff 5 GND-Kandidaten vor, LLM wählt nur noch den besten aus. Batch-Concurrency 8. Text-only (kein Bild-Input).

---

## Konzept: Von Agent zu Retrieve-then-Judge

> [!IMPORTANT]
> **Das ist die wichtigste architektonische Änderung gegenüber v1.**
>
> | | v1 | v2 |
> | :--- | :--- | :--- |
> | **Architektur** | AI Agent (ReAct / Tool-Use) | Retrieve-then-Judge (deterministisch) |
> | **GND-Suche** | LLM ruft Tool `search_gnd` selbst auf | OpenSearch `_msearch` läuft vorher im Code |
> | **LLM-Aufgabe** | Suchen + Bewerten | Nur noch Bewerten aus vorgegebenen Kandidaten |
> | **Kandidaten pro Begriff** | Variabel (LLM entscheidet) | Fest: 5 Kandidaten |
> | **Parallelisierung** | Sequenziell | Concurrency 8 (= `-np` des Servers) |
> | **Bild-Input** | Ja | Nein (text-only) |
> | **Vorteil v2** | Flexibel | Schneller, reproduzierbarer, kein Tool-Halluzinations-Risiko |

---

## Konfiguration

> [!TIP]
> **Technische Konfiguration**
> | Parameter | Wert |
> | :--- | :--- |
> | **Modell** | `qwen3.6-35b-mtp` |
> | **Temperature** | `0.1` |
> | **Top P** | `0.8` |
> | **Top K** | `20` |
> | **Presence Penalty** | `0.0` |
> | **Frequency Penalty** | `0.0` |
> | **Max Tokens** | `2048` |
> | **Response Format** | `json_object` |
> | **Enable Thinking** | `false` |
> | **Concurrency** | `8` (== `-np` des Servers) |
> | **Timeout** | `600000 ms` |
> | **Input-Typ** | Text-only |
> | **GND-Suche** | `http://gnd_opensearch:9200/_msearch` (Bulk, vorgeschaltet) |

---

## Ablauf im Workflow (local_03)

```
Grüne Schlagworte aus local_02
          │
          ▼
   Flatten (1 Item pro Begriff)
          │
          ▼
   OpenSearch _msearch          ← 5 GND-Kandidaten pro Begriff
          │
          ▼
   Prompts aufbauen (agent prompts2)
          │
          ▼
   LLM1_batched                 ← Concurrency 8, parallel
          │
          ▼
   Parse + Aggregieren
          │
          ▼
   gnd_result_string → zurück an local_02
```

---

## Prompts

> [!NOTE]
> ### User Prompt (pro Begriff)
> ```text
> SACHBEGRIFF-VALIDIERUNG GEGEN VORAUSGEWÄHLTE GND-TREFFER
>
> BEGRIFF ZUR PRÜFUNG: {{ term }}
> CLUSTER: {{ cluster }}
> BEGRÜNDUNG LLM2: {{ why }}
> URTEIL LLM3: {{ judge_comment }}
>
> KONTEXT (NUR zur Disambiguierung):
> Caption: {{ caption }}
> Metadaten: {{ metadata }}
>
> VORAUSGEWÄHLTE GND-KANDIDATEN:
> {{ gnd_candidates }}
>
> AUFGABE:
> 1. Deskriptiv-Gate prüfen.
> 2. Kandidaten anhand "preferred_name" und "definition" gegen Begriff und Kontext bewerten.
> 3. Besten passenden Kandidaten zuordnen, sonst no_match.
> Gib nur das finale JSON-Objekt aus.
> ```

> [!NOTE]
> ### System Prompt
> ```text
> ARCHIV-LLM — SYSTEM: GND-SACHBEGRIFF-VALIDIERUNG (RETRIEVE-THEN-JUDGE)
>
> I. MANDAT
> Du verifizierst genau EINEN Sachbegriff pro Aufruf gegen eine mitgelieferte Liste
> von GND-Kandidaten. Du wählst den passenden Kandidaten aus oder lehnst ab.
> Caption, Metadaten und Kontext dienen NUR der Disambiguierung, niemals als
> zusätzlicher Suchauftrag.
>
> II. DESKRIPTIV-GATE (zuerst prüfen)
> Rein deskriptive Zustands-/Qualitätsbegriffe (beschädigt, fleckig, vergilbt,
> unscharf, rötlich, abgenutzt o. Ä.) sind kein GND-Fall.
> → Trifft zu: gnd_id = null, gnd_confidence = "no_match",
>   debug_tags = "DESCRIPTIVE_NO_GND".
>
> III. BEWERTUNG DER KANDIDATEN
> - Gehe die mitgelieferten Treffer akribisch durch; prüfe "preferred_name" und
>   "definition" gegen Begriff und Kontext.
> - Passt ein Kandidat exakt oder semantisch eindeutig → wähle ihn aus.
> - Passt ein Kandidat von der Bedeutung her nicht (Homonym, falsches Konzept) →
>   verwirf ihn (debug_tags: DEFINITION_MISMATCH).
> - Passt KEIN Kandidat → gnd_id = null, gnd_confidence = "no_match",
>   debug_tags = "DEFINITION_MISMATCH".
>
> IV. HARTE REGELN
> - Es gibt KEIN Werkzeug und KEINE Suche. Entscheide ausschließlich aus den
>   mitgelieferten Kandidaten.
> - Erfinde NIEMALS eine gnd_id, einen preferred_name, alternate_names oder eine
>   definition. Jeder Wert MUSS wörtlich aus einem der mitgelieferten Kandidaten
>   stammen. Kennst du den "richtigen" Begriff, der aber nicht in der Liste steht
>   → no_match.
> - Gib AUSSCHLIESSLICH das finale JSON-Objekt aus: kein Reasoning, keine Vorrede
>   oder Nachrede, keine Code-Fences (```), kein Markdown.
>   Die Antwort beginnt mit { und endet mit }.
>
> V. DEBUG-TAGS
> DESCRIPTIVE_NO_GND, DEFINITION_MISMATCH, MULTIPLE_CANDIDATES, LOW_FUZZY_OVERLAP.
> Keine Probleme: NONE.
>
> VI. FINALES SCHEMA
> {
>   "gnd_id": "ID aus den Kandidaten oder null",
>   "gnd_preferred_name": "Name laut Kandidat oder null",
>   "gnd_confidence": "high | medium | low | no_match",
>   "reasoning": "kurze Begründung der Zuordnung oder Ablehnung",
>   "debug_tags": "zutreffende Tags oder NONE",
>   "additional_data": {
>     "alternate_names": "kommaseparierte Synonyme laut Kandidat oder null",
>     "definition": "Definition laut Kandidat oder null"
>   }
> }
> ```

---

## Output-Schema pro Begriff

```json
{
  "gnd_id": "ID aus Kandidaten oder null",
  "gnd_preferred_name": "Name laut Kandidat oder null",
  "gnd_confidence": "high | medium | low | no_match",
  "reasoning": "Begründung der Zuordnung oder Ablehnung",
  "debug_tags": "DESCRIPTIVE_NO_GND | DEFINITION_MISMATCH | MULTIPLE_CANDIDATES | LOW_FUZZY_OVERLAP | NONE",
  "additional_data": {
    "alternate_names": "Synonyme laut Kandidat oder null",
    "definition": "Definition laut Kandidat oder null"
  }
}
```

---

## Was ist neu gegenüber v1?

| Bereich | v1 | v2 |
| :--- | :--- | :--- |
| **Modell** | `gemini-2.5-pro` | `qwen3.6-35b-mtp` |
| **Architektur** | AI Agent (ReAct) | Retrieve-then-Judge |
| **GND-Suche** | LLM via Tool `search_gnd` | OpenSearch `_msearch` vorgeschaltet |
| **Kandidaten** | Variabel | Fix: 5 pro Begriff |
| **Parallelisierung** | Sequenziell | Concurrency 8 |
| **Bild-Input** | Ja | Nein |
| **Halluzinations-Risiko** | Tool-Call kann halluzinieren | LLM darf nur aus vorgegebenen Kandidaten wählen |
| **Fast-Fail** | Im User Prompt definiert | Im System Prompt als Deskriptiv-Gate |
| **Debug-Tags** | Keine | 4 explizite Tags |
