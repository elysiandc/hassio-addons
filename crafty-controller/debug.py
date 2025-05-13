#!/usr/bin/env python3

import os
import json
import sys

# Path to version.json
version_path = '/crafty/app/config/version.json'

# Extreme debugging
print("Current Working Directory:", os.getcwd())
print("Python Executable:", sys.executable)
print("Python Version:", sys.version)
print("Environment Variables:")
for k, v in os.environ.items():
    print(f"{k}: {v}")

# Check file existence and details
print("\nChecking version.json:")
print("Full Path:", os.path.abspath(version_path))
print("Path Exists:", os.path.exists(version_path))

if os.path.exists(version_path):
    print("File Details:")
    print("Absolute Path:", os.path.abspath(version_path))
    print("Is File:", os.path.isfile(version_path))
    print("Is Symlink:", os.path.islink(version_path))

    if os.path.islink(version_path):
        print("Symlink Target:", os.readlink(version_path))

    try:
        with open(version_path, 'r') as f:
            content = f.read()
            print("File Contents:")
            print(content)

        print("\nParsing JSON:")
        version_data = json.load(open(version_path))
        print("Parsed JSON:", version_data)
    except Exception as e:
        print("Error reading file:", str(e))

# List directory contents
print("\nDirectory Contents:")
try:
    print("Current Directory Contents:")
    print(os.listdir('.'))

    print("\n/crafty/app/config Contents:")
    print(os.listdir('/crafty/app/config'))
except Exception as e:
    print("Error listing directory:", str(e))