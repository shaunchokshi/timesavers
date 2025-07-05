#!/bin/python

## example for cli based use:

# python convert_css_colors.py theme.css --format rgb --output theme --scss --tailwind --html

## example for interactive script with prompts for user input:

# python convert_css_colors.py




import re
import argparse
from pathlib import Path
from colorsys import rgb_to_hls, hls_to_rgb

# --- Color detection patterns ---
HSL_PATTERN = re.compile(r'^(\d+(\.\d+)?)\s+(\d+(\.\d+)?%)\s+(\d+(\.\d+)?%)$')
HEX_PATTERN = re.compile(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$')
RGB_PATTERN = re.compile(r'^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$')
VAR_DECL_PATTERN = re.compile(r'\s*(--[\w-]+):\s*([^;]+);')

# --- Detection and conversion ---
def detect_color_format(value):
    value = value.strip()
    if HSL_PATTERN.match(value): return 'hsl'
    if HEX_PATTERN.match(value): return 'hex'
    if RGB_PATTERN.match(value): return 'rgb'
    return 'unknown'

def hex_to_rgb(hex_str):
    hex_str = hex_str.lstrip('#')
    if len(hex_str) == 3: hex_str = ''.join([c * 2 for c in hex_str])
    return tuple(int(hex_str[i:i+2], 16) for i in (0, 2, 4))

def parse_hsl(hsl_str):
    h, s, l = hsl_str.strip().split()
    return float(h), float(s.strip('%')) / 100, float(l.strip('%')) / 100

def hsl_to_rgb_tuple(hsl_str):
    h, s, l = parse_hsl(hsl_str)
    r, g, b = hls_to_rgb(h / 360, l, s)
    return int(r * 255), int(g * 255), int(b * 255)

def rgb_to_hex(rgb): return f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}"
def rgb_to_rgb_string(rgb): return f"rgb({rgb[0]}, {rgb[1]}, {rgb[2]})"

def rgb_to_hsl_string(rgb):
    r, g, b = [x / 255 for x in rgb]
    h, l, s = rgb_to_hls(r, g, b)
    return f"hsl({round(h * 360)}, {round(s * 100)}%, {round(l * 100)}%)"

# --- Parsing and output generators ---
def parse_color_block(css_block):
    in_comment = False
    color_vars = {}
    for line in css_block.splitlines():
        stripped = line.strip()
        if stripped.startswith("/*"): in_comment = True
        if in_comment:
            if "*/" in stripped: in_comment = False
            continue
        if "/*" in stripped and "*/" in stripped: continue
        match = VAR_DECL_PATTERN.match(line)
        if match:
            var, val = match.groups()
            if detect_color_format(val.strip()) != 'unknown':
                color_vars[var] = val.strip()
    return color_vars

def generate_css_block(color_dict, fmt='hex'):
    out = []
    for var, val in color_dict.items():
        color = convert_to_all_formats(val)
        out.append(f"  {var}: {color[fmt]};")
        for alt_fmt in ('hex', 'rgb', 'hsl'):
            if alt_fmt != fmt:
                out.append(f"  /* {var}: {color[alt_fmt]}; */")
    return '\n'.join(out)

def generate_scss_block(color_dict, fmt='hex'):
    return '\n'.join(f"${var.replace('--', '')}: {convert_to_all_formats(val)[fmt]};"
                     for var, val in color_dict.items())

def generate_tailwind_block(color_dict, fmt='hex'):
    return '\n'.join(
        f".bg-[{var}] {{ background-color: {convert_to_all_formats(val)[fmt]}; }}\n"
        f".text-[{var}] {{ color: {convert_to_all_formats(val)[fmt]}; }}"
        for var, val in color_dict.items()
    )

