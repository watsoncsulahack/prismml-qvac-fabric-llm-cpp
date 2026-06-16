#!/usr/bin/env python3
"""Flatten llama-bench sweep artifacts into CSV/TSV and ODS tables."""

from __future__ import annotations

import argparse
import csv
import html
import json
import mimetypes
import os
from pathlib import Path
import zipfile


ODS_MIMETYPE = "application/vnd.oasis.opendocument.spreadsheet"


FIELDS = [
    "phase",
    "model_label",
    "model_type",
    "model_filename",
    "model_size",
    "model_n_params",
    "rc",
    "seconds",
    "build_commit",
    "backends",
    "gpu_info",
    "devices",
    "n_threads",
    "n_gpu_layers",
    "flash_attn",
    "type_k",
    "type_v",
    "n_batch",
    "n_ubatch",
    "n_prompt",
    "n_gen",
    "n_depth",
    "avg_ts",
    "stddev_ts",
    "avg_ns",
    "test_time",
    "source_json",
    "command",
]


def read_summary(summary_path: Path) -> list[dict[str, str]]:
    with summary_path.open(newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def flatten(summary_path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for summary in read_summary(summary_path):
        base = {
            "phase": summary.get("phase", ""),
            "model_label": summary.get("model_label", ""),
            "model_filename": summary.get("model", ""),
            "rc": summary.get("rc", ""),
            "seconds": summary.get("seconds", ""),
            "source_json": summary.get("output", ""),
            "command": summary.get("command", ""),
        }
        output = summary.get("output", "")
        path = Path(output) if output else None
        if not path or not path.exists():
            rows.append(base)
            continue
        try:
            records = json.loads(path.read_text())
        except json.JSONDecodeError:
            rows.append(base)
            continue
        if not isinstance(records, list):
            rows.append(base)
            continue
        for record in records:
            if not isinstance(record, dict):
                continue
            row = dict(base)
            for field in FIELDS:
                if field in record:
                    row[field] = record[field]
            rows.append(row)
    return rows


def write_delimited(path: Path, rows: list[dict[str, object]], delimiter: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, delimiter=delimiter)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in FIELDS})


def ods_cell(value: object) -> str:
    text = "" if value is None else str(value)
    try:
        number = float(text)
    except ValueError:
        return (
            '<table:table-cell office:value-type="string">'
            f"<text:p>{html.escape(text)}</text:p>"
            "</table:table-cell>"
        )
    if text.strip() == "":
        return '<table:table-cell office:value-type="string"><text:p/></table:table-cell>'
    return (
        f'<table:table-cell office:value-type="float" office:value="{number}">'
        f"<text:p>{html.escape(text)}</text:p>"
        "</table:table-cell>"
    )


def write_ods(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    table_rows = []
    table_rows.append(
        "<table:table-row>"
        + "".join(ods_cell(field) for field in FIELDS)
        + "</table:table-row>"
    )
    for row in rows:
        table_rows.append(
            "<table:table-row>"
            + "".join(ods_cell(row.get(field, "")) for field in FIELDS)
            + "</table:table-row>"
        )

    content = f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  office:version="1.2">
  <office:body>
    <office:spreadsheet>
      <table:table table:name="llama-bench">
        {''.join(table_rows)}
      </table:table>
    </office:spreadsheet>
  </office:body>
</office:document-content>
"""
    manifest = f"""<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest
  xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
  manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="{ODS_MIMETYPE}"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
</manifest:manifest>
"""
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("mimetype", ODS_MIMETYPE, compress_type=zipfile.ZIP_STORED)
        zf.writestr("content.xml", content)
        zf.writestr("META-INF/manifest.xml", manifest)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("summary", type=Path)
    parser.add_argument("--out-prefix", type=Path)
    args = parser.parse_args()

    rows = flatten(args.summary)
    prefix = args.out_prefix or args.summary.with_suffix("")
    write_delimited(prefix.with_suffix(".csv"), rows, ",")
    write_delimited(prefix.with_suffix(".tsv"), rows, "\t")
    write_ods(prefix.with_suffix(".ods"), rows)


if __name__ == "__main__":
    mimetypes.add_type(ODS_MIMETYPE, ".ods")
    main()
