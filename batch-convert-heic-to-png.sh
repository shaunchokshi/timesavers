#!/bin/bash

# Set the input and output file extensions
input_ext="heic"
output_ext="png"
command="heic-cli"
workdir="/Users/shaun/iCloud-drive/image-playground-saves"


# Loop through all files with the input extension in the current directory
for file in "$workdir"/*."$input_ext"; do
  # Check if the file exists
  if [ -f "$file" ]; then
    # Get the filename without the extension
    filename=$(basename "$file" .$input_ext)

    # Convert the file using the appropriate command, replacing with your desired conversion tool

    $command < $file > $filename.$output_ext

    # Example using ffmpeg to convert from mp4 to avi:
    # ffmpeg -i "$file" "$filename.$output_ext"

    echo "Converted $file to $filename.$output_ext"
  else
    echo "File not found: $file"
  fi
done
