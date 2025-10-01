#!/bin/bash

# Script to replace problematic characters with underscores in filenames
# Replaces: spaces, special chars [ # % & ! @ $ ^ * ( ) / ? ' " ; : > < , = { } ], and non-ASCII characters
# Usage: ./rename_spaces.sh

echo "Renaming files with problematic characters to use underscores..."

# Counter for renamed files
count=0

# Function to sanitize filename
sanitize_filename() {
    local filename="$1"
    
    # Generate unique timestamp for non-ASCII characters
    local timestamp=$(date '+%Y-%m-%d_%H%M%S%N')
    
    # Use awk to handle character replacement - much cleaner than sed
    local sanitized=$(echo "$filename" | awk -v timestamp="$timestamp" '
    {
        result = ""
        has_non_ascii = 0
        
        for (i = 1; i <= length($0); i++) {
            char = substr($0, i, 1)
            ascii_code = ord(char)
            
            # Check if character is ASCII (0-127)
            if (ascii_code < 0 || ascii_code > 127) {
                # Non-ASCII character - mark that we found one
                has_non_ascii = 1
                # For now, skip non-ASCII characters, we will handle them later
            } else {
                # ASCII character - check if it is problematic
                if (char == " " || char == "#" || char == "%" || char == "&" || 
                    char == "!" || char == "@" || char == "$" || char == "^" || 
                    char == "*" || char == "(" || char == ")" || char == "/" || 
                    char == "?" || char == "\047" || char == "\042" || char == ";" || 
                    char == ":" || char == ">" || char == "<" || char == "," || 
                    char == "=" || char == "{" || char == "}" || char == "[" || 
                    char == "]") {
                    result = result "_"
                } else {
                    result = result char
                }
            }
        }
        
        # If we found non-ASCII characters, append timestamp
        if (has_non_ascii) {
            if (result == "") {
                result = timestamp
            } else {
                result = result "_" timestamp
            }
        }
        
        print result
    }
    
    function ord(c) {
        return int(sprintf("%d", c))
    }')
    
    # Clean up multiple consecutive underscores
    sanitized=$(echo "$sanitized" | awk '{gsub(/__+/, "_"); print}')
    
    # Remove leading/trailing underscores
    sanitized=$(echo "$sanitized" | awk '{gsub(/^_+|_+$/, ""); print}')
    
    # Ensure the filename doesn't start with a dot (hidden file)
    if [[ "$sanitized" == .* ]]; then
        sanitized="file_$sanitized"
    fi
    
    # Ensure filename is not empty
    if [[ -z "$sanitized" ]]; then
        sanitized="unnamed_file_${timestamp}"
    fi
    
    echo "$sanitized"
}

# Loop through all files in current directory
for file in *; do
    # Check if file exists and is not a directory
    if [ -f "$file" ]; then
        # Get sanitized filename
        new_name=$(sanitize_filename "$file")
        
        # Check if filename actually needs to be changed
        if [[ "$file" != "$new_name" ]]; then
            # Check if target file already exists
            if [ -f "$new_name" ]; then
                echo "Warning: '$new_name' already exists, skipping '$file'"
            else
                # Rename the file
                mv "$file" "$new_name"
                echo "Renamed: '$file' -> '$new_name'"
                ((count++))
            fi
        fi
    fi
done

echo "Renaming complete. $count files renamed."