def generate_html_preview(color_dict, fmt='hex'):
    rows = []
    for var, val in color_dict.items():
        color = convert_to_all_formats(val)[fmt]
        rows.append(f"""<div style="display:flex;align-items:center;margin-bottom:8px;">
  <div style="width:30px;height:30px;background:{color};margin-right:10px;border:1px solid #ccc;"></div>
  <code>{var}: {color}</code>
</div>""")
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8">
<title>Color Preview</title></head><body style="font-family:sans-serif;padding:20px;">
<h2>CSS Color Preview ({fmt.upper()})</h2>{''.join(rows)}</body></html>"""

def convert_to_all_formats(value):
    fmt = detect_color_format(value)
    if fmt == 'hsl':
        rgb = hsl_to_rgb_tuple(value)
    elif fmt == 'hex':
        rgb = hex_to_rgb(value)
    elif fmt == 'rgb':
        rgb = tuple(map(int, re.findall(r'\d+', value)))
    else:
        return {"hex": "#000000", "rgb": "rgb(0,0,0)", "hsl": "hsl(0, 0%, 0%)"}
    return {
        "hex": rgb_to_hex(rgb),
        "rgb": rgb_to_rgb_string(rgb),
        "hsl": rgb_to_hsl_string(rgb)
    }

# --- Write outputs ---
def write_outputs(base_path: str, css=None, scss=None, tailwind=None, html=None):
    outputs = []
    if css:
        Path(f"{base_path}.css").write_text(css, encoding="utf-8")
        outputs.append(f"{base_path}.css")
    if scss:
        Path(f"{base_path}.scss").write_text(scss, encoding="utf-8")
        outputs.append(f"{base_path}.scss")
    if tailwind:
        Path(f"{base_path}.tailwind.css").write_text(tailwind, encoding="utf-8")
        outputs.append(f"{base_path}.tailwind.css")
    if html:
        Path(f"{base_path}.html").write_text(html, encoding="utf-8")
        outputs.append(f"{base_path}.html")
    return outputs

# --- Interactive Fallback ---
def prompt_input():
    mode = input("Enter 'file' or 'block': ").strip().lower()
    if mode == 'file':
        path = input("File path: ").strip()
        return Path(path).read_text(encoding="utf-8")
    elif mode == 'block':
        print("Paste CSS block (end with empty line):")
        lines = []
        while True:
            try:
                line = input()
                if line.strip() == "": break
                lines.append(line)
            except EOFError:
                break
        return "\n".join(lines)
    else:
        return ""

def prompt_flags():
    fmt = input("Preferred format? (hex/rgb/hsl): ").strip().lower()
    out = input("Base output filename (omit extension): ").strip()
    gen_scss = input("Generate SCSS? (y/n): ").strip().lower().startswith("y")
    gen_tw = input("Generate Tailwind CSS? (y/n): ").strip().lower().startswith("y")
    gen_html = input("Generate HTML preview? (y/n): ").strip().lower().startswith("y")
    return fmt, out, gen_scss, gen_tw, gen_html

# --- Main ---
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="?", type=Path, help="CSS file")
    parser.add_argument("--format", choices=["hex", "rgb", "hsl"], default=None)
    parser.add_argument("--output", type=str)
    parser.add_argument("--scss", action="store_true")
    parser.add_argument("--tailwind", action="store_true")
    parser.add_argument("--html", action="store_true")
    args = parser.parse_args()

    if args.input:
        css_text = args.input.read_text(encoding="utf-8")
        fmt = args.format or "hex"
        out = args.output or "colors"
        scss, tw, html = args.scss, args.tailwind, args.html
    else:
        css_text = prompt_input()
        fmt, out, scss, tw, html = prompt_flags()

    color_vars = parse_color_block(css_text)
    css_block = generate_css_block(color_vars, fmt)
    scss_block = generate_scss_block(color_vars, fmt) if scss else None
    tw_block = generate_tailwind_block(color_vars, fmt) if tw else None
    html_block = generate_html_preview(color_vars, fmt) if html else None

    if out:
        files = write_outputs(out, css_block, scss_block, tw_block, html_block)
        print("✅ Wrote output files:")
        for f in files:
            print(" -", f)
    else:
        print(css_block)

if __name__ == "__main__":
    main()
