#!/usr/bin/env python
import pathlib
import re
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <version>")

    # Strip leading "v" from tags like "v2026.03.16"
    version = sys.argv[1].lstrip("v")

    # These are the artifact copies created in the workflow
    linux_path = pathlib.Path("dist/svtminion.sh")
    windows_path = pathlib.Path("dist/svtminion.ps1")

    # Update bash script readonly SCRIPT_VERSION
    linux_text = linux_path.read_text(encoding="utf-8")
    linux_text = re.sub(
        r'readonly SCRIPT_VERSION="(.*)"',
        f'readonly SCRIPT_VERSION="{version}"',
        linux_text,
    )
    linux_path.write_text(linux_text, encoding="utf-8")

    # Update PowerShell script $SCRIPT_VERSION
    windows_text = windows_path.read_text(encoding="utf-8")
    windows_text = re.sub(
        r'\$SCRIPT_VERSION = "(.*)"',
        f'$SCRIPT_VERSION = "{version}"',
        windows_text,
    )
    windows_path.write_text(windows_text, encoding="utf-8")


if __name__ == "__main__":
    main()

