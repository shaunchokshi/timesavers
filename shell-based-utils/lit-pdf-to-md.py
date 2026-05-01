#!/usr/bin/env python3
"""Convert LiteParse JSON output to GitHub-flavored Markdown.

Reads JSON from a file path argument or stdin; writes Markdown to stdout.

Heuristics:
  - Lines: textItems with similar y are clustered into one line.
  - Headings: line max fontSize / body-median fontSize → #, ##, ###.
  - Bullets: line starting with bullet glyph becomes "- ".
  - Paragraph breaks: vertical gap > ~1.8 * median line height.
  - Tables: not detected yet (TODO — needs column-cluster pass).

Usage:
  lit parse doc.pdf --format json -o doc.json --quiet
  python3 lit-pdf-to-md.py doc.json > doc.md
  # or:
  cat doc.json | python3 lit-pdf-to-md.py > doc.md
"""
import json
import sys
from statistics import median

BULLET_GLYPHS = ("•", "●", "▪", "·", "○", "▸", "▶")


def cluster_lines(items, y_tol):
    if not items:
        return []
    items_sorted = sorted(items, key=lambda it: (it["y"], it["x"]))
    lines = []
    current = [items_sorted[0]]
    for it in items_sorted[1:]:
        if abs(it["y"] - current[0]["y"]) <= y_tol:
            current.append(it)
        else:
            lines.append(sorted(current, key=lambda i: i["x"]))
            current = [it]
    lines.append(sorted(current, key=lambda i: i["x"]))
    return lines


def line_text(line):
    return " ".join(it["text"].strip() for it in line if it["text"].strip())


def line_max_font(line):
    return max(it["fontSize"] for it in line)


def starts_with_bullet(text):
    if not text:
        return False
    if text[0] in BULLET_GLYPHS:
        return True
    return text.startswith("- ") or text.startswith("* ")


def normalize_bullet(text):
    if text and text[0] in BULLET_GLYPHS:
        return "- " + text[1:].lstrip()
    return text


def page_to_md(page, body_font):
    items = page.get("textItems", [])
    if not items:
        return ""

    heights = [it["height"] for it in items if it.get("height")]
    med_h = median(heights) if heights else 10.0
    y_tol = med_h * 0.5

    lines = cluster_lines(items, y_tol)

    out = []
    prev_bottom = None
    for line in lines:
        text = line_text(line)
        if not text:
            continue
        font = line_max_font(line)
        ratio = font / body_font if body_font else 1.0
        line_y = line[0]["y"]

        if prev_bottom is not None and (line_y - prev_bottom) > med_h * 1.2:
            out.append("")
        prev_bottom = line_y + med_h

        if ratio >= 1.6:
            out.append(f"# {text}")
        elif ratio >= 1.3:
            out.append(f"## {text}")
        elif ratio >= 1.12:
            out.append(f"### {text}")
        elif starts_with_bullet(text):
            out.append(normalize_bullet(text))
        else:
            out.append(text)

    return "\n".join(out)


def main():
    if len(sys.argv) > 1 and sys.argv[1] != "-":
        with open(sys.argv[1]) as f:
            data = json.load(f)
    else:
        data = json.load(sys.stdin)

    pages = data.get("pages", [])
    all_sizes = [
        it["fontSize"]
        for p in pages
        for it in p.get("textItems", [])
        if it.get("fontSize")
    ]
    body_font = median(all_sizes) if all_sizes else 10.0

    parts = []
    for page in pages:
        md = page_to_md(page, body_font)
        if md:
            parts.append(md)

    sys.stdout.write("\n\n".join(parts) + "\n")


if __name__ == "__main__":
    main()
