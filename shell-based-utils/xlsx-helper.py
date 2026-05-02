#!/usr/bin/env python3
"""Convert XLSX worksheets to CSV / TSV / Markdown / JSON.

CSV / TSV outputs are per-sheet: one file per worksheet, written into the
directory passed via --out. Multi-sheet workbooks use "{stem}__{SheetName}.{ext}";
single-sheet workbooks use "{stem}.{ext}".

Markdown and JSON outputs are combined: one file with each sheet rendered as
an H2 section (markdown) or an entry in a "sheets" array (json). Pass --out
as a file path, or omit it to write to stdout.

Usage:
  python3 xlsx-helper.py book.xlsx --to csv --out ./out
  python3 xlsx-helper.py book.xlsx --to md  --out book.md
  python3 xlsx-helper.py book.xlsx --to md  > book.md
  python3 xlsx-helper.py book.xlsx --to md  --sheet Summary
"""
import argparse
import csv
import json
import sys
from pathlib import Path

try:
    from openpyxl import load_workbook
except ImportError:
    sys.stderr.write(
        "error: openpyxl not installed.\n"
        "  pip install openpyxl       (or pip3 / pipx / your venv of choice)\n"
    )
    sys.exit(2)


def cell_to_str(value):
    if value is None:
        return ""
    # whole-number floats render as "3" not "3.0"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def sheet_rows(ws):
    rows = [[cell_to_str(c) for c in row] for row in ws.iter_rows(values_only=True)]
    while rows and not any(c.strip() for c in rows[-1]):
        rows.pop()
    return rows


def slugify_sheet(name):
    bad = '<>:"/\\|?*'
    cleaned = "".join("_" if c in bad else c for c in name)
    cleaned = cleaned.strip().replace(" ", "_")
    return cleaned or "Sheet"


def md_escape(s):
    return s.replace("|", "\\|").replace("\n", " ")


def to_markdown(sheets):
    parts = []
    for name, rows in sheets:
        parts.append(f"## {name}")
        parts.append("")
        if not rows:
            parts.append("*(empty)*")
            parts.append("")
            continue
        ncols = max(len(r) for r in rows)
        rows = [r + [""] * (ncols - len(r)) for r in rows]
        header, body = rows[0], rows[1:]
        parts.append("| " + " | ".join(md_escape(c) for c in header) + " |")
        parts.append("|" + "|".join("---" for _ in range(ncols)) + "|")
        for r in body:
            parts.append("| " + " | ".join(md_escape(c) for c in r) + " |")
        parts.append("")
    return "\n".join(parts).rstrip() + "\n"


def to_json(sheets):
    payload = {"sheets": [{"name": n, "rows": r} for n, r in sheets]}
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def write_delimited(sheets, out_dir, stem, ext, delim):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    multiple = len(sheets) > 1
    for name, rows in sheets:
        suffix = f"__{slugify_sheet(name)}" if multiple else ""
        path = out_dir / f"{stem}{suffix}.{ext}"
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f, delimiter=delim)
            for r in rows:
                w.writerow(r)
        written.append(path)
    return written


def select_sheets(wb, sheet_arg):
    names = wb.sheetnames
    if sheet_arg is None:
        return names
    if sheet_arg.isdigit():
        idx = int(sheet_arg)
        if 0 <= idx < len(names):
            return [names[idx]]
    if sheet_arg in names:
        return [sheet_arg]
    sys.stderr.write(
        f"error: sheet '{sheet_arg}' not found. Available: {names}\n"
    )
    sys.exit(1)


def main():
    p = argparse.ArgumentParser(
        description="Convert XLSX worksheets to CSV/TSV/Markdown/JSON."
    )
    p.add_argument("input", help="path to .xlsx file")
    p.add_argument("--to", choices=["csv", "tsv", "md", "json"], required=True)
    p.add_argument(
        "--out",
        help="output path: directory for csv/tsv, file for md/json (omit for stdout)",
    )
    p.add_argument(
        "--sheet",
        help="restrict to a single sheet (name or 0-based index)",
    )
    args = p.parse_args()

    src = Path(args.input)
    if not src.is_file():
        sys.stderr.write(f"error: file not found: {src}\n")
        return 1

    wb = load_workbook(src, read_only=True, data_only=True)
    sheet_names = select_sheets(wb, args.sheet)
    sheets = [(n, sheet_rows(wb[n])) for n in sheet_names]

    if args.to in ("csv", "tsv"):
        if not args.out:
            sys.stderr.write(f"error: --out DIR is required for --to {args.to}\n")
            return 1
        delim = "," if args.to == "csv" else "\t"
        for path in write_delimited(sheets, args.out, src.stem, args.to, delim):
            sys.stderr.write(f"wrote {path}\n")
        return 0

    text = to_markdown(sheets) if args.to == "md" else to_json(sheets)
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
