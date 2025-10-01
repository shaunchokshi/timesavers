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
    
    # Replace problematic ASCII characters with underscores
    # This includes: spaces, brackets, special chars [ # % & ! @ $ ^ * ( ) / ? ' " ; : > < , = { } ]
    local sanitized=$(echo "$filename" | sed 's/[ #%&!@$^*()/?'"'"'";:><,={}\[\]/]/_/g')
    
    # Replace non-ASCII characters with timestamp
    # Use a more portable method to detect non-ASCII characters
    local temp_file=$(mktemp)
    echo "$sanitized" > "$temp_file"
    
    # Check if file contains non-ASCII characters by comparing byte count
    local byte_count=$(wc -c < "$temp_file")
    local char_count=$(wc -m < "$temp_file")
    
    rm "$temp_file"
    
    # If byte count != char count, there are non-ASCII characters
    if [ "$byte_count" -ne "$char_count" ]; then
        # Replace non-ASCII characters with timestamp
        sanitized=$(echo "$sanitized" | sed "s/[^\x00-\x7F]/${timestamp}/g")
    fi
    
    # Remove multiple consecutive underscores and replace with single underscore
    sanitized=$(echo "$sanitized" | sed 's/__*/_/g')
    
    # Remove leading/trailing underscores (but keep them if they're part of the original name structure)
    # Only remove if they were added by our replacement
    sanitized=$(echo "$sanitized" | sed 's/^_*//; s/_*$//')
    
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
