#!/usr/bin/env python3
import os
import sys

def replace_in_file(filepath, old, new):
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
    except (UnicodeDecodeError, PermissionError):
        return

    if old not in content:
        return

    # Backup
    with open(filepath + ".bak", "w", encoding="utf-8") as f:
        f.write(content)

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content.replace(old, new))

    print(f"Updated CONTENT: {filepath}")


def rename_file(filepath, old, new):
    dirname, filename = os.path.dirname(filepath), os.path.basename(filepath)
    if old in filename:
        new_filename = filename.replace(old, new)
        new_path = os.path.join(dirname, new_filename)
        os.rename(filepath, new_path)
        print(f"Renamed FILE: {filename} → {new_filename}")
        return new_path
    return filepath


def process_folder(base_folder, old, new):
    for root, dirs, files in os.walk(base_folder):
        # Only process folders that are "sub*" or inside "sub*"
        parts = root.split(os.sep)
        if any(part.startswith("sub") for part in parts):
            for f in files:
                full_path = os.path.join(root, f)
                full_path = rename_file(full_path, old, new)
                replace_in_file(full_path, old, new)


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: script.py <folder> <old_string> <new_string>")
        sys.exit(1)

    base = sys.argv[1]
    old = sys.argv[2]
    new = sys.argv[3]

    process_folder(base, old, new)
