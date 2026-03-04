#!/usr/bin/env python3
"""
Clean Inkscape-specific content from SVG files.

Removes:
- Inkscape/Sodipodi namespace declarations
- metadata elements
- Inkscape-specific attributes
- sodipodi:type attributes
- Empty defs sections (optionally)

Preserves all actual vector content (paths, circles, rects, etc.).

Usage:
######

- Clean in-place (modifies original)
# python3 svg_inkscape_cleaner.py drawing.svg

- Save to new file
# python3 svg_inkscape_cleaner.py drawing.svg -o cleaned_drawing.svg

- Show details of what was removed
# python3 svg_inkscape_cleaner.py drawing.svg -v

- Batch clean multiple files
# python3 svg_inkscape_cleaner.py *.svg -v

- Keep empty defs sections (default removes them)
# python3 svg_inkscape_cleaner.py drawing.svg --keep-empty-defs

"""

import xml.etree.ElementTree as ET
import sys
import argparse
from pathlib import Path


def clean_svg(input_file, output_file=None, remove_empty_defs=True, verbose=False):
    """
    Clean Inkscape-specific content from SVG file.
    
    Args:
        input_file: Path to input SVG
        output_file: Path to output SVG (defaults to input_file if None)
        remove_empty_defs: Remove empty <defs> sections
        verbose: Print what was removed
    """
    
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
