#!/bin/bash

###############################################################################
# svg-clean: Wrapper for SVG Inkscape cleaner
#
# Removes Inkscape-specific metadata and attributes from SVG files.
# Validates inputs and provides helpful error messages.
###############################################################################

set -o pipefail

# Script metadata
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/svg_inkscape_cleaner.py"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Functions
###############################################################################

show_help() {
    cat << 'EOF'
svg-clean - Remove Inkscape-specific content from SVG files

USAGE:
    svg-clean [OPTIONS] <input-file> [input-file ...]

OPTIONS:
    -o, --output FILE           Output file (only with single input file)
    -v, --verbose               Show detailed information about removed elements
    --keep-empty-defs           Preserve empty <defs> sections
    -h, --help                  Display this help message
    --version                   Display version information

DESCRIPTION:
    Removes Inkscape and Sodipodi namespace declarations, metadata elements,
    and Inkscape-specific attributes from SVG files while preserving all
    vector content (paths, circles, rectangles, etc.).

    This is useful for making SVG files compatible with strict parsers like
    laser cutting software (e.g., Gweike Glaser) that may crash on files
    containing Inkscape-specific extensions.

EXAMPLES:

    1. Clean a single SVG file in-place:
       svg-clean drawing.svg

    2. Clean and save to a new file:
       svg-clean drawing.svg -o cleaned_drawing.svg

    3. Show what will be removed (verbose mode):
       svg-clean drawing.svg -v

    4. Batch clean all SVG files in current directory:
       svg-clean *.svg

    5. Clean multiple specific files:
       svg-clean file1.svg file2.svg file3.svg

    6. Clean with verbose output and custom output:
       svg-clean input.svg -o output.svg -v

    7. Keep empty defs sections (normally removed):
       svg-clean drawing.svg --keep-empty-defs

WHAT GETS REMOVED:
    - Inkscape namespace declarations (xmlns:inkscape, xmlns:sodipodi)
    - <metadata> elements
    - All Inkscape-specific attributes (sodipodi:type, inkscape:*, etc.)
    - Empty <defs> sections containing only Inkscape content

WHAT IS PRESERVED:
    - All vector content (paths, circles, rectangles, polygons, etc.)
    - Valid SVG attributes and styling
    - Transform matrices and positioning
    - Line and fill properties
    - All standard SVG namespaces

EXIT CODES:
    0   All files processed successfully
    1   One or more files failed to process
    2   Invalid arguments or missing dependencies

NOTES:
    - Input files must be valid SVG files (.svg extension)
    - When using --output, only a single input file is allowed
    - Files are automatically backed up before modification (use -o for safety)
    - The script requires Python 3 with ElementTree (included in standard library)

EOF
}

show_version() {
    echo "svg-clean version ${SCRIPT_VERSION}"
}

error_msg() {
    echo -e "${RED}✗ Error:${NC} $*" >&2
}

success_msg() {
    echo -e "${GREEN}✓ $*${NC}"
}

info_msg() {
    echo -e "${BLUE}ℹ $*${NC}"
}

warn_msg() {
    echo -e "${YELLOW}⚠ $*${NC}"
}

check_python() {
    if ! command -v python3 &> /dev/null; then
        error_msg "Python 3 is not installed or not in PATH"
        error_msg "Please install Python 3 to use this script"
        exit 2
    fi
}

check_python_script() {
    if [[ ! -f "$PYTHON_SCRIPT" ]]; then
        error_msg "Python script not found: $PYTHON_SCRIPT"
        error_msg "Make sure svg_inkscape_cleaner.py is in the same directory as this script"
        exit 2
    fi
}

validate_svg_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        error_msg "File not found: $file"
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        error_msg "File is not readable: $file"
        return 1
    fi
    
    if [[ "${file##*.}" != "svg" && "${file##*.}" != "SVG" ]]; then
        warn_msg "File does not have .svg extension: $file"
    fi
    
    # Check if file looks like SVG (basic check)
    if ! grep -q "<?xml\|<svg" "$file" 2>/dev/null; then
        error_msg "File does not appear to be a valid SVG file: $file"
        return 1
    fi
    
    return 0
}

###############################################################################
# Main Script
###############################################################################

main() {
    local input_files=()
    local output_file=""
    local verbose=0
    local keep_empty_defs=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -o|--output)
                if [[ -z "$2" ]]; then
                    error_msg "--output requires an argument"
                    exit 2
                fi
                output_file="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=1
                shift
                ;;
            --keep-empty-defs)
                keep_empty_defs=1
                shift
                ;;
            -*)
                error_msg "Unknown option: $1"
                echo ""
                echo "Use '$SCRIPT_NAME --help' for usage information"
                exit 2
                ;;
            *)
                input_files+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate input
    if [[ ${#input_files[@]} -eq 0 ]]; then
        error_msg "No input files specified"
        echo ""
        echo "Use '$SCRIPT_NAME --help' for usage information"
        exit 2
    fi
    
    if [[ -n "$output_file" && ${#input_files[@]} -gt 1 ]]; then
        error_msg "--output can only be used with a single input file"
        exit 2
    fi
    
    # Check dependencies
    check_python
    check_python_script
    
    # Validate all input files
    info_msg "Validating input files..."
    local validation_failed=0
    for file in "${input_files[@]}"; do
        if ! validate_svg_file "$file"; then
            validation_failed=1
        fi
    done
    
    if [[ $validation_failed -eq 1 ]]; then
        exit 2
    fi
    
    if [[ ${#input_files[@]} -gt 1 ]]; then
        info_msg "Processing ${#input_files[@]} files..."
    fi
    
    # Build Python script arguments
    local py_args=()
    
    if [[ $verbose -eq 1 ]]; then
        py_args+=("-v")
    fi
    
    if [[ $keep_empty_defs -eq 1 ]]; then
        py_args+=("--keep-empty-defs")
    fi
    
    if [[ -n "$output_file" ]]; then
        py_args+=("-o" "$output_file")
    fi
    
    # Add input files
    py_args+=("${input_files[@]}")
    
    # Call Python script
    if python3 "$PYTHON_SCRIPT" "${py_args[@]}"; then
        if [[ ${#input_files[@]} -eq 1 ]]; then
            if [[ -n "$output_file" ]]; then
                success_msg "SVG cleaned successfully: $output_file"
            else
                success_msg "SVG cleaned successfully: ${input_files[0]}"
            fi
        else
            success_msg "All ${#input_files[@]} files cleaned successfully"
        fi
        exit 0
    else
        error_msg "Failed to process SVG file(s)"
        exit 1
    fi
}

# Run main function
main "$@"
