#!/bin/bash

source $ANSI_COLORS

echo "Common file extensions' formats that will work for INPUT:"
echo "md (markdown)"
echo "txt (textfile)"
echo "csv"
echo "odt"
echo "html"
echo "docx"
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

workdir="$(pwd)"
read -e -i "$workdir" -p "Enter path for files' directory:" workdir

# set -evx  # stop on error, verbose, and print expanded commands
# set -ex # stop on error and print expanded commands
set -e #stop on error

convert_file() {
    local input_file="$1"
    if [ -f "$input_file" ]; then
        local filename=$(basename "$input_file" .$input_ext)
        local outdir=$(dirname "$input_file")
        local output_file="$outdir/$filename.$output_ext"

        if [ -f "$output_file" ]; then
            echo "Skipping $input_file – output file already exists: $output_file"
        else
            pandoc --pdf-engine=typst -f "$input_format" -t "$output_format" "$input_file" -o "$output_file"
            echo "Converted $input_file to $output_file"
        fi
    else
        echo "File not found: $input_file"
    fi
}

cd "$workdir"
IFS=$'\n'
declare -a paths=($(find "${workdir}" -name "*.${input_ext}"))
unset IFS

for i in "${paths[@]}"; do
    convert_file "$i"
done
