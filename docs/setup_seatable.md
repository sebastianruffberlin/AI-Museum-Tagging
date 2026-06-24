# 📊 SeaTable Setup: Datenbank-Struktur

> **Version: 2.0 | Stand: 24.Juni 2026**
> Änderungen gegenüber v1.0: Tabellenname `tags_gemini` → `tags_gemini_2.5_pro`, neue Audit-Spalten (`audit1`–`audit5`), neue Felder `confidence`, `hinweis`, `status2`, `config`, Spalte `Image` → `Bildlink`.

Damit die n8n-Workflows korrekt mit SeaTable kommunizieren können, müssen zwei Tabellen mit exakt definierten Spaltennamen angelegt werden.

> [!TIP]
> **Vorgefertigte CSV-Templates nutzen**
> Im Repository liegen bereits zwei fertige Dateien für dich bereit:
> 1. `template_metadata.csv` (Für die Quelltabelle)
> 2. `template_tags_gemini.csv` (Für die Zieltabelle)
>
> Lade diese Dateien herunter und importiere sie direkt in deine SeaTable Base.

---

## 1. Tabelle: `metadata` (Die Datenquelle)

Diese Tabelle enthält deine ursprünglichen Objektdaten. n8n scannt diese Tabelle nach Zeilen, bei denen das Feld `processed` leer ist oder nicht den Wert `ok` enthält.

> [!NOTE]
> **Checkliste nach dem Import (`metadata`)**
>
> | Spaltenname | Empfohlener Datentyp | Beschreibung |
> | :--- | :--- | :--- |
> | **Inv Nr** | Text | Primärschlüssel (Eindeutige Inventarnummer). |
> | **Bildlink** | URL | Link zum Objektbild für die Vision-KI. |
> | **Titel** | Text | Der historische Titel des Objekts. |
> | **Beschreibung** | Text | Vorhandene Metadaten oder Beschreibungstexte. |
> | **processed** | Auswahl | Setze diese Spalte in SeaTable auf "Einzelauswahl". |
> | **newest** | Text | Wird vom Workflow automatisch gesetzt (z. B. `ok_1.3`). Nicht manuell befüllen. |

---

## 2. Tabelle: `tags_gemini_2.5_pro` (Der Zielspeicher)

In diese Tabelle schreibt n8n für jedes generierte und validierte Schlagwort eine eigene Zeile. Sie dient als flaches Archiv für alle Audits und GND-Matches.

> [!NOTE]
> **Checkliste nach dem Import (`tags_gemini_2.5_pro`)**
>
> | Spaltenname | Empfohlener Datentyp | Beschreibung |
> | :--- | :--- | :--- |
> | **parent_id** | Text | Verknüpfung zur `Inv Nr` des Quellobjekts. |
> | **cluster** | Auswahl | Setze auf "Einzelauswahl" (z. B. Objekttyp, Farbe_Nuancen). |
> | **schlagwort** | Text | Das finale Schlagwort. |
> | **status** | Auswahl | Setze auf "Einzelauswahl" (green, yellow, red). |
> | **gnd_id** | Text | Die verifizierte ID aus der GND. |
> | **gnd_name** | Text | Der offizielle Vorzugsbenenner-Name laut GND. |
> | **confidence** | Text | Konfidenz des GND-Abgleichs (high, medium, low, no_match). |
> | **hinweis** | Text | Kritischer Hinweis des Senior-Auditors (LLM3). |
> | **llm2** | Text | Begründung des Kustos-Generators (LLM2). |
> | **llm3** | Text | Audit-Urteil des Senior-Auditors (LLM3). |
> | **llm4** | Text | Begründung des GND-Referees (LLM4). |
> | **audit1** | Text | Audit-Dimension: Relevance Check. |
> | **audit2** | Text | Audit-Dimension: Vision Check. |
> | **audit3** | Text | Audit-Dimension: Syntax Check. |
> | **audit4** | Text | Audit-Dimension: Sovereignty Check. |
> | **audit5** | Text | Audit-Dimension: Museo Check. |
> | **status2** | Auswahl | Protokoll-Status: Open Access, Restricted oder Sensitive. |
> | **config** | Text (lang) | Automatisch befüllt: Versions- und Modell-Konfiguration des Workflows. |

---

## 🚀 Schritt-für-Schritt Import

1. **Datei herunterladen**: Lade die `template_metadata.csv` und `template_tags_gemini.csv` aus diesem Repo herunter.
2. **Import in SeaTable**: Klicke in deiner SeaTable Base auf `Tabelle hinzufügen` → `CSV-Datei importieren`.
3. **Datentypen anpassen**: SeaTable erkennt beim Import alles als Text. Ändere die Spalten `processed`, `cluster`, `status` und `status2` manuell auf den Typ **Einzelauswahl**, um die farbige Markierung in der UI zu nutzen.
4. **API-Token**: Erstelle in den Base-Einstellungen einen API-Token mit Schreibrechten und hinterlege diesen in deinen n8n-Credentials.
