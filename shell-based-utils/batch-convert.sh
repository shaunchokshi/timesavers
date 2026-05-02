#!/bin/bash

# Usage: lit [options] [command]

# OSS document parsing tool (supports PDF, DOCX, XLSX, images, and more)

# Options:
#  -V, --version                                   output the version number
#  -h, --help                                      display help for command

# Commands:
#   parse [options] <file>                          Parse a document file (PDF, DOCX, XLSX, PPTX, images, etc.)
#   screenshot [options] <file>                     Generate screenshots of PDF pages
#   batch-parse [options] <input-dir> <output-dir>  Parse multiple documents in batch mode
#   help [command]                                  display help for command

source $ANSI_COLORS
TESSDATA_PREFIX="${HOME}/.local/tessdata"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIT_HELPER="$SCRIPT_DIR/lit-pdf-to-md.py"
XLSX_HELPER="$SCRIPT_DIR/xlsx-helper.py"

ensure_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi
    echo "Homebrew not found."
    read -e -p "Install Homebrew now from https://brew.sh? [y/N]: " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        command -v brew >/dev/null 2>&1
    else
        return 1
    fi
}

install_liteparse_via_brew() {
    brew tap run-llama/liteparse && brew install llamaindex-liteparse
}

ensure_liteparse() {
    if command -v lit >/dev/null 2>&1; then
        return 0
    fi

    echo
    echo "liteparse (lit) not found in PATH."
    echo "  1) Install liteparse via Homebrew (recommended)"
    echo "  2) Provide path to an existing 'lit' binary"
    echo "  3) Install Homebrew first, then liteparse"
    read -e -p "Choose [1/2/3]: " choice

    case "$choice" in
        1)
            command -v brew >/dev/null 2>&1 || { echo "Homebrew not found. Re-run and pick option 3."; return 1; }
            install_liteparse_via_brew || return 1
            ;;
        2)
            read -e -p "Full path to 'lit' binary: " lit_path
            if [ ! -x "$lit_path" ]; then
                echo "Not executable: $lit_path"
                return 1
            fi
            export PATH="$(dirname "$lit_path"):$PATH"
            ;;
        3)
            ensure_homebrew || return 1
            install_liteparse_via_brew || return 1
            ;;
        *)
            echo "Invalid choice."
            return 1
            ;;
    esac

    if ! command -v lit >/dev/null 2>&1; then
        echo "liteparse still not available; aborting."
        return 1
    fi
    echo "liteparse ready: $(command -v lit)"
}

echo "Common file extensions' formats that will work for INPUT:"
echo "md (markdown)"
echo "txt (textfile)"
echo "csv"
echo "odt"
echo "html"
echo "docx"
echo "pdf  (routed through liteparse — JSON intermediate preserves layout)"
echo "xlsx (routed through openpyxl helper — csv/tsv emit one file per sheet,"
echo "      md/json combine all sheets, others go via markdown → pandoc)"
echo "This is not an exhaustive list - to get all INPUT formats, run:"
echo "pandoc --list-input-formats"

# Set the input and output file extensions
read -e -p "File extension (format) of current files (convert FROM):" input_format

if [[ "$input_format" == "markdown" || "$input_format" == "md" ]]; then
    input_format=markdown
    input_ext=md
else
    input_ext=$input_format
fi

echo "Common output formats for OUTPUT:"
echo "pdf, md (markdown), docx, odt, html (html4/5), json, asciidoc, txt, rtf, pptx"
echo "xlsx (only from csv/tsv/md input — md is parsed leniently, every pipe-table"
echo "      becomes a sheet named after the preceding ## heading or Sheet1, Sheet2, ...)"
echo "This is not an exhaustive list - to get all OUTPUT formats, run:"
echo "pandoc --list-output-formats"

read -e -p "Desired file extension (format) of files (convert TO):" output_format

if [[ "$output_format" == "markdown" || "$output_format" == "md" ]]; then
    output_format=markdown
    output_ext=md
else
    output_ext=$output_format
fi

# PDF input requires liteparse + helper
if [[ "$input_format" == "pdf" ]]; then
    if [[ "$output_format" == "pdf" ]]; then
        echo "pdf → pdf is a no-op. Aborting."
        exit 0
    fi
    if [ ! -f "$LIT_HELPER" ]; then
        echo "Helper not found at $LIT_HELPER"
        exit 1
    fi
    ensure_liteparse || exit 1
fi

# XLSX input requires openpyxl + helper
if [[ "$input_format" == "xlsx" ]]; then
    if [[ "$output_format" == "xlsx" ]]; then
        echo "xlsx → xlsx is a no-op. Aborting."
        exit 0
    fi
    if [ ! -f "$XLSX_HELPER" ]; then
        echo "Helper not found at $XLSX_HELPER"
        exit 1
    fi
    if ! python3 -c "import openpyxl" 2>/dev/null; then
        echo "Python module 'openpyxl' is required for xlsx input."
        echo "Install with one of:"
        echo "  pip install openpyxl"
        echo "  pip3 install openpyxl"
        echo "  brew install python-openpyxl"
        exit 1
    fi
