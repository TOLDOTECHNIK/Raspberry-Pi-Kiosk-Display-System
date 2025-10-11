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
# 2025-10-08 v1.4: Added screen rotation option, network wait before launching browser, auto-hide mouse cursor
# 2025-10-09 v1.5: Added audio to HDMI option, splash screen improvements
# 2025-10-10 v1.6: Added TV remote CEC support

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

# Function to prompt the user for y/n input with default value
ask_user() {
    local prompt="$1"
    local default="$2"
    local default_text=""
    
    if [ "$default" = "y" ]; then
        default_text=" [default: yes]"
    elif [ "$default" = "n" ]; then
        default_text=" [default: no]"
    fi
    
    while true; do
        read -p "$prompt$default_text (y/n): " yn
        # If empty (just Enter pressed), use default
        yn="${yn:-$default}"
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# update the package list?
echo
if ask_user "Do you want to update the package list?" "y"; then
    echo -e "\e[90mUpdating the package list, please wait...\e[0m"
    sudo apt update > /dev/null 2>&1 &
    spinner $! "Updating package list..."
fi

# upgrade installed packages?
echo
if ask_user "Do you want to upgrade installed packages?" "y"; then
    echo -e "\e[90mUpgrading installed packages. THIS MAY TAKE SOME TIME, please wait...\e[0m"
    sudo apt upgrade -y > /dev/null 2>&1 &
    spinner $! "Upgrading installed packages..."
fi

# install Wayland/labwc packages?
echo
if ask_user "Do you want to install Wayland and labwc packages?" "y"; then
    echo -e "\e[90mInstalling Wayland packages, please wait...\e[0m"
    sudo apt install --no-install-recommends -y labwc wlr-randr seatd > /dev/null 2>&1 &
    spinner $! "Installing Wayland packages..."
fi

# --- Smart Chromium install + autostart snippet ---
echo
if ask_user "Do you want to install Chromium Browser?" "y"; then
    # detect available chromium package name (prefer 'chromium')
    CHROMIUM_PKG=""
    if apt-cache show chromium >/dev/null 2>&1; then
        CHROMIUM_PKG="chromium"
    elif apt-cache show chromium-browser >/dev/null 2>&1; then
        CHROMIUM_PKG="chromium-browser"
    fi

    if [ -z "$CHROMIUM_PKG" ]; then
        echo -e "\e[33mNo chromium package found in APT. You may need to enable the appropriate repository or install manually.\e[0m"
    else
        echo -e "\e[90mInstalling $CHROMIUM_PKG. THIS MAY TAKE SOME TIME, please wait...\e[0m"
        sudo apt install --no-install-recommends -y "$CHROMIUM_PKG" > /dev/null 2>&1 &
        spinner $! "Installing $CHROMIUM_PKG..."
    fi
fi

# install and configure greetd?
echo
if ask_user "Do you want to install and configure greetd for auto start of labwc?" "y"; then
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
if ask_user "Do you want to create an autostart (chromium) script for labwc?" "y"; then
    read -p "Enter the URL to open in Chromium [default: https://webglsamples.org...]: " USER_URL
    USER_URL="${USER_URL:-https://webglsamples.org/aquarium/aquarium.html}"

    # Ask about incognito mode (default: no)
    echo
    INCOGNITO_FLAG=""
    if ask_user "Start browser in incognito mode?" "n"; then
        INCOGNITO_FLAG="--incognito "
    fi

    # Ask about network wait (default: no)
    echo
    NETWORK_WAIT=""
    if ask_user "Wait for network connectivity before launching Chromium?" "n"; then
        read -p "Enter host to ping for network check [default: 8.8.8.8]: " PING_HOST
        PING_HOST="${PING_HOST:-8.8.8.8}"
        read -p "Enter maximum wait time in seconds [default: 30]: " MAX_WAIT
        MAX_WAIT="${MAX_WAIT:-30}"

        NETWORK_WAIT="  # Wait for network connectivity (max ${MAX_WAIT}s)
  for i in \$(seq 1 $MAX_WAIT); do
    if ping -c 1 -W 2 $PING_HOST > /dev/null 2>&1; then
      break
    fi
    sleep 1
  done
"
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

        if [ -n "$NETWORK_WAIT" ]; then
            cat >> "$LABWC_AUTOSTART_FILE" << EOL
# Launch Chromium in kiosk mode (with network wait)
(
$NETWORK_WAIT
    $CHROMIUM_BIN ${INCOGNITO_FLAG}--autoplay-policy=no-user-gesture-required --kiosk $USER_URL
) &
EOL
        else
            echo "$CHROMIUM_BIN ${INCOGNITO_FLAG}--autoplay-policy=no-user-gesture-required --kiosk $USER_URL &" >> "$LABWC_AUTOSTART_FILE"
        fi

        echo -e "\e[32m✔\e[0m labwc autostart script has been created or updated at $LABWC_AUTOSTART_FILE."
    fi
fi

# configure cursor hiding for labwc?
echo
if ask_user "Do you want to hide the mouse cursor in kiosk mode?" "y"; then
    # Install wtype if not present
    if ! command -v wtype &> /dev/null; then
        echo -e "\e[90mInstalling wtype for cursor control, please wait...\e[0m"
        sudo apt install -y wtype > /dev/null 2>&1 &
        spinner $! "Installing wtype..."
    fi

    # Create labwc config directory
    LABWC_CONFIG_DIR="$HOME_DIR/.config/labwc"
    mkdir -p "$LABWC_CONFIG_DIR"
    
    # Create or modify rc.xml
    RC_XML="$LABWC_CONFIG_DIR/rc.xml"

    if [ -f "$RC_XML" ]; then
        # Check if HideCursor already exists
        if grep -q "HideCursor" "$RC_XML" 2>/dev/null; then
            echo -e "\e[33mrc.xml already contains HideCursor configuration. No changes made.\e[0m"
        else
            echo -e "\e[90mAdding HideCursor keybind to existing rc.xml...\e[0m"
            # Insert before closing </openbox_config> or </keyboard> tag
            if grep -q "</keyboard>" "$RC_XML"; then
                sudo sed -i 's|</keyboard>|  <keybind key="W-h">\n    <action name="HideCursor"/>\n    <action name="WarpCursor" to="output" x="1" y="1"/>\n  </keybind>\n</keyboard>|' "$RC_XML"
            else
                echo -e "\e[33mCouldn't find </keyboard> tag in rc.xml. Please add HideCursor keybind manually.\e[0m"
            fi
        fi
    else
        # Create new rc.xml with HideCursor configuration
        echo -e "\e[90mCreating rc.xml with HideCursor configuration...\e[0m"
        cat > "$RC_XML" << 'EOL'
<?xml version="1.0"?>
<labwc_config>
  <keyboard>
    <keybind key="W-h">
      <action name="HideCursor"/>
      <action name="WarpCursor" to="output" x="1" y="1"/>
    </keybind>
  </keyboard>
</labwc_config>
EOL
        echo -e "\e[32m✔\e[0m rc.xml created successfully!"
    fi

    # Add wtype command to autostart
    LABWC_AUTOSTART_FILE="$LABWC_CONFIG_DIR/autostart"
    touch "$LABWC_AUTOSTART_FILE"

    if grep -q "wtype.*logo.*-k h" "$LABWC_AUTOSTART_FILE" 2>/dev/null; then
        echo -e "\e[33mAutostart already contains cursor hiding command. No changes made.\e[0m"
    else
        echo -e "\e[90mAdding cursor hiding command to autostart...\e[0m"
        cat >> "$LABWC_AUTOSTART_FILE" << 'EOL'

# Hide cursor on startup (simulate Win+H hotkey)
sleep 1 && wtype -M logo -k h -m logo &
EOL
        echo -e "\e[32m✔\e[0m Cursor hiding configured successfully!"
    fi
fi

# install splash screen?
echo
if ask_user "Do you want to install the splash screen?" "y"; then
    # Install Plymouth and themes including pix-plym-splash
    echo -e "\e[90mInstalling splash screen and themes. THIS MAY TAKE SOME TIME, please wait...\e[0m"
    sudo apt-get install -y plymouth plymouth-themes pix-plym-splash > /dev/null 2>&1 &
    spinner $! "Installing splash screen..."

    # Check if pix theme is available
    if [ ! -e /usr/share/plymouth/themes/pix/pix.script ]; then
        echo -e "\e[33mWarning: pix theme not found after installation. Splash screen may not work correctly.\e[0m"
    else
        echo -e "\e[90mSetting splash screen theme to pix...\e[0m"
        sudo plymouth-set-default-theme pix

        # Download and replace the splash.png with custom logo
        echo -e "\e[90mDownloading custom splash logo...\e[0m"
        SPLASH_URL="https://raw.githubusercontent.com/TOLDOTECHNIK/Raspberry-Pi-Kiosk-Display-System/main/_assets/splashscreens/splash.png"
        SPLASH_PATH="/usr/share/plymouth/themes/pix/splash.png"

        if sudo wget -q "$SPLASH_URL" -O "$SPLASH_PATH"; then
            echo -e "\e[32m✔\e[0m Custom splash logo installed."
        else
            echo -e "\e[33mWarning: Failed to download custom splash logo. Using default.\e[0m"
        fi

        sudo update-initramfs -u > /dev/null 2>&1 &
        spinner $! "Updating initramfs..."
    fi

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
        fi
        if grep -q "console=tty1" "$CMDLINE_TXT"; then
            echo -e "\e[90mReplacing console=tty1 with console=tty3 in $CMDLINE_TXT...\e[0m"
            sudo sed -i 's/console=tty1/console=tty3/' "$CMDLINE_TXT"
        elif ! grep -q "console=tty3" "$CMDLINE_TXT"; then
            echo -e "\e[90mAdding console=tty3 to $CMDLINE_TXT...\e[0m"
            sudo sed -i 's/$/ console=tty3/' "$CMDLINE_TXT"
        fi
        echo -e "\e[32m✔\e[0m Splash screen installed and configured with pix theme."
    else
        echo -e "\e[33m$CMDLINE_TXT not found — skipping cmdline.txt modification.\e[0m"
    fi
fi

# Configure a resolution
echo
if ask_user "Do you want to set the screen resolution in cmdline.txt and the labwc autostart file?" "y"; then

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

# Configure screen orientation
echo
if ask_user "Do you want to set the screen orientation (rotation)?" "n"; then
    echo -e "\e[94mPlease choose an orientation:\e[0m"
    orientations=("normal (0°)" "90° clockwise" "180°" "270° clockwise")
    transform_values=("normal" "90" "180" "270")

    select orientation in "${orientations[@]}"; do
        if [[ -n "$orientation" ]]; then
            idx=$((REPLY - 1))
            TRANSFORM="${transform_values[$idx]}"
            echo -e "\e[32mYou selected $orientation\e[0m"
            break
        else
            echo -e "\e[33mInvalid selection, please try again.\e[0m"
        fi
    done

    # Add to labwc autostart
    AUTOSTART_FILE="$HOME_DIR/.config/labwc/autostart"
    touch "$AUTOSTART_FILE"
    if ! grep -q "wlr-randr.*--transform" "$AUTOSTART_FILE" 2>/dev/null; then
        echo "wlr-randr --output HDMI-A-1 --transform $TRANSFORM" >> "$AUTOSTART_FILE"
        echo -e "\e[32m✔\e[0m Screen orientation added to labwc autostart file successfully!"
    else
        echo -e "\e[33mAutostart file already contains a transform command. No changes made.\e[0m"
    fi
fi

# Force audio to HDMI?
echo
if ask_user "Do you want to force audio output to HDMI?" "y"; then
    CONFIG_TXT="/boot/firmware/config.txt"
    if [ -f "$CONFIG_TXT" ]; then
        # Check if dtparam=audio exists (uncommented)
        if grep -q "^dtparam=audio=" "$CONFIG_TXT"; then
            # Check if it's already set to off
            if grep -q "^dtparam=audio=off" "$CONFIG_TXT"; then
                echo -e "\e[33m$CONFIG_TXT already has dtparam=audio=off. No changes made.\e[0m"
            else
                # Replace existing audio parameter
                echo -e "\e[90mModifying existing dtparam=audio in $CONFIG_TXT...\e[0m"
                sudo sed -i 's/^dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT"
                echo -e "\e[32m✔\e[0m Audio parameter updated to force HDMI output!"
            fi
        elif grep -q "^#dtparam=audio=" "$CONFIG_TXT"; then
            # Uncomment and set to off
            echo -e "\e[90mUncommenting and setting dtparam=audio=off in $CONFIG_TXT...\e[0m"
            sudo sed -i 's/^#dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT"
            echo -e "\e[32m✔\e[0m Audio parameter set to force HDMI output!"
        else
            # Add new parameter
            echo -e "\e[90mAdding dtparam=audio=off to $CONFIG_TXT...\e[0m"
            sudo bash -c "echo 'dtparam=audio=off' >> '$CONFIG_TXT'"
            echo -e "\e[32m✔\e[0m Audio parameter added to force HDMI output!"
        fi
    else
        echo -e "\e[33m$CONFIG_TXT not found — skipping audio configuration.\e[0m"
    fi
fi

# Enable TV remote CEC support?
echo
if ask_user "Do you want to enable TV remote control via HDMI-CEC?" "n"; then
    echo -e "\e[90mInstalling CEC utilities, please wait...\e[0m"
    sudo apt-get install -y ir-keytable > /dev/null 2>&1 &
    spinner $! "Installing CEC utilities..."

    # Create custom CEC keymap directory
    echo -e "\e[90mCreating custom CEC keymap...\e[0m"
    sudo mkdir -p /etc/rc_keymaps

    # Create custom keymap file
    sudo bash -c "cat > /etc/rc_keymaps/custom-cec.toml" << 'EOL'
[[protocols]]
name = "custom_cec"
protocol = "cec"
[protocols.scancodes]
0x00 = "KEY_ENTER"
0x01 = "KEY_UP"
0x02 = "KEY_DOWN"
0x03 = "KEY_LEFT"
0x04 = "KEY_RIGHT"
0x09 = "KEY_EXIT"
0x0d = "KEY_BACK"
0x44 = "KEY_PLAYPAUSE"
0x45 = "KEY_STOPCD"
0x46 = "KEY_PAUSECD"
EOL

    echo -e "\e[32m✔\e[0m Custom CEC keymap created!"

    # Create systemd service for CEC setup
    echo -e "\e[90mCreating CEC setup service...\e[0m"
    sudo bash -c "cat > /etc/systemd/system/cec-setup.service" << 'EOL'
[Unit]
Description=CEC Remote Control Setup
After=multi-user.target
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/bin/cec-ctl -d /dev/cec1 --playback
ExecStart=/bin/sleep 2
ExecStart=/usr/bin/cec-ctl -d /dev/cec1 --active-source phys-addr=1.0.0.0
ExecStart=/bin/sleep 1
ExecStart=/usr/bin/ir-keytable -c -s rc0 -w /etc/rc_keymaps/custom-cec.toml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

    # Enable the service
    echo -e "\e[90mEnabling CEC setup service...\e[0m"
    sudo systemctl daemon-reload > /dev/null 2>&1
    sudo systemctl enable cec-setup.service > /dev/null 2>&1 &
    spinner $! "Enabling CEC service..."

    echo -e "\e[32m✔\e[0m TV remote CEC support configured successfully!"
    echo -e "\e[90mNote: Make sure HDMI-CEC (SimpLink/Anynet+/Bravia Sync) is enabled on your TV.\e[0m"
fi

# cleaning up apt caches
echo -e "\e[90mCleaning up apt caches, please wait...\e[0m"
sudo apt clean > /dev/null 2>&1 &
spinner $! "Cleaning up apt caches..."

# Print completion message and ask for reboot
echo -e "\e[32m✔\e[0m \e[32mSetup completed successfully!\e[0m"
echo
if ask_user "Do you want to reboot now?" "n"; then
    echo -e "\e[90mRebooting system...\e[0m"
    sudo reboot
else
    echo -e "\e[33mPlease remember to reboot your system manually for all changes to take effect.\e[0m"
fi