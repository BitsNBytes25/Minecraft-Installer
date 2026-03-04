#!/bin/bash
#
# Setup this project for development

# Setup a virtual environment for Python with the necessary dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install --force-reinstall warlock-manager@git+https://github.com/BitsNBytes25/Warlock-Manager.git@main

# Install newest version of scripts compiler
if which curl; then
	curl -sL https://raw.githubusercontent.com/eVAL-Agency/ScriptsCollection/refs/heads/main/compile.py -o compile.py
elif which wget; then
	wget https://raw.githubusercontent.com/eVAL-Agency/ScriptsCollection/refs/heads/main/compile.py -O compile.py
else
	echo "Neither curl nor wget is installed. Please install one of them to download the scripts compiler."
	exit 1
fi
chmod +x compile.py