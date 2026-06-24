# Phase 3: Repair-Kustos (LLM Repair)

> **Version: 2.0 | Stand: 24.Juni 2026**
> Neu in v2: Dieser Schritt existierte in v1 nicht. Er verarbeitet die gelben (formal behebbaren) Schlagworte aus LLM3 und versucht, sie in GND-taugliche Begriffe zu reparieren. Reparierte Begriffe werden grün und gehen in den GND-Abgleich. Nicht reparierbare Begriffe bleiben gelb und werden verworfen.

---

## Einordnung im Workflow

```
LLM3 Output
     │
     ├── Grüne Begriffe  ──────────────────────────────→ GND-Abgleich (local_03)
     │
     ├── Gelbe Begriffe  → Repair-Prep → Repair-LLM → Repair-Post
     │                                                      │
     │                                        ┌─────────────┴─────────────┐
     │                                        │                           │
     │                                   Reparierbar               Nicht reparierbar
     │                                   → Grün                    → bleibt Gelb
     │                                   → GND-Abgleich            → verworfen
     │
     └── Rote Begriffe   ──────────────────────────────→ verworfen
```

---

## Konfiguration

> [!TIP]
> **Technische Konfiguration**
> | Parameter | Wert |
> | :--- | :--- |
> | **Modell** | `gemma-4-12b-qat` |
> | **Temperature** | `0.1` |
> | **Top P** | `0.9` |
> | **Max Tokens** | `2000` |
> | **Enable Thinking** | `false` |
> | **Response Format** | `json_schema` (strict, name: `repair_result`) |
> | **Input-Typ** | Text-only (master_caption + Metadaten + gelbe Terme) |
>
> *Kein Bild-Input in diesem Schritt — reine Formalreparatur.*

---

## Prompts

> [!NOTE]
> ### System Prompt
> ```text
> Du bist ein knapper Reparatur-Kustos für GND-orientierte Museums-Schlagworte
> (Stadtmuseum Berlin).
> Du erhältst gelbe (formal behebbare) Schlagworte mit dem Reparaturhinweis eines Prüfers
> (judge_comment) plus Objektkontext.
> Der judge_comment ist ein VORSCHLAG, den du übernehmen ODER überstimmen darfst,
> wenn er nicht trägt.
>
> REGELN PRO TERM:
> - Ziel: ein einzelner GND-tauglicher Sachbegriff im Singular (Nomen).
> - Plural → Singular (Bücher → Buch).
> - Adjektiv → Substantiv NUR wenn ein echtes Sachnomen entsteht (gepflastert → Pflaster).
> - Unzerlegtes Kompositum → sinnvolle Teile (Soldatenalltag → ["Soldat", "Alltag"]).
>   Feststehende Fachbegriffe (Dampfschiff) bleiben.
> - Material-Kompositum: das Sachnomen ist der Tail (Holzgriff → Griff, Metallsteg → Steg).
>   Reines Material (Holz, Papier, Karton) ist NICHT reparierbar.
> - Fehlende Laien-Brücke: Fachbegriff behalten UND Alltags-Oberbegriff ergänzen
>   (Tschako → ["Tschako", "Hut"]).
> - Du darfst pro Term mehrere Terme ausgeben (Brücke, Kompositum-Teile).
> - ABLEHNEN (repairable: false, repaired_terms: []) wenn nur eine Mehrwort-Phrase möglich
>   wäre ("spitz zulaufende Form") oder kein sauberer Sachbegriff entsteht.
>   Lieber ablehnen als ein schlechtes Schlagwort erzeugen.
> - Erfinde keine inhaltliche Neuaussage. Repariere nur Form/Begriff, nicht die Evidenz.
>
> Antworte ausschließlich im vorgegebenen JSON-Schema.
> ```

> [!NOTE]
> ### User Prompt
> ```text
> Objektkontext und zu reparierende gelbe Terme:
> """
> {
>   "master_caption": "{{ master_caption }}",
>   "metadaten": "{{ context_data_string }}",
>   "zu_reparieren": [
>     {
>       "original": "{{ term }}",
>       "cluster": "{{ cluster }}",
>       "why": "{{ why }}",
>       "judge_comment": "{{ judge_comment }}",
>       "fehlerklassen": ["{{ fehlerklassen }}"]
>     }
>   ]
> }
> """
> Gib für JEDEN Term einen Eintrag in "repairs" zurück
> (gleiche Reihenfolge, gleicher cluster, gleiches original).
> ```

---

## Output-Schema (JSON Schema, strict)

```json
{
  "repairs": [
    {
      "original": "Originalterm aus Input",
      "cluster": "Cluster aus Input",
      "repairable": true,
      "repaired_terms": ["Reparierter Begriff 1", "Reparierter Begriff 2"]
    }
  ]
}
```

> [!NOTE]
> **Verarbeitungslogik nach dem LLM-Call (Repair-Post):**
> - `repairable: true` + Terme vorhanden → Terme werden Bias-gefiltert, dedupliziert und als **grün** in `payload_valid` übernommen
> - `repairable: false` oder keine Terme → Begriff bleibt **gelb** und landet in `payload_rejected`
> - Datierungen (Regex) und Duplikate werden auch nach der Reparatur noch abgefangen

---

## Fehlerklassen die zur gelben Einstufung führen

| Fehlerklasse | Bedeutung | Typische Reparatur |
| :--- | :--- | :--- |
| `PLURAL` | Begriff im Plural | Singular-Form |
| `ADJEKTIV` | Eigenschaftswort statt Nomen | Substantivierung |
| `KOMPOSITUM` | Unzerlegtes Ad-hoc-Kompositum | Zerlegung in Teile |
| `FEHLENDE_BRUECKE` | Fachbegriff ohne Laien-Oberbegriff | Oberbegriff ergänzen |
| `MATERIAL_KOMPOSITUM` | Material-Prefix + Sachnomen | Nur Sachnomen behalten |
