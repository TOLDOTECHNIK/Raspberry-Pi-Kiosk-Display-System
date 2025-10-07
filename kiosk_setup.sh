#!/bin/bash

# kiosk_setup.sh
# Tested for interactive use on Raspberry Pi OS / Debian-based systems.
# Do NOT run as root. Run as a regular user with sudo privileges.
#
# History
# 2024-10-22 v1.0: Initial release
# 2024-11-04 V1.1: Switch from wayfire to labwc
# 2024-11-13 V1.2: Added setup of wlr-randr
# 2025-10-07 v1.3: Smart chromium package detection + robustness fixes

# Function to display a spinner with additional message
spinner() {
    local pid=$1
    local message=$2
    local delay=0.1
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    tput civis 2>/dev/null || true
    local i=0
    while [ -d /proc/$pid ]; do
        local frame=${frames[$i]}
        printf "\r\e[35m%s\e[0m %s" "$frame" "$message"
        i=$(((i + 1) % ${#frames[@]}))
        sleep $delay
    done
    printf "\r\e[32m✔\e[0m %s\n" "$message"
    tput cnorm 2>/dev/null || true
}

# Ensure not run as root
if [ "$(id -u)" -eq 0 ]; then
  echo "This script should not be run as root. Please run as a regular user with sudo permissions."
  exit 1
fi

# Current user and home dir
CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo "~$CURRENT_USER")

# Function to prompt the user for y/n input
ask_user() {
    local prompt="$1"
    while true; do
        read -p "$prompt (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# update the package list?
echo
if ask_user "Do you want to update the package list?"; then
    echo -e "\e[90mUpdating the package list, please wait...\e[0m"
    sudo apt update > /dev/null 2>&1 &
    spinner $! "Updating package list..."
fi

# upgrade installed packages?
echo
if ask_user "Do you want to upgrade installed packages?"; then
    echo -e "\e[90mUpgrading installed packages. THIS MAY TAKE SOME TIME, please wait...\e[0m"
    sudo apt upgrade -y > /dev/null 2>&1 &
    spinner $! "Upgrading installed packages..."
fi

# install Wayland/labwc packages?
echo
if ask_user "Do you want to install Wayland and labwc packages?"; then
    echo -e "\e[90mInstalling Wayland packages, please wait...\e[0m"
    sudo apt install --no-install-recommends -y labwc wlr-randr seatd > /dev/null 2>&1 &
    spinner $! "Installing Wayland packages..."
fi

# --- Smart Chromium install + autostart snippet ---
# detect available chromium package name (prefer 'chromium')
CHROMIUM_PKG=""
if apt-cache show chromium >/dev/null 2>&1; then
    CHROMIUM_PKG="chromium"
elif apt-cache show chromium-browser >/dev/null 2>&1; then
    CHROMIUM_PKG="chromium-browser"
fi

echo
if ask_user "Do you want to install Chromium Browser?"; then
    if [ -z "$CHROMIUM_PKG" ]; then
        echo -e "\e[33mNo chromium package found in APT. You may need to enable the appropriate repository or install manually.\e[0m"
    else
        echo -e "\e[90mInstalling $CHROMIUM_PKG, please wait...\e[0m"
        sudo apt install --no-install-recommends -y "$CHROMIUM_PKG" > /dev/null 2>&1 &
        spinner $! "Installing $CHROMIUM_PKG..."
    fi
fi

# install and configure greetd?
echo
if ask_user "Do you want to install and configure greetd for auto start of labwc?"; then
    echo -e "\e[90mInstalling greetd for auto start of labwc, please wait...\e[0m"
    sudo apt install -y greetd > /dev/null 2>&1 &
    spinner $! "Installing greetd..."

    echo -e "\e[90mCreating or overwriting /etc/greetd/config.toml...\e[0m"
    sudo mkdir -p /etc/greetd
    sudo bash -c "cat <<EOL > /etc/greetd/config.toml
[terminal]
vt = 7
[default_session]
command = \"/usr/bin/labwc\"
user = \"$CURRENT_USER\"
EOL"

    echo -e "\e[32m✔\e[0m /etc/greetd/config.toml has been created or overwritten successfully!"

    echo -e "\e[90mEnabling greetd service...\e[0m"
    sudo systemctl enable greetd > /dev/null 2>&1 &
    spinner $! "Enabling greetd service..."

    echo -e "\e[90mSetting graphical target as the default...\e[0m"
    sudo systemctl set-default graphical.target > /dev/null 2>&1 &
    spinner $! "Setting graphical target..."
fi

# create an autostart script for labwc?
echo
if ask_user "Do you want to create an autostart (chromium) script for labwc?"; then
    read -p "Enter the URL to open in Chromium [default: https://webglsamples.org...]: " USER_URL
    USER_URL="${USER_URL:-https://webglsamples.org/aquarium/aquarium.html}"

    # Ask about incognito mode (default: yes)
    echo
    INCOGNITO_FLAG=""
    if ask_user "Start browser in incognito mode? [default: yes]"; then
        INCOGNITO_FLAG="--incognito "
    fi

    LABWC_AUTOSTART_DIR="$HOME_DIR/.config/labwc"
    mkdir -p "$LABWC_AUTOSTART_DIR"
    LABWC_AUTOSTART_FILE="$LABWC_AUTOSTART_DIR/autostart"

    # find the installed binary (try both names) — prefer binary in PATH
    CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"

    if [ -z "$CHROMIUM_BIN" ]; then
        # fallback common paths
        if [ -x "/usr/bin/chromium" ]; then
            CHROMIUM_BIN="/usr/bin/chromium"
        elif [ -x "/usr/bin/chromium-browser" ]; then
            CHROMIUM_BIN="/usr/bin/chromium-browser"
        else
            CHROMIUM_BIN="/usr/bin/chromium"
            echo -e "\e[33mWarning: couldn't find chromium binary in PATH. Using $CHROMIUM_BIN in autostart — adjust if needed.\e[0m"
        fi
    fi

    # Ensure autostart file exists
    touch "$LABWC_AUTOSTART_FILE"

    # write autostart entry if not present
    if grep -q -E "chromium|chromium-browser" "$LABWC_AUTOSTART_FILE" 2>/dev/null; then
        echo "Chromium autostart entry already exists in $LABWC_AUTOSTART_FILE."
    else
        echo -e "\e[90mAdding Chromium to labwc autostart script...\e[0m"
        echo "$CHROMIUM_BIN ${INCOGNITO_FLAG}--autoplay-policy=no-user-gesture-required --kiosk $USER_URL &" >> "$LABWC_AUTOSTART_FILE"
        echo -e "\e[32m✔\e[0m labwc autostart script has been created or updated at $LABWC_AUTOSTART_FILE."
    fi
fi

# install Plymouth splash screen?
echo
if ask_user "Do you want to install the Plymouth splash screen?"; then
    CONFIG_TXT="/boot/firmware/config.txt"
    if [ -f "$CONFIG_TXT" ]; then
        if ! grep -q "disable_splash" "$CONFIG_TXT"; then
            echo -e "\e[90mAdding disable_splash=1 to $CONFIG_TXT...\e[0m"
            sudo bash -c "echo 'disable_splash=1' >> '$CONFIG_TXT'"
        else
            echo -e "\e[33m$CONFIG_TXT already contains a disable_splash option. No changes made. Please check manually!\e[0m"
        fi
    else
        echo -e "\e[33m$CONFIG_TXT not found — skipping config.txt modification.\e[0m"
    fi

    CMDLINE_TXT="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_TXT" ]; then
        if ! grep -q "splash" "$CMDLINE_TXT"; then
            echo -e "\e[90mAdding quiet splash plymouth.ignore-serial-consoles to $CMDLINE_TXT...\e[0m"
            sudo sed -i 's/$/ quiet splash plymouth.ignore-serial-consoles/' "$CMDLINE_TXT"
        else
            echo -e "\e[33m$CMDLINE_TXT already contains splash options. No changes made. Please check manually!\e[0m"
        fi
    else
        echo -e "\e[33m$CMDLINE_TXT not found — skipping cmdline.txt modification.\e[0m"
    fi

    # Install Plymouth and themes
    echo -e "\e[90mInstalling Plymouth and themes...\e[0m"
    sudo apt install -y plymouth plymouth-themes > /dev/null 2>&1 &
    spinner $! "Installing Plymouth..."

    # List available themes and store them in an array
    THEMES=()
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        readarray -t THEMES < <(plymouth-set-default-theme -l 2>/dev/null || true)
    fi

    if [ ${#THEMES[@]} -eq 0 ]; then
        echo -e "\e[33mNo Plymouth themes found or plymouth-set-default-theme not available. Skipping theme setup.\e[0m"
    else
        echo -e "\e[94mPlease choose a theme (enter the number, default: 8 - spinner):\e[0m"
        select SELECTED_THEME in "${THEMES[@]}"; do
            # If user just pressed Enter, use default (option 8)
            if [[ -z "$REPLY" ]]; then
                SELECTED_THEME="${THEMES[7]}"  # Array index 7 = option 8
            fi
            
            if [[ -n "$SELECTED_THEME" ]]; then
                echo -e "\e[90mSetting Plymouth theme to $SELECTED_THEME...\e[0m"
                sudo plymouth-set-default-theme "$SELECTED_THEME"
                sudo update-initramfs -u > /dev/null 2>&1 &
                spinner $! "Updating initramfs..."
                echo -e "\e[32m✔\e[0m Plymouth splash screen installed and configured with $SELECTED_THEME theme."
                break
            else
                echo -e "\e[31mInvalid selection, please try again.\e[0m"
            fi
        done
    fi
fi

# Configure a resolution
echo
if ask_user "Do you want to set the screen resolution in cmdline.txt and the labwc autostart file?"; then

    # Check if edid-decode is installed; if not, install it
    if ! command -v edid-decode &> /dev/null; then
        echo -e "\e[90mInstalling required tool edid-decode, please wait...\e[0m"
        sudo apt install -y edid-decode > /dev/null 2>&1 &
        spinner $! "Installing edid-decode..."
        echo -e "\e[32mrequired tool installed successfully!\e[0m"
    fi

    # Try to read EDID; many Pi setups use /sys/class/drm/card1-HDMI-A-1/edid or card0
    EDID_PATH=""
    if [ -r /sys/class/drm/card1-HDMI-A-1/edid ]; then
        EDID_PATH="/sys/class/drm/card1-HDMI-A-1/edid"
    elif [ -r /sys/class/drm/card0-HDMI-A-1/edid ]; then
        EDID_PATH="/sys/class/drm/card0-HDMI-A-1/edid"
    fi

    available_resolutions=()

    if [ -n "$EDID_PATH" ]; then
        edid_output=$(sudo cat "$EDID_PATH" | edid-decode 2>/dev/null || true)
        while IFS= read -r line; do
            if [[ "$line" =~ ([0-9]+)x([0-9]+)[[:space:]]+([0-9]+\.[0-9]+|[0-9]+)\ Hz ]]; then
                resolution="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"
                frequency="${BASH_REMATCH[3]}"
                formatted="${resolution}@${frequency}"
                available_resolutions+=("$formatted")
            fi
        done <<< "$edid_output"
    fi

    # Fallback to default list if no resolutions are found
    if [ ${#available_resolutions[@]} -eq 0 ]; then
        echo -e "\e[33mNo resolutions found via EDID. Using default list.\e[0m"
        available_resolutions=("1920x1080@60" "1280x720@60" "1024x768@60" "1600x900@60" "1366x768@60")
    fi

    # Prompt user to choose a resolution
    echo -e "\e[94mPlease choose a resolution (type in the number):\e[0m"
    select RESOLUTION in "${available_resolutions[@]}"; do
        if [[ -n "$RESOLUTION" ]]; then
            echo -e "\e[32mYou selected $RESOLUTION\e[0m"
            break
        else
            echo -e "\e[33mInvalid selection, please try again.\e[0m"
        fi
    done

    # Add the selected resolution to /boot/firmware/cmdline.txt if not already present
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_FILE" ]; then
        if ! grep -q "video=" "$CMDLINE_FILE"; then
            echo -e "\e[90mAdding video=HDMI-A-1:$RESOLUTION to $CMDLINE_FILE...\e[0m"
            # Prepend video=... at start of single-line cmdline.txt
            sudo sed -i "1s/^/video=HDMI-A-1:$RESOLUTION /" "$CMDLINE_FILE"
            echo -e "\e[32m✔\e[0m Resolution added to cmdline.txt successfully!"
        else
            echo -e "\e[33mcmdline.txt already contains a video entry. No changes made.\e[0m"
        fi
    else
        echo -e "\e[33m$CMDLINE_FILE not found — skipping cmdline modification.\e[0m"
    fi

    # Add the command to labwc autostart if not present
    AUTOSTART_FILE="$HOME_DIR/.config/labwc/autostart"
    touch "$AUTOSTART_FILE"
    if ! grep -q "wlr-randr --output HDMI-A-1 --mode $RESOLUTION" "$AUTOSTART_FILE" 2>/dev/null; then
        echo "wlr-randr --output HDMI-A-1 --mode $RESOLUTION" >> "$AUTOSTART_FILE"
        echo -e "\e[32m✔\e[0m Resolution command added to labwc autostart file successfully!"
    else
        echo -e "\e[33mAutostart file already contains this resolution command. No changes made.\e[0m"
    fi
fi

# cleaning up apt caches
echo -e "\e[90mCleaning up apt caches, please wait...\e[0m"
sudo apt clean > /dev/null 2>&1 &
spinner $! "Cleaning up apt caches..."

# Print completion message
echo -e "\e[32m✔\e[0m \e[32mSetup completed successfully! Please reboot your system.\e[0m"