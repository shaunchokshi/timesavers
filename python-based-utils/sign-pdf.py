#!/usr/bin/env python3
"""Sign a PDF using an ECDSA (or RSA) PFX/PKCS12 certificate bundle.

Usage:
    sign-pdf <input.pdf> <certificate.pfx> [output.pdf] [--pass PASSWORD]

If output is omitted, writes to <input>-signed.pdf
"""

import argparse
import getpass
import sys
from pathlib import Path

from pyhanko.sign import signers, fields
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter


def main():
    parser = argparse.ArgumentParser(description="Sign a PDF with a PFX certificate")
    parser.add_argument("pdf", help="Input PDF file")
    parser.add_argument("pfx", help="PFX/PKCS12 certificate bundle")
    parser.add_argument("output", nargs="?", help="Output PDF (default: <input>-signed.pdf)")
    parser.add_argument("--pass", dest="password", default=None,
                        help="PFX password (will prompt if not provided)")
    parser.add_argument("--field", default=None,
                        help="Existing signature field name to use")
    parser.add_argument("--reason", default=None, help="Signing reason")
    parser.add_argument("--location", default=None, help="Signing location")
    parser.add_argument("--contact", default=None, help="Signer contact info")
    args = parser.parse_args()

    pdf_path = Path(args.pdf)
    pfx_path = Path(args.pfx)

    if not pdf_path.exists():
        print(f"Error: PDF file not found: {pdf_path}", file=sys.stderr)
        sys.exit(1)
    if not pfx_path.exists():
        print(f"Error: PFX file not found: {pfx_path}", file=sys.stderr)
        sys.exit(1)

    if args.output:
        out_path = Path(args.output)
    else:
        out_path = pdf_path.with_stem(pdf_path.stem + "-signed")

    password = args.password
    if password is None:
        password = getpass.getpass("PFX password: ")

    # Load the PKCS12 signer (handles both RSA and EC keys)
    signer = signers.SimpleSigner.load_pkcs12(
        pfx_file=str(pfx_path),
        passphrase=password.encode("utf-8") if password else None,
    )

    with open(pdf_path, "rb") as f:
        writer = IncrementalPdfFileWriter(f)

        sig_meta = signers.PdfSignatureMetadata(
            field_name=args.field or "Signature1",
            reason=args.reason,
            location=args.location,
            contact_info=args.contact,
        )

        with open(out_path, "wb") as out_f:
            signers.sign_pdf(
                writer,
                signature_meta=sig_meta,
                signer=signer,
                output=out_f,
            )

    print(f"Signed: {out_path}")


if __name__ == "__main__":
    main()
