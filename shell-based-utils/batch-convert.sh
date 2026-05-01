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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIT_HELPER="$SCRIPT_DIR/lit-pdf-to-md.py"

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

    if [[ "$input_format" == "pdf" ]]; then
        local tmp_json tmp_md
        tmp_json=$(mktemp -t liteparse-json.XXXXXX)
        tmp_md=$(mktemp -t liteparse-md.XXXXXX)
        lit parse "$input_file" --format json -o "$tmp_json" --quiet
        python3 "$LIT_HELPER" "$tmp_json" > "$tmp_md"

        if [[ "$output_format" == "markdown" ]]; then
            mv "$tmp_md" "$output_file"
        else
            pandoc -f markdown -t "$output_format" "$tmp_md" -o "$output_file"
            rm -f "$tmp_md"
        fi
        rm -f "$tmp_json"
        echo "Converted (pdf via liteparse) $input_file to $output_file"
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
