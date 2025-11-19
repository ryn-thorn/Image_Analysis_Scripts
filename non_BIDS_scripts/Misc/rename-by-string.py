#!/usr/bin/env python3
import os
import sys

def replace_in_file(filepath, old, new):
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        return  # Skip binary files

    if old not in content:
        return

    backup_path = filepath + ".bak"
    with open(backup_path, "w", encoding="utf-8") as f:
        f.write(content)

    updated = content.replace(old, new)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(updated)

    print(f"Updated content: {filepath}")


def rename_file_if_needed(filepath, old, new):
    dirname, filename = os.path.dirname(filepath), os.path.basename(filepath)

    if old in filename:
        new_filename = filename.replace(old, new)
        new_path = os.path.join(dirname, new_filename)

        os.rename(filepath, new_path)
        print(f"Renamed file: {filepath} → {new_path}")

        return new_path  # Return new path so content editing can continue
    return filepath


def main():
    if len(sys.argv) < 4:
        print("Usage: rename-by-string.py <folder> <old_string> <new_string>")
        sys.exit(1)

    base_folder = sys.argv[1]
    old = sys.argv[2]
    new = sys.argv[3]

    for root, dirs, files in os.walk(base_folder):
        # Only descend into dirs starting with "sub"
        dirs[:] = [d for d in dirs if d.startswith("sub")]

        rel_path = os.path.relpath(root, base_folder)
        depth = 0 if rel_path == "." else rel_path.count(os.sep) + 1

        # Only operate when at least 3 subfolders deep
        if depth >= 3:
            for name in files:
                filepath = os.path.join(root, name)

                # First rename file if needed
                updated_path = rename_file_if_needed(filepath, old, new)

                # Then replace inside file
                replace_in_file(updated_path, old, new)


if __name__ == "__main__":
    main()
