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

if [[ "$input_format" == "markdown" ]]; then
    input_ext=md
else
    input_ext=$input_format
fi

echo "Common output formats for OUTPUT:"
echo "pdf, md (markdown), docx, odt, html (html4/5), json, asciidoc, txt, rtf, pptx"
echo "This is not an exhaustive list - to get all OUTPUT formats, run:"
echo "pandoc --list-output-formats"

read -e -p "Desired file extension (format) of files (convert TO):" output_format

if [[ "$output_format" == "markdown" ]]; then
    output_ext=md
else
    output_ext=$output_format
fi

workdir="$(pwd)"
read -e -i "$workdir" -p "Enter path for files' directory:" workdir

# Loop through all files with the input extension in the current directory
 set -evx # e = stop on first error; v = verbose, print each line before execute; x =  print each line with the subs/vars/shell expansions before executing
convert_file() {
        #for file in *."$input_ext"; do
            # Check if the file exists
            if [ -f "$i" ]; then
            # Get the filename without the extension
                filename=`basename "$i" .$input_ext`
            # Convert the file using pandoc
                pandoc -f $input_format -t $output_format "$i" -o "$filename.$output_ext"
                echo "Converted $i to $filename.$output_ext"
            else
                echo "File not found: $i"
            fi
        #done
}

cd "$workdir"
IFS=$'\n'
declare -a paths=($(find "${workdir}" -name "*.${input_ext}"))
unset IFS
for i in "${paths[@]}"; do
        convert_file
done
