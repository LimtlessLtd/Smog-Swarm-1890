#!/usr/bin/env python3
"""Invoke the project-configured Godot executable without shell quoting."""
import os
import subprocess
import sys

GODOT = os.environ.get("GODOT_BIN", r"E:\Program Files\GoDot\Godot_v4.7.1-stable_win64_console.exe")

def command(arguments):
    return [GODOT, *arguments]

if __name__ == "__main__":
    sys.exit(subprocess.run(command(sys.argv[1:]), shell=False).returncode)
