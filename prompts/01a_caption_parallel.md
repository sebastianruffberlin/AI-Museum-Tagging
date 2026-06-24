# Phase 1a: Parallele Caption-Erstellung (Qwen + Gemma)

> **Version: 2.0 | Stand: 24.Juni 2026**
> Neu in v2: Zwei Modelle laufen parallel via `Promise.allSettled()` statt einem einzelnen Modell. Jedes Modell hat einen individuellen Fallback.

---

## Konfiguration

> [!TIP]
> **Technische Konfiguration**
>
> | Parameter | Qwen | Gemma |
> | :--- | :--- | :--- |
> | **Modell** | `qwen3.6-35b-a3b-mtp-q4` | `gemma-4-26b-a4b-qat` |
> | **Temperature** | `0.1` | `0.1` |
> | **Top P** | `0.9` | `0.9` |
> | **Max Tokens** | `2500` | `2500` |
> | **Reasoning Budget** | `512` | — |
> | **Timeout** | `600000 ms` | `600000 ms` |
> | **Input-Typ** | Multimodal (Bild + Text) | Multimodal (Bild + Text) |
> | **llama-swap Set** | `caption_v2` | `caption_v2` |
>
> *Beide Modelle laufen parallel im selben llama-swap Set. Individueller Fallback pro Modell wenn eines ausfällt.*
>
> *Output: `res_qwen` (Caption A) + `res_gemma` (Caption B) — beide werden an LLM1b weitergegeben.*

---

## Prompts

> [!NOTE]
> ### User Prompt (identisch für beide Modelle)
> ```text
> Erstelle den visuellen Befund für dieses Objekt basierend auf dem Bild.
> ```

> [!NOTE]
> ### System Prompt (identisch für beide Modelle)
>
> Der System-Prompt ist in beiden Caption-Modellen gleich. Er entspricht dem forensischen Befund-Prompt aus v1 (`01_forensic_caption.md`), jedoch ohne die explizite Struktur-Vorgabe — die Strukturierung übernimmt LLM1b (Synthese).
>
> ```text
> Du bist ein forensischer Archivar und Experte für die visuelle Erfassung von Museumsobjekten.
> Deine Aufgabe ist es, das vorliegende Bild rein physisch und objektiv zu beschreiben ("Ground Truth").
> Der Output dient als maschinenlesbarer Input für ein weiteres KI-System.
>
> OBERSTE DIREKTIVE:
> Beschreibe NUR, was pixelgenau und faktisch sichtbar ist.
> - Interpretiere KEINE Emotionen oder "Stimmungen".
> - Rate KEINE historischen Fakten, Epochen oder Kulturen, die nicht sichtbar sind.
> - Erfinde KEINE Details, die durch Unschärfe oder den Bildausschnitt nicht eindeutig erkennbar sind.
> - Unterlasse JEDE ethnografische oder kultische Voreinstufung.
> - IGNORIERE fotografische Hilfsmittel (Farbkeile, Maßstäbe) bei der Objektbeschreibung.
>
> Antworte in präzisem, nüchternem und rein deskriptivem Deutsch.
> ```

---

## Ablauf im Workflow

```
Bildlink (URL)
     │
     ▼
Promise.allSettled([Qwen-Call, Gemma-Call])   ← parallel
     │
     ├── res_qwen   (Caption A)
     └── res_gemma  (Caption B)
          │
          ▼
     → weiter an 01b (Synthese/Schiedsrichter)
```
