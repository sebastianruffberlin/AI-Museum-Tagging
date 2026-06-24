#!/usr/bin/env python3
"""
GND Sachbegriffe Import Script
Importiert GND-Sachbegriffe aus dem DNB-Dump in OpenSearch.

Index:    gnd_sachbegriffe
Filter:   nur @type: SubjectHeading
Felder:   gnd_id, preferred_name, alternate_names, broader_term,
          broader_generic, related_term, def

Voraussetzungen:
  pip install opensearch-py tqdm --break-system-packages
  authorities-gnd-sachbegriff_lds.jsonld.gz im selben Verzeichnis

Stand: 24. Juni 2026
Referenz: 207.505 Dokumente auf Produktionsserver
"""

import gzip
import json
import sys
from pathlib import Path
from opensearchpy import OpenSearch, helpers
from tqdm import tqdm

OPENSEARCH_HOST = "localhost"
OPENSEARCH_PORT = 9200
INDEX_NAME      = "gnd_sachbegriffe"
CHUNK_SIZE      = 1000
INPUT_FILE      = "authorities-gnd-sachbegriff_lds.jsonld.gz"

client = OpenSearch(
    hosts=[{"host": OPENSEARCH_HOST, "port": OPENSEARCH_PORT}],
    use_ssl=False,
    verify_certs=False,
)

def create_index():
    if client.indices.exists(index=INDEX_NAME):
        client.indices.delete(index=INDEX_NAME)
        print(f"  Alter Index '{INDEX_NAME}' gelöscht.")

    mapping = {
        "settings": {"index": {"number_of_shards": 1, "number_of_replicas": 0}},
        "mappings": {
            "properties": {
                "gnd_id":          {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
                "preferred_name":  {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
                "alternate_names": {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
                "def":             {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
                "broader_term":    {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
                "broader_generic": {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
                "related_term":    {"type": "text", "fields": {"keyword": {"type": "keyword", "ignore_above": 256}}},
            }
        }
    }
    client.indices.create(index=INDEX_NAME, body=mapping)
    print(f"✓ Index '{INDEX_NAME}' angelegt")

def get_text(val):
    """Extrahiert Text aus JSON-LD Werten (string, dict mit @value, oder Liste)."""
    if isinstance(val, list):
        return " | ".join(get_text(v) for v in val if v)
    elif isinstance(val, dict):
        return val.get("@value", "")
    return str(val)

def doc_generator():
    with gzip.open(INPUT_FILE, "rt", encoding="utf-8") as f:
        for line in tqdm(f, desc="Importiere", unit=" Zeilen"):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            # Nur SubjectHeading verarbeiten — exakt wie im Original-Script
            gnd_type = record.get("@type", [])
            if isinstance(gnd_type, str):
                gnd_type = [gnd_type]
            if "SubjectHeading" not in gnd_type:
                continue

            gnd_uri = record.get("@id", "")
            if "gnd/" not in gnd_uri:
                continue
            gnd_id = gnd_uri.split("gnd/")[-1]

            pref_name_raw = record.get("preferredNameForTheSubjectHeading")
            if not pref_name_raw:
                continue
            preferred_name = get_text(pref_name_raw)
            if not preferred_name:
                continue

            alt_names_raw = record.get("variantNameForTheSubjectHeading")
            alternate_names = get_text(alt_names_raw) if alt_names_raw else None

            def_raw = record.get("definition")
            definition = get_text(def_raw) if def_raw else None

            broader_term_raw = record.get("broaderTermGeneral") or record.get("broaderTerm")
            broader_term = get_text(broader_term_raw) if broader_term_raw else None

            broader_generic_raw = record.get("broaderTermGeneric")
            broader_generic = get_text(broader_generic_raw) if broader_generic_raw else None

            related_raw = record.get("relatedTerm")
            related_term = get_text(related_raw) if related_raw else None

            doc = {k: v for k, v in {
                "gnd_id":          gnd_id,
                "preferred_name":  preferred_name,
                "alternate_names": alternate_names,
                "def":             definition,
                "broader_term":    broader_term,
                "broader_generic": broader_generic,
                "related_term":    related_term,
            }.items() if v}

            yield {
                "_index":  INDEX_NAME,
                "_id":     gnd_id,
                "_source": doc,
            }

if __name__ == "__main__":
    if not Path(INPUT_FILE).exists():
        print(f"Fehler: {INPUT_FILE} nicht gefunden.")
        sys.exit(1)

    print("=== GND Sachbegriffe Import ===")
    create_index()

    success, errors = helpers.bulk(
        client,
        doc_generator(),
        chunk_size=CHUNK_SIZE,
        raise_on_error=False,
    )

    count = client.count(index=INDEX_NAME)["count"]
    print(f"\n✓ Import abgeschlossen")
    print(f"  Importiert:  {success}")
    print(f"  Fehler:      {len(errors)}")
    print(f"  Im Index:    {count} Dokumente")
    print(f"  Referenz:    207.505 auf Produktionsserver")