fi

# XLSX output is only valid from tabular sources (csv/tsv/md). pandoc cannot
# write xlsx, so anything else is rejected up front rather than failing later.
if [[ "$output_format" == "xlsx" ]]; then
    case "$input_format" in
        csv|tsv|markdown)
            ;;
        xlsx)
            : # already handled above
            ;;
        *)
            echo "Output format xlsx is only supported from csv, tsv, or markdown input."
            echo "Got input_format=$input_format. For pdf, convert pdf → md first, sanity-check the tables, then md → xlsx."
            exit 1
            ;;
    esac
    if [ ! -f "$XLSX_HELPER" ]; then
        echo "Helper not found at $XLSX_HELPER"
        exit 1
    fi
    if ! python3 -c "import openpyxl" 2>/dev/null; then
        echo "Python module 'openpyxl' is required for xlsx output."
        echo "Install with one of:"
        echo "  pip install openpyxl"
        echo "  pip3 install openpyxl"
        echo "  brew install python-openpyxl"
        exit 1
    fi
fi

workdir="$(pwd)"
read -e -i "$workdir" -p "Enter path for files' directory:" workdir

read -e -p "Recurse into subdirectories? [y/N]: " recurse_choice
if [[ "$recurse_choice" =~ ^[Yy]$ ]]; then
    find_depth=()
else
    find_depth=(-maxdepth 1)
fi

# set -evx  # stop on error, verbose, and print expanded commands
# set -ex # stop on error and print expanded commands
set -e #stop on error

convert_file() {
    local input_file="$1"
    if [ ! -f "$input_file" ]; then
        echo "File not found: $input_file"
        return
    fi

    local filename=$(basename "$input_file" .$input_ext)
    local outdir=$(dirname "$input_file")
    local output_file="$outdir/$filename.$output_ext"

    if [ -f "$output_file" ]; then
        echo "Skipping $input_file – output file already exists: $output_file"
        return
    fi

    if [[ "$output_format" == "xlsx" ]]; then
        # csv/tsv/md → xlsx via xlsx-helper. Other inputs were rejected above.
        local from_fmt="${input_format/markdown/md}"
        python3 "$XLSX_HELPER" "$input_file" --from "$from_fmt" --to xlsx --out "$output_file"
        echo "Converted ($from_fmt → xlsx) $input_file to $output_file"
        return
    fi

    if [[ "$input_format" == "pdf" ]]; then
        local tmp_json tmp_md
        tmp_json=$(mktemp -t liteparse-json.XXXXXX)
        tmp_md=$(mktemp -t liteparse-md.XXXXXX)
        lit parse "$input_file" --format json -o "$tmp_json" --quiet
        python3 "$LIT_HELPER" "$tmp_json" > "$tmp_md"

        if [[ "$output_format" == "markdown" ]]; then
            mv "$tmp_md" "$output_file"
        else
            pandoc --pdf-engine=typst -f markdown -t "$output_format" "$tmp_md" -o "$output_file"
            rm -f "$tmp_md"
        fi
        rm -f "$tmp_json"
        echo "Converted (pdf via liteparse) $input_file to $output_file"
    elif [[ "$input_format" == "xlsx" ]]; then
        case "$output_format" in
            csv|tsv)
                # Multi-sheet workbooks emit "${stem}__{SheetName}.${ext}" — the
                # generic "$output_file" check above only catches the single-sheet
                # case, so re-check for the suffixed variant here.
                shopt -s nullglob
                local existing=("$outdir/${filename}__"*."$output_ext")
                shopt -u nullglob
                if [ ${#existing[@]} -gt 0 ]; then
                    echo "Skipping $input_file – multi-sheet outputs exist (e.g. ${existing[0]})"
                    return
                fi
                python3 "$XLSX_HELPER" "$input_file" --to "$output_format" --out "$outdir"
                echo "Converted (xlsx) $input_file → $outdir/${filename}{,__<sheet>}.${output_ext}"
                ;;
            markdown|json)
                python3 "$XLSX_HELPER" "$input_file" --to "${output_format/markdown/md}" --out "$output_file"
                echo "Converted (xlsx) $input_file to $output_file"
                ;;
            *)
                local tmp_md
                tmp_md=$(mktemp -t xlsx-md.XXXXXX)
                python3 "$XLSX_HELPER" "$input_file" --to md --out "$tmp_md"
                pandoc --pdf-engine=typst -f markdown -t "$output_format" "$tmp_md" -o "$output_file"
                rm -f "$tmp_md"
                echo "Converted (xlsx via markdown) $input_file to $output_file"
                ;;
        esac
    else
        pandoc --pdf-engine=typst -f "$input_format" -t "$output_format" "$input_file" -o "$output_file"
        echo "Converted $input_file to $output_file"
    fi
}

cd "$workdir"
IFS=$'\n'
declare -a paths=($(find "${workdir}" "${find_depth[@]}" -name "*.${input_ext}"))
unset IFS

for i in "${paths[@]}"; do
    convert_file "$i"
done
