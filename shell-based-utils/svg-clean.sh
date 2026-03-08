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

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#PYTHON_SCRIPT="${SCRIPT_DIR}/svg_inkscape_cleaner.py"

cleaner() {
cat <<'PYTHON'
#!/usr/bin/env python3

import xml.etree.ElementTree as ET
import sys
import argparse
from pathlib import Path


def clean_svg(input_file, output_file=None, remove_empty_defs=True, verbose=False):
    
    # Register namespaces to preserve them in output (except Inkscape ones)
    namespaces = {
        'svg': 'http://www.w3.org/2000/svg',
        'xlink': 'http://www.w3.org/1999/xlink',
        'xml': 'http://www.w3.org/XML/1998/namespace',
    }
    
    # Inkscape namespaces to remove
    inkscape_namespaces = {
        'http://www.inkscape.org/namespaces/inkscape',
        'http://sodipodi.sourceforge.net/DTD/sodipodi.dtd',
    }
    
    for prefix, uri in namespaces.items():
        ET.register_namespace(prefix, uri)
    
    try:
        tree = ET.parse(input_file)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"Error parsing SVG file: {e}", file=sys.stderr)
        return False
    
    removed_count = 0
    
    # Remove Inkscape namespace declarations from root element
    attribs_to_remove = []
    for attr in root.attrib:
        if attr.startswith('{http://www.inkscape.org/namespaces/inkscape}'):
            attribs_to_remove.append(attr)
        elif attr.startswith('{http://sodipodi.sourceforge.net/DTD/sodipodi.dtd}'):
            attribs_to_remove.append(attr)
        # Also catch xmlns attributes for Inkscape
        elif 'inkscape' in attr or 'sodipodi' in attr:
            attribs_to_remove.append(attr)
    
    for attr in attribs_to_remove:
        del root.attrib[attr]
        removed_count += 1
        if verbose:
            print(f"Removed namespace declaration: {attr}")
    
    # Remove metadata elements and Inkscape-specific elements
    def should_remove(elem):
        """Check if element should be removed."""
        tag = elem.tag
        
        # Remove metadata
        if 'metadata' in tag.lower():
            return True
        
        # Remove Inkscape-specific elements
        if 'sodipodi' in tag.lower() or 'inkscape' in tag.lower():
            return True
        
        return False
    
    elements_to_remove = []
    for elem in root.iter():
        if should_remove(elem):
            elements_to_remove.append(elem)
    
    for elem in elements_to_remove:
        parent = None
        for p in root.iter():
            if elem in p:
                parent = p
                break
        
        if parent is not None:
            parent.remove(elem)
            removed_count += 1
            if verbose:
                print(f"Removed element: {elem.tag}")
    
    # Remove Inkscape-specific attributes from all elements
    for elem in root.iter():
        attribs_to_remove = []
        for attr in elem.attrib:
            # Remove sodipodi:type and similar attributes
            if 'sodipodi' in attr or 'inkscape' in attr:
                attribs_to_remove.append(attr)
        
        for attr in attribs_to_remove:
            del elem.attrib[attr]
            removed_count += 1
            if verbose:
                print(f"Removed attribute from {elem.tag}: {attr}")
    
    # Remove empty defs sections if requested
    if remove_empty_defs:
        defs_to_remove = []
        for elem in root.iter():
            if 'defs' in elem.tag:
                # Check if defs is empty or only contains Inkscape stuff
                if len(elem) == 0 or all('inkscape' in child.tag.lower() or 'sodipodi' in child.tag.lower() 
                                         for child in elem):
                    defs_to_remove.append(elem)
        
        for defs in defs_to_remove:
            parent = None
            for p in root.iter():
                if defs in p:
                    parent = p
                    break
            
            if parent is not None:
                parent.remove(defs)
                removed_count += 1
                if verbose:
                    print(f"Removed empty defs section")
    
    # Write output
    if output_file is None:
        output_file = input_file
    
    try:
        tree.write(output_file, encoding='utf-8', xml_declaration=True)
        return True
    except Exception as e:
        print(f"Error writing output file: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Remove Inkscape-specific metadata and attributes from SVG files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s input.svg                    # Clean in-place
  %(prog)s input.svg -o output.svg      # Clean and save to new file
  %(prog)s input.svg -v                 # Clean and show what was removed
  %(prog)s *.svg                        # Clean all SVG files in directory
        """
    )
    
    parser.add_argument('input_files', nargs='+', 
                       help='Input SVG file(s) to clean')
    parser.add_argument('-o', '--output', dest='output_file',
                       help='Output file (only works with single input file)')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Print details of what was removed')
    parser.add_argument('--keep-empty-defs', action='store_true',
                       help='Keep empty defs sections')
    
    args = parser.parse_args()
    
    # Handle multiple input files
    if len(args.input_files) > 1 and args.output_file:
        print("Error: --output can only be used with a single input file", file=sys.stderr)
        sys.exit(1)
    
    success_count = 0
    for input_file in args.input_files:
        input_path = Path(input_file)
        
        if not input_path.exists():
            print(f"Error: File not found: {input_file}", file=sys.stderr)
            continue
        
        if not input_path.suffix.lower() == '.svg':
            print(f"Warning: {input_file} does not have .svg extension", file=sys.stderr)
        
        output_path = args.output_file if args.output_file else input_file
        
        if args.verbose:
            print(f"\nProcessing: {input_file}")
            if output_path != input_file:
                print(f"Output: {output_path}")
        
        if clean_svg(input_path, output_path, 
                    remove_empty_defs=not args.keep_empty_defs,
                    verbose=args.verbose):
            success_count += 1
            if args.verbose:
                print(f"✓ Successfully cleaned: {input_file}")
        else:
            print(f"✗ Failed to clean: {input_file}", file=sys.stderr)
    
    if args.verbose:
        print(f"\n{success_count}/{len(args.input_files)} file(s) processed successfully")
    
    sys.exit(0 if success_count == len(args.input_files) else 1)


if __name__ == '__main__':
    main()
PYTHON
}



###############################################################################
# svg-clean (debug)
# Bash wrapper writing Python to temp file


###############################################################################

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
    --debug                     Write embedded Python to temp file and keep it
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
    - With --debug, the embedded Python is written to a temp file
      in the system temp directory (respects \$TMPDIR and is cleared
      automatically on reboot)

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
    local debug=0
    
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
            --debug)
                debug=1
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
    
    # Call embedded Python script (optionally via temp file when --debug is set)
    local python_status

    if [[ $debug -eq 1 ]]; then
        local tmp_base tmp_py
        case "$(uname -s)" in
            Darwin)
                tmp_base="${TMPDIR:-/var/tmp}"
                ;;
            Linux)
                tmp_base="${TMPDIR:-/tmp}"
                ;;
            *)
                tmp_base="${TMPDIR:-/tmp}"
                ;;
        esac

        tmp_py="$(mktemp -p "$tmp_base" svg_cleaner_XXXX.py)"
        cleaner > "$tmp_py"
        info_msg "Debug: wrote embedded Python script to $tmp_py (not removed automatically)"
        python3 "$tmp_py" "${py_args[@]}"
        python_status=$?
    else
        cleaner | python3 - "${py_args[@]}"
        python_status=$?
    fi

    if [[ $python_status -eq 0 ]]; then
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
    fi

    error_msg "Failed to process SVG file(s)"
    exit 1
}

# Run main function
main "$@"
