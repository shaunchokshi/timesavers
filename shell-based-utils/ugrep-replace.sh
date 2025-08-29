read -r -p "Enter the search pattern (what to find): " PATTERN
read -r -p "Enter the replacement text (plain text): " REPLACEMENT
#read -r -p "Enter the path to search/replace in: " SEARCH_PATH
SEARCH_PATH="$(pwd)"
read -e -i "$SEARCH_PATH" -p "Enter path to search/replace in:" SEARCH_PATH


