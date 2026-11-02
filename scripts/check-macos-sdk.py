#!/usr/bin/env python3
"""Reject a packaged executable whose linked SDK does not match its build SDK.

AppKit/SwiftUI use linked-on-or-after SDK behavior for native control appearance.
The minimum supported OS is separate and must not be substituted for the SDK.
"""
import argparse
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--binary', type=Path, required=True)
parser.add_argument('--sdk-version', required=True)
args = parser.parse_args()
output = subprocess.run(['otool', '-l', str(args.binary)], check=True, capture_output=True, text=True).stdout
sdk = re.search(r'cmd LC_BUILD_VERSION\b(?:(?!\nLoad command).)*?\n\s+sdk\s+(\d+(?:\.\d+)*)', output, re.S)
if not sdk:
    raise SystemExit('Missing macOS LC_BUILD_VERSION SDK metadata.')
def major_minor(version):
    parts = [int(part) for part in version.split('.')]
    return tuple((parts + [0])[:2])
if major_minor(sdk[1]) != major_minor(args.sdk_version):
    raise SystemExit(f'Linked SDK {sdk[1]} does not match build SDK {args.sdk_version}; native controls may use the wrong compatibility appearance.')
print(f'Linked SDK {sdk[1]} matches build SDK {args.sdk_version}.')
