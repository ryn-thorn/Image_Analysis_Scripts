#!/usr/bin/env python3

import os
import subprocess
import sys
import tkinter as tk
from tkinter import filedialog, messagebox

SCRIPT_NAME = "run_freesurfer_bids"

class FreeSurferGUI(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("FreeSurfer 6.0 BIDS Runner")
        self.geometry("500x200")
        self.resizable(False, False)

        self.bids_path = tk.StringVar()

        tk.Label(self, text="BIDS root folder:").pack(pady=10)

        frame = tk.Frame(self)
        frame.pack(pady=5)

        tk.Entry(frame, textvariable=self.bids_path, width=50).pack(side=tk.LEFT, padx=5)
        tk.Button(frame, text="Browse", command=self.browse).pack(side=tk.LEFT)

        tk.Button(self, text="Run FreeSurfer", command=self.run).pack(pady=20)

    def browse(self):
        path = filedialog.askdirectory(title="Select BIDS root folder")
        if path:
            self.bids_path.set(path)

    def run(self):
        bids = self.bids_path.get()

        if not bids:
            messagebox.showerror("Error", "Please select a BIDS root folder.")
            return

        if not os.path.isdir(bids):
            messagebox.showerror("Error", "Selected path is not a directory.")
            return

        script_path = os.path.join(os.path.dirname(__file__), SCRIPT_NAME)

        if not os.path.isfile(script_path):
            messagebox.showerror(
                "Error",
                f"Could not find {SCRIPT_NAME} in the same folder as this GUI."
            )
            return

        try:
            subprocess.Popen(
                [script_path, bids],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            messagebox.showinfo(
                "Started",
                "FreeSurfer processing has started.\n\n"
                "A terminal window may open showing progress."
            )
        except Exception as e:
            messagebox.showerror("Error", str(e))


if __name__ == "__main__":
    app = FreeSurferGUI()
    app.mainloop()
