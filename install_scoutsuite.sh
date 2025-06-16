#!/bin/bash

# This script installs ScoutSuite and its dependencies, including various cloud CLI tools.
# It creates a Python virtual environment to isolate the installation.
# Ensure the script is run with appropriate permissions
# (e.g., using sudo if necessary).      
# Usage: ./install_scoutsuite.sh
# Ensure the script is run in a terminal with internet access.

# Authored by: Campbell Murray
# Date: 2023-10-01
# Version: 1.0
# Sodium Cyber Ltd - www.sodiumcyber.com

# Determine the actual user's home directory to create the virtual environment
# This ensures the venv is created in the user's home, even if the script is run with sudo.
if [ "$EUID" -eq 0 ]; then
    CALLING_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
    USER_HOME=$(getent passwd "$CALLING_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        echo "Error: Could not determine calling user's home directory. Exiting."
        exit 1
    fi
    VENV_DIR="$USER_HOME/scoutsuite_venv"
    echo "Running as root. Virtual environment will be created in the home directory of user: $CALLING_USER ($USER_HOME)"
else
    VENV_DIR="$HOME/scoutsuite_venv"
    echo "Running as regular user. Virtual environment will be created in your home directory: $HOME"
fi

echo "Starting ScoutSuite and Cloud CLI installation process..."
echo "---------------------------------------------------"

# Function to check and install a Debian package
check_and_install_apt_package() {
    PACKAGE_NAME=$1
    echo "Checking for '$PACKAGE_NAME' package..."
    if ! dpkg -s "$PACKAGE_NAME" >/dev/null 2>&1; then
        echo "'$PACKAGE_NAME' is not installed. Installing it now..."
        sudo apt update
        sudo apt install -y "$PACKAGE_NAME"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install '$PACKAGE_NAME'. Please install it manually and try again."
            return 1 # Indicate failure
        fi
        echo "'$PACKAGE_NAME' installed successfully."
    else
        echo "'$PACKAGE_NAME' is already installed."
    fi
    return 0 # Indicate success
}

# --- Common OS Dependencies ---
# Check and install python3-venv
if ! check_and_install_apt_package "python3-venv"; then
    echo "Installation failed due to missing 'python3-venv'. Exiting."
    exit 1
fi

# Check and install unzip (needed for AWS CLI v2 installation method)
if ! check_and_install_apt_package "unzip"; then
    echo "Warning: 'unzip' could not be installed. AWS CLI installation might fail."
    # Continue as unzip is not critical for other parts
fi

# Check and install ca-certificates and gnupg for various CLI installations
if ! check_and_install_apt_package "ca-certificates"; then
    echo "Warning: 'ca-certificates' could not be installed. Some CLI installations might fail."
fi
if ! check_and_install_apt_package "gnupg"; then
    echo "Warning: 'gnupg' could not be installed. Some CLI installations might fail."
fi

# --- Virtual Environment Setup ---
echo "Creating virtual environment at: $VENV_DIR"
python3 -m venv "$VENV_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create virtual environment at $VENV_DIR. Please check permissions or disk space."
    exit 1
fi
echo "Virtual environment created successfully."

echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"
if [ $? -ne 0 ]; then
    echo "Error: Failed to activate virtual environment. Exiting."
    exit 1
fi
echo "Virtual environment activated."

# --- Python Package Installation (ScoutSuite and its direct dependencies) ---
echo "Installing Python dependencies ('asyncio_throttle', 'scoutsuite') within the virtual environment..."
pip install asyncio_throttle
if [ $? -ne 0 ]; then
    echo "Error: Failed to install 'asyncio_throttle'. Please check your internet connection or try again."
    deactivate
    exit 1
fi
echo "'asyncio_throttle' installed."

pip install scoutsuite
if [ $? -ne 0 ]; then
    echo "Error: Failed to install 'scoutsuite'. Please check your internet connection or try again."
    deactivate
    exit 1
fi
echo "'scoutsuite' installed."

# --- Cloud CLI Installations ---

echo "Checking and installing Cloud CLIs..."

# --- AWS CLI v2 Installation ---
echo "--- AWS CLI v2 ---"
if command -v aws &>/dev/null; then
    echo "AWS CLI is already installed."
else
    echo "AWS CLI not found. Attempting to install AWS CLI v2..."
    AWS_CLI_V2_ZIP="awscliv2.zip"
    AWS_CLI_INSTALL_DIR="/tmp/aws-cli-install" # Use /tmp for temporary extraction

    # Download AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$AWS_CLI_V2_ZIP"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download AWS CLI v2. Please check internet connection or curl."
    else
        # Create a temporary directory for extraction
        mkdir -p "$AWS_CLI_INSTALL_DIR"

        # Unzip and install
        unzip -q "$AWS_CLI_V2_ZIP" -d "$AWS_CLI_INSTALL_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to unzip AWS CLI v2. Ensure 'unzip' is installed."
        else
            # Run the install script (sudo is handled by the script itself)
            sudo "$AWS_CLI_INSTALL_DIR/aws/install" --update
            if [ $? -ne 0 ]; then
                echo "Error: AWS CLI v2 installation script failed. Please check permissions."
            else
                echo "AWS CLI v2 installed successfully."
            fi
        fi
        # Clean up temporary files
        rm -rf "$AWS_CLI_V2_ZIP" "$AWS_CLI_INSTALL_DIR"
    fi
fi

# --- Azure CLI Installation ---
echo "--- Azure CLI ---"
if command -v az &>/dev/null; then
    echo "Azure CLI is already installed."
else
    echo "Azure CLI not found. Attempting to install Azure CLI..."
    # Ensure apt-transport-https is installed for secure apt
    check_and_install_apt_package "apt-transport-https"

    sudo curl -sL https://aka.ms/InstallAzureCliDeb | sudo bash
    if [ $? -ne 0 ]; then
        echo "Error: Azure CLI installation script failed. Please check internet connection or curl/sudo permissions."
    else
        echo "Azure CLI installed successfully."
    fi
fi

# --- Google Cloud SDK (gcloud CLI) Installation ---
echo "--- Google Cloud SDK (gcloud CLI) ---"
if command -v gcloud &>/dev/null; then
    echo "Google Cloud SDK is already installed."
else
    echo "Google Cloud SDK not found. Attempting to install Google Cloud SDK..."
    # Add the Cloud SDK distribution URI as a package source
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null

    # Import the Google Cloud public key
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    if [ $? -ne 0 ]; then
        echo "Error: Failed to import Google Cloud public key. Installation might proceed but with warnings."
    fi

    # Update the package list and install the Cloud SDK
    sudo apt update
    sudo apt install -y google-cloud-sdk
    if [ $? -ne 0 ]; then
        echo "Error: Google Cloud SDK installation failed. Please check apt setup."
    else
        echo "Google Cloud SDK installed successfully."
    fi
fi


echo "---------------------------------------------------"
echo "ScoutSuite and Cloud CLI installation process completed."
echo "You can now run ScoutSuite using the 'run_scoutsuite.sh' script."
echo "Remember to authenticate your CLIs (e.g., aws configure, az login, gcloud auth login) before running ScoutSuite."
echo "---------------------------------------------------"

# Deactivate the virtual environment to return to the system shell
deactivate
echo "Virtual environment deactivated."
echo "./run_scout.sh script is ready to use."
