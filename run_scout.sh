#!/bin/bash
# This script runs ScoutSuite from a pre-existing virtual environment.
# It assumes that the virtual environment has already been created and activated.   

# Authored by: Campbell Murray
# Date: 2023-10-01
# Version: 1.0
# Sodium Cyber Ltd - www.sodiumcyber.com


# Determine the actual user's home directory to find the virtual environment
if [ "$EUID" -eq 0 ]; then
    # Script is being run as root (e.g., via sudo)
    CALLING_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
    USER_HOME=$(getent passwd "$CALLING_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        echo "Error: Could not determine calling user's home directory. Exiting."
        exit 1
    fi
    VENV_DIR="$USER_HOME/scoutsuite_venv"
    echo "Running as root. Looking for virtual environment in the home directory of user: $CALLING_USER ($USER_HOME)"
else
    # Script is being run as a regular user
    VENV_DIR="$HOME/scoutsuite_venv"
    echo "Running as regular user. Looking for virtual environment in your home directory: $HOME"
fi

echo "Attempting to run ScoutSuite..."
echo "---------------------------------------------------"

# Step 1: Check if the virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found at $VENV_DIR."
    echo "Please ensure the installation script ran successfully and created it in your user's home directory."
    echo "If it was created in /root, you might need to move it or manually activate from there."
    exit 1
fi

# Step 2: Activate the virtual environment
echo "Activating virtual environment from: $VENV_DIR"
source "$VENV_DIR/bin/activate"
if [ $? -ne 0 ]; then
    echo "Error: Failed to activate virtual environment."
    echo "You can try sourcing it manually: source $VENV_DIR/bin/activate"
    exit 1
fi
echo "Virtual environment activated."

# Step 3: Run the 'scout' command
# "$@" passes all arguments received by this script to the 'scout' command
echo "Executing 'scout $@'..."
scout "$@"

# Step 4: Deactivate the virtual environment after ScoutSuite finishes
deactivate
echo "Virtual environment deactivated."

echo "---------------------------------------------------"
echo "ScoutSuite execution finished."
echo "---------------------------------------------------"
