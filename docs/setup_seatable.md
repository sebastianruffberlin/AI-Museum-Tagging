# 📊 SeaTable Setup: Datenbank-Struktur

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
> | **Image** | URL | Link zum Objektbild für die Vision-KI. |
> | **Titel** | Text | Der historische Titel des Objekts. |
> | **Beschreibung** | Text | Vorhandene Metadaten oder Beschreibungstexte. |
> | **processed** | Auswahl | Setze diese Spalte in SeaTable auf "Einzelauswahl". |
> | **context_data_string** | Formel | Kombiniert Titel + Beschreibung (siehe n8n Setup). |

---

## 2. Tabelle: `tags_gemini` (Der Zielspeicher)
In diese Tabelle schreibt n8n für jedes generierte und validierte Schlagwort eine eigene Zeile. Sie dient als flaches Archiv für alle Audits und GND-Matches.

> [!NOTE]
> **Checkliste nach dem Import (`tags_gemini`)**
> 
> | Spaltenname | Empfohlener Datentyp | Beschreibung |
> | :--- | :--- | :--- |
> | **parent_id** | Text | Mapping zur `Inv Nr` des Quellobjekts. |
> | **cluster** | Auswahl | Setze auf "Einzelauswahl" (Objekttyp, Farbe, etc.). |
> | **term** | Text | Das finale Schlagwort. |
> | **why** | Text | Die Begründung des Kustos-Generators. |
> | **status** | Auswahl | Setze auf "Einzelauswahl" (green, yellow, red). |
> | **judge_comment** | Text | Audit-Begründung des Senior-Auditors. |
> | **gnd_id** | Text | Die verifizierte ID aus der GND. |
> | **gnd_name** | Text | Der offizielle Vorzugsbildner-Name der GND. |
> | **llm4_reasoning** | Text | Begründung des Referee-Agenten. |
> | **additional_data** | Text / JSON | Zusatzinfos (Synonyme & Definition). |

---

## 🚀 Schritt-für-Schritt Import

1. **Datei herunterladen**: Lade die `template_metadata.csv` und `template_tags_gemini.csv` aus diesem Repo herunter.
2. **Import in SeaTable**: Klicke in deiner SeaTable Base auf `Tabelle hinzufügen` -> `CSV-Datei importieren`.
3. **Datentypen anpassen**: SeaTable erkennt beim Import alles als Text. Ändere die Spalten `processed`, `cluster` und `status` manuell auf den Typ **Einzelauswahl**, um die farbige Markierung in der UI zu nutzen.
4. **API-Token**: Erstelle in den Base-Einstellungen einen API-Token mit Schreibrechten und hinterlege diesen in deinen n8n-Credentials.
