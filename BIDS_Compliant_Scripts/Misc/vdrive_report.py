#!/usr/bin/env python
import os
import json
import time
import shutil
import matplotlib.pyplot as plt
from reportlab.platypus import SimpleDocTemplate, Paragraph, Image, Spacer
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
import tempfile
from tqdm import tqdm

#############################################
# CONFIGURATION
#############################################

ROOT = "/Volumes/vdrive"
PLAYAREA = f"{ROOT}/helpern_playarea"
USERS = f"{ROOT}/helpern_users"

OUTPUT_PDF = "/Volumes/vdrive/server_space_report.pdf"
CACHE_FILE = os.path.expanduser("~/.server_space_cache.json")

#############################################
# CACHE FUNCTIONS
#############################################

def load_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                return json.load(f)
        except:
            return {}
    return {}

def save_cache(cache):
    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f, indent=2)

def folder_modified_time(path):
    """Return the latest modification time inside a directory."""
    latest = 0
    for root, dirs, files in os.walk(path):
        for f in files:
            fp = os.path.join(root, f)
            try:
                m = os.path.getmtime(fp)
                if m > latest:
                    latest = m
            except:
                pass
    return latest

#############################################
# FILE SIZE FUNCTIONS
#############################################

def folder_size(path, cache):
    """Return folder size using cache when possible, with progress."""
    path = os.path.abspath(path)

    # Check if cached
    if path in cache:
        cached = cache[path]
        current_mtime = folder_modified_time(path)

        if current_mtime <= cached["folder_mtime"]:
            # Folder unchanged — use cached value
            return cached["size"]

    # Folder changed or uncached — scan
    total_size = 0
    file_list = []

    # Build list of files first (fast)
    for root, dirs, files in os.walk(path):
        for f in files:
            file_list.append(os.path.join(root, f))

    # Progress bar for size calculation
    for fp in tqdm(file_list, desc=f"Scanning {path}", unit="files"):
        try:
            total_size += os.path.getsize(fp)
        except:
            pass

    # Save updated cache entry
    cache[path] = {
        "size": total_size,
        "folder_mtime": folder_modified_time(path),
        "cached_at": time.time()
    }

    save_cache(cache)
    return total_size

def bytes_to_gb(b):
    return b / (1024**3)

def get_subfolder_sizes(base_path, cache):
    subfolders = sorted([
        f for f in os.listdir(base_path)
        if os.path.isdir(os.path.join(base_path, f))
    ])
    sizes = {}
    for sf in subfolders:
        p = os.path.join(base_path, sf)
        sizes[sf] = folder_size(p, cache)
    return sizes

#############################################
# PLOTTING
#############################################

def make_bar_plot(data_dict, title):
    names = list(data_dict.keys())
    values_gb = [bytes_to_gb(v) for v in data_dict.values()]

    plt.figure(figsize=(10,5))
    plt.bar(names, values_gb)
    plt.xticks(rotation=45, ha='right')
    plt.ylabel("Used Space (GB)")
    plt.title(title)
    plt.tight_layout()

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
    plt.savefig(tmp.name, dpi=150)
    plt.close()
    return tmp.name

#############################################
# MAIN
#############################################

if __name__ == "__main__":
    cache = load_cache()

    # Overall disk usage
    total, used, free = shutil.disk_usage(ROOT)

    # Subfolder sizes with caching + progress bars
    playarea_sizes = get_subfolder_sizes(PLAYAREA, cache)
    users_sizes = get_subfolder_sizes(USERS, cache)

    # Plots
    playarea_plot = make_bar_plot(playarea_sizes,
                                  "Space Used per Subfolder: helpern_playarea")
    users_plot = make_bar_plot(users_sizes,
                               "Space Used per Subfolder: helpern_users")

    #############################################
    # PDF GENERATION
    #############################################

    styles = getSampleStyleSheet()
    story = []
    doc = SimpleDocTemplate(OUTPUT_PDF, pagesize=letter)

    total_gb = bytes_to_gb(total)
    used_gb = bytes_to_gb(used)
    free_gb = bytes_to_gb(free)

    summary = f"""
    <para>
    <b>SERVER SPACE REPORT</b><br/><br/>

    <b>Disk Usage ({ROOT}):</b><br/>
    Total: {total_gb:,.2f} GB<br/>
    Used: {used_gb:,.2f} GB<br/>
    Free: {free_gb:,.2f} GB<br/><br/>

    <b>helpern_playarea:</b><br/>
    {"".join([f"{k}: {bytes_to_gb(v):,.2f} GB<br/>" for k, v in playarea_sizes.items()])}
    <br/>

    <b>helpern_users:</b><br/>
    {"".join([f"{k}: {bytes_to_gb(v):,.2f} GB<br/>" for k, v in users_sizes.items()])}
    </para>
    """

    story.append(Paragraph(summary, styles["Normal"]))
    story.append(Spacer(1, 0.3*inch))

    story.append(Paragraph("<b>helpern_playarea Plot</b>", styles["Heading3"]))
    story.append(Image(playarea_plot, width=6.5*inch, height=3*inch))
    story.append(Spacer(1, 0.3*inch))

    story.append(Paragraph("<b>helpern_users Plot</b>", styles["Heading3"]))
    story.append(Image(users_plot, width=6.5*inch, height=3*inch))
    story.append(Spacer(1, 0.3*inch))

    doc.build(story)

    print(f"\nPDF report generated: {OUTPUT_PDF}")
