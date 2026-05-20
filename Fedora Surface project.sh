#!/bin/bash
# ==============================================================================
# Linux-Surface Installer & Manager for Fedora 44 KDE Plasma
# Based on: https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup#Fedora
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

REPO_URL="https://pkg.surfacelinux.com/fedora/linux-surface.repo"
REPO_FILE="/etc/yum.repos.d/linux-surface.repo"
CAL_DIR="/etc/iptsd.d"
CAL_FILE="/etc/iptsd.d/90-calibration.conf"

# Default calibration values (optimized for medium to big size fingers)
declare -A CAL_DEFAULTS=(
    ["Touchscreen_Overshoot"]="0.5"
    ["Touchscreen_SizeMin"]="0.325"
    ["Touchscreen_SizeMax"]="2.159"
    ["Touchpad_Overshoot"]="0.5"
    ["Contacts_NeutralValue"]="0"
    ["Contacts_ActivationThreshold"]="24"
    ["Contacts_DeactivationThreshold"]="20"
    ["Contacts_SizeThresholdMin"]="0.1"
    ["Contacts_SizeThresholdMax"]="0.5"
    ["Contacts_PositionThresholdMax"]="2"
    ["Contacts_OrientationThresholdMin"]="1"
    ["Contacts_OrientationThresholdMax"]="5"
    ["Contacts_SizeMin"]="0.1"
    ["Contacts_SizeMax"]="2.0"
    ["Contacts_AspectMin"]="0.521"
    ["Contacts_AspectMax"]="3.323"
    ["Stylus_TipDistance"]="0"
    ["DFT_PositionMinAmp"]="50"
    ["DFT_PositionMinMag"]="2000"
    ["DFT_PositionExp"]="-0.7"
    ["DFT_ButtonMinMag"]="1000"
    ["DFT_FreqMinMag"]="10000"
)

# ==============================================================================
# Helper Functions
# ==============================================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║           Linux-Surface Manager for Fedora 44 KDE Plasma             ║"
    echo "║         Patched Kernel | Touch | Stylus | Secure Boot               ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

pause() {
    echo ""
    read -rp "$(echo -e "${YELLOW}Press Enter to continue...${NC}")" dummy
}

ask_yes_no() {
    local prompt="$1"
    while true; do
        read -rp "$(echo -e "${YELLOW}$prompt [y/N]: ${NC}")" yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

check_kernel_surface() {
    if uname -r | grep -qi "surface"; then
        return 0
    else
        return 1
    fi
}

check_pkg_installed() {
    rpm -q "$1" &>/dev/null
}

check_repo_added() {
    [[ -f "$REPO_FILE" ]] || grep -r "surfacelinux.com" /etc/yum.repos.d/ &>/dev/null
}

# ==============================================================================
# Menu 1: Check System Status
# ==============================================================================

menu_check_status() {
    echo -e "${BLUE}========== System Status Check ==========${NC}"
    echo ""

    # OS Check
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo -e "OS: ${GREEN}$NAME $VERSION_ID${NC}"
    fi

    # Kernel
    echo -e "Current Kernel: ${CYAN}$(uname -r)${NC}"
    if check_kernel_surface; then
        echo -e "Surface Kernel: ${GREEN}YES ✓${NC}"
    else
        echo -e "Surface Kernel: ${RED}NO ✗${NC}  ${YELLOW}(You are using the default Fedora kernel)${NC}"
    fi
    echo ""

    # Packages
    local pkgs=("kernel-surface" "iptsd" "libwacom-surface" "surface-secureboot" "kernel-surface-default-watchdog")
    for pkg in "${pkgs[@]}"; do
        if check_pkg_installed "$pkg"; then
            echo -e "  ${GREEN}✓${NC} $pkg"
        else
            echo -e "  ${RED}✗${NC} $pkg"
        fi
    done
    echo ""

    # Repository
    if check_repo_added; then
        echo -e "Repository: ${GREEN}Added ✓${NC}"
    else
        echo -e "Repository: ${RED}Not Added ✗${NC}"
    fi

    # Services
    echo ""
    echo -e "${BLUE}Services:${NC}"
    if systemctl is-active --quiet iptsd 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} iptsd (active)"
    else
        echo -e "  ${RED}✗${NC} iptsd (inactive or not found)"
    fi

    if systemctl is-enabled --quiet linux-surface-default-watchdog.path 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} linux-surface-default-watchdog.path (enabled)"
    else
        echo -e "  ${RED}✗${NC} linux-surface-default-watchdog.path (not enabled)"
    fi

    # Calibration
    echo ""
    if [[ -f "$CAL_FILE" ]]; then
        echo -e "Calibration: ${GREEN}Found${NC} at $CAL_FILE"
    else
        echo -e "Calibration: ${RED}Not Found${NC}"
    fi

    echo ""
    echo -e "${MAGENTA}Tip: If Surface Kernel shows NO, run option 7 after install to set it as default.${NC}"
    pause
}

# ==============================================================================
# Menu 2: Update Fedora
# ==============================================================================

menu_update_fedora() {
    echo -e "${BLUE}========== Update Fedora ==========${NC}"
    echo -e "${YELLOW}This will run: sudo dnf update -y && sudo dnf upgrade -y${NC}"
    echo ""

    if ask_yes_no "Proceed with system update?"; then
        sudo dnf update -y
        sudo dnf upgrade -y
        echo ""
        echo -e "${GREEN}[+] Fedora updated successfully.${NC}"
    else
        echo -e "${YELLOW}Skipped.${NC}"
    fi
    pause
}

# ==============================================================================
# Menu 3: Add Repository
# ==============================================================================

menu_add_repo() {
    echo -e "${BLUE}========== Add linux-surface Repository ==========${NC}"

    if check_repo_added; then
        echo -e "${GREEN}Repository already exists.${NC}"
        if ask_yes_no "Re-add/refresh repository?"; then
            sudo rm -f "$REPO_FILE"
        else
            pause
            return
        fi
    fi

    echo -e "${CYAN}Trying DNF5 method first...${NC}"
    if sudo dnf config-manager addrepo --from-repofile="$REPO_URL" 2>/dev/null; then
        echo -e "${GREEN}[+] Repository added via DNF5 config-manager.${NC}"
    else
        echo -e "${YELLOW}[!] DNF5 method failed. Trying DNF4 method...${NC}"
        if sudo dnf config-manager --add-repo="$REPO_URL" 2>/dev/null; then
            echo -e "${GREEN}[+] Repository added via DNF4 config-manager.${NC}"
        else
            echo -e "${YELLOW}[!] Both methods failed. Creating repo file manually...${NC}"
            sudo tee "$REPO_FILE" > /dev/null <<EOF
[linux-surface]
name=Linux Surface
baseurl=https://pkg.surfacelinux.com/fedora/\$releasever/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://pkg.surfacelinux.com/fedora/linux-surface.pub
EOF
            echo -e "${GREEN}[+] Repository file created manually at $REPO_FILE${NC}"
        fi
    fi
    pause
}

# ==============================================================================
# Menu 4: Install Kernel & Dependencies
# ==============================================================================

menu_install_kernel() {
    echo -e "${BLUE}========== Install linux-surface Kernel ==========${NC}"

    if check_pkg_installed "kernel-surface"; then
        echo -e "${GREEN}kernel-surface is already installed.${NC}"
        if ! ask_yes_no "Reinstall / update kernel-surface?"; then
            pause
            return
        fi
    fi

    echo -e "${CYAN}Installing: kernel-surface, iptsd, libwacom-surface${NC}"
    echo -e "${YELLOW}Note: --allowerasing is used to handle potential conflicts.${NC}"
    echo ""

    sudo dnf install --allowerasing -y kernel-surface iptsd libwacom-surface

    echo ""
    echo -e "${GREEN}[+] Kernel and dependencies installed.${NC}"

    if ask_yes_no "Also install kernel-surface-devel (needed for building kernel modules)?"; then
        sudo dnf install -y kernel-surface-devel
    fi

    pause
}

# ==============================================================================
# Menu 5: Install Secure Boot Key
# ==============================================================================

menu_secureboot() {
    echo -e "${BLUE}========== Install Secure Boot Key ==========${NC}"
    echo -e "${YELLOW}This installs the MOK key so the Surface kernel boots with Secure Boot ON.${NC}"

    if check_pkg_installed "surface-secureboot"; then
        echo -e "${GREEN}surface-secureboot is already installed.${NC}"
        if ! ask_yes_no "Reinstall to re-trigger MOK enrollment?"; then
            pause
            return
        fi
        sudo dnf remove -y surface-secureboot
    fi

    echo ""
    sudo dnf install -y surface-secureboot

    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  IMPORTANT: After reboot, a BLUE menu (MokManager) will appear.      ║${NC}"
    echo -e "${MAGENTA}║                                                                        ║${NC}"
    echo -e "${MAGENTA}║  1. Select \"Enroll Key\" or \"Enroll MOK\"                                ║${NC}"
    echo -e "${MAGENTA}║  2. Select \"Continue\"                                                  ║${NC}"
    echo -e "${MAGENTA}║  3. Enter password:  ${GREEN}surface${MAGENTA}                                            ║${NC}"
    echo -e "${MAGENTA}║  4. Select \"Reboot\"                                                    ║${NC}"
    echo -e "${MAGENTA}║                                                                        ║${NC}"
    echo -e "${MAGENTA}║  NOTE: MokManager uses QWERTY layout!                                  ║${NC}"
    echo -e "${MAGENTA}║  If you miss the menu, uninstall then reinstall this package.          ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    pause
}

# ==============================================================================
# Menu 6: Reboot Instructions
# ==============================================================================

menu_reboot_instructions() {
    echo -e "${BLUE}========== Reboot & MOK Enrollment ==========${NC}"
    echo ""
    echo -e "${YELLOW}You MUST reboot now if you just installed the secureboot key.${NC}"
    echo ""
    echo -e "${CYAN}After reboot, you will see a BLUE screen (MokManager):${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} Select ${YELLOW}Enroll Key${NC} → ${YELLOW}Continue${NC}"
    echo -e "  ${GREEN}2.${NC} Type password: ${MAGENTA}surface${NC}"
    echo -e "  ${GREEN}3.${NC} Select ${YELLOW}Reboot${NC}"
    echo ""
    echo -e "${RED}If you skip this step, the Surface kernel will NOT boot with Secure Boot ON.${NC}"
    echo ""

    if ask_yes_no "Reboot now?"; then
        echo -e "${GREEN}Rebooting...${NC}"
        sudo reboot
    else
        echo -e "${YELLOW}Reboot skipped. Remember to reboot manually later!${NC}"
    fi
    pause
}

# ==============================================================================
# Menu 7: Set Surface Kernel as Default
# ==============================================================================

menu_set_default_kernel() {
    echo -e "${BLUE}========== Set Surface Kernel as Default ==========${NC}"
    echo -e "${YELLOW}This prevents the stock Fedora kernel from overriding the Surface kernel on updates.${NC}"
    echo ""

    if ! check_pkg_installed "kernel-surface-default-watchdog"; then
        echo -e "${YELLOW}Watchdog package not installed. Installing now...${NC}"
        sudo dnf install -y kernel-surface-default-watchdog
    fi

    echo -e "${CYAN}Enabling linux-surface-default-watchdog.path...${NC}"
    sudo systemctl enable --now linux-surface-default-watchdog.path

    echo -e "${CYAN}Running watchdog script...${NC}"
    sudo linux-surface-default-watchdog.py

    echo ""
    echo -e "${GREEN}[+] Surface kernel is now set as the default boot target.${NC}"
    echo -e "${YELLOW}After reboot, run 'uname -a' and verify it contains 'surface'.${NC}"
    pause
}

# ==============================================================================
# Menu 8: Apply Default Calibration (Medium to Big Fingers)
# ==============================================================================

menu_default_calibration() {
    echo -e "${BLUE}========== Apply Default Touch Calibration ==========${NC}"
    echo ""
    echo -e "${MAGENTA}NOTE: These values are tuned for MEDIUM to BIG size fingers.${NC}"
    echo -e "${MAGINTA}If you have small fingers or want different sensitivity, use Custom Calibration (option 9).${NC}"
    echo ""

    if ask_yes_no "Apply default calibration for medium/big fingers?"; then
        sudo mkdir -p "$CAL_DIR"

        sudo tee "$CAL_FILE" > /dev/null <<EOF
# Linux-Surface iptsd Calibration
# Optimized for: Medium to Big Size Fingers
# Generated by linux-surface-manager script

[Touchscreen]
Overshoot = ${CAL_DEFAULTS["Touchscreen_Overshoot"]}
SizeMin = ${CAL_DEFAULTS["Touchscreen_SizeMin"]}
SizeMax = ${CAL_DEFAULTS["Touchscreen_SizeMax"]}

[Touchpad]
Overshoot = ${CAL_DEFAULTS["Touchpad_Overshoot"]}

[Contacts]
NeutralValue = ${CAL_DEFAULTS["Contacts_NeutralValue"]}
ActivationThreshold = ${CAL_DEFAULTS["Contacts_ActivationThreshold"]}
DeactivationThreshold = ${CAL_DEFAULTS["Contacts_DeactivationThreshold"]}
SizeThresholdMin = ${CAL_DEFAULTS["Contacts_SizeThresholdMin"]}
SizeThresholdMax = ${CAL_DEFAULTS["Contacts_SizeThresholdMax"]}
PositionThresholdMax = ${CAL_DEFAULTS["Contacts_PositionThresholdMax"]}
OrientationThresholdMin = ${CAL_DEFAULTS["Contacts_OrientationThresholdMin"]}
OrientationThresholdMax = ${CAL_DEFAULTS["Contacts_OrientationThresholdMax"]}
SizeMin = ${CAL_DEFAULTS["Contacts_SizeMin"]}
SizeMax = ${CAL_DEFAULTS["Contacts_SizeMax"]}
AspectMin = ${CAL_DEFAULTS["Contacts_AspectMin"]}
AspectMax = ${CAL_DEFAULTS["Contacts_AspectMax"]}

[Stylus]
TipDistance = ${CAL_DEFAULTS["Stylus_TipDistance"]}

[DFT]
PositionMinAmp = ${CAL_DEFAULTS["DFT_PositionMinAmp"]}
PositionMinMag = ${CAL_DEFAULTS["DFT_PositionMinMag"]}
PositionExp = ${CAL_DEFAULTS["DFT_PositionExp"]}
ButtonMinMag = ${CAL_DEFAULTS["DFT_ButtonMinMag"]}
FreqMinMag = ${CAL_DEFAULTS["DFT_FreqMinMag"]}
EOF

        echo ""
        echo -e "${GREEN}[+] Calibration applied to $CAL_FILE${NC}"
        echo -e "${YELLOW}Please reboot for changes to take full effect.${NC}"
    else
        echo -e "${YELLOW}Skipped.${NC}"
    fi
    pause
}

# ==============================================================================
# Menu 9: Custom Calibration (Interactive)
# ==============================================================================

menu_custom_calibration() {
    echo -e "${BLUE}========== Custom Touch Calibration ==========${NC}"
    echo ""
    echo -e "${CYAN}Enter new values or press Enter to keep current default.${NC}"
    echo -e "${YELLOW}Current defaults are shown in [brackets].${NC}"
    echo ""

    read_value() {
        local key="$1"
        local desc="$2"
        local current="${CAL_DEFAULTS[$key]}"
        read -rp "$(echo -e "${CYAN}$desc${NC} [$current]: ")" input
        if [[ -n "$input" ]]; then
            CAL_DEFAULTS["$key"]="$input"
        fi
    }

    echo -e "${MAGENTA}--- Touchscreen ---${NC}"
    read_value "Touchscreen_Overshoot" "Overshoot (cm outside screen allowed)"
    read_value "Touchscreen_SizeMin"   "SizeMin (min contact diameter)"
    read_value "Touchscreen_SizeMax"   "SizeMax (max contact diameter)"

    echo ""
    echo -e "${MAGENTA}--- Touchpad ---${NC}"
    read_value "Touchpad_Overshoot"    "Overshoot (cm outside touchpad allowed)"

    echo ""
    echo -e "${MAGENTA}--- Contacts (Finger Detection) ---${NC}"
    read_value "Contacts_NeutralValue"         "NeutralValue (0-255)"
    read_value "Contacts_ActivationThreshold"  "ActivationThreshold (0-255)"
    read_value "Contacts_DeactivationThreshold" "DeactivationThreshold (0-255)"
    read_value "Contacts_SizeThresholdMin"     "SizeThresholdMin (cm)"
    read_value "Contacts_SizeThresholdMax"     "SizeThresholdMax (cm)"
    read_value "Contacts_PositionThresholdMax" "PositionThresholdMax (cm)"
    read_value "Contacts_OrientationThresholdMin" "OrientationThresholdMin (degrees)"
    read_value "Contacts_OrientationThresholdMax" "OrientationThresholdMax (degrees)"
    read_value "Contacts_SizeMin"              "SizeMin (cm)"
    read_value "Contacts_SizeMax"              "SizeMax (cm)"
    read_value "Contacts_AspectMin"            "AspectMin (ratio)"
    read_value "Contacts_AspectMax"            "AspectMax (ratio)"

    echo ""
    echo -e "${MAGENTA}--- Stylus ---${NC}"
    read_value "Stylus_TipDistance" "TipDistance (cm offset for tilt)"

    echo ""
    echo -e "${MAGENTA}--- DFT ---${NC}"
    read_value "DFT_PositionMinAmp"  "PositionMinAmp"
    read_value "DFT_PositionMinMag"  "PositionMinMag"
    read_value "DFT_PositionExp"     "PositionExp"
    read_value "DFT_ButtonMinMag"    "ButtonMinMag"
    read_value "DFT_FreqMinMag"      "FreqMinMag"

    echo ""
    if ask_yes_no "Apply these custom values?"; then
        sudo mkdir -p "$CAL_DIR"
        sudo tee "$CAL_FILE" > /dev/null <<EOF
# Linux-Surface iptsd Calibration
# Custom user-defined values
# Generated by linux-surface-manager script

[Touchscreen]
Overshoot = ${CAL_DEFAULTS["Touchscreen_Overshoot"]}
SizeMin = ${CAL_DEFAULTS["Touchscreen_SizeMin"]}
SizeMax = ${CAL_DEFAULTS["Touchscreen_SizeMax"]}

[Touchpad]
Overshoot = ${CAL_DEFAULTS["Touchpad_Overshoot"]}

[Contacts]
NeutralValue = ${CAL_DEFAULTS["Contacts_NeutralValue"]}
ActivationThreshold = ${CAL_DEFAULTS["Contacts_ActivationThreshold"]}
DeactivationThreshold = ${CAL_DEFAULTS["Contacts_DeactivationThreshold"]}
SizeThresholdMin = ${CAL_DEFAULTS["Contacts_SizeThresholdMin"]}
SizeThresholdMax = ${CAL_DEFAULTS["Contacts_SizeThresholdMax"]}
PositionThresholdMax = ${CAL_DEFAULTS["Contacts_PositionThresholdMax"]}
OrientationThresholdMin = ${CAL_DEFAULTS["Contacts_OrientationThresholdMin"]}
OrientationThresholdMax = ${CAL_DEFAULTS["Contacts_OrientationThresholdMax"]}
SizeMin = ${CAL_DEFAULTS["Contacts_SizeMin"]}
SizeMax = ${CAL_DEFAULTS["Contacts_SizeMax"]}
AspectMin = ${CAL_DEFAULTS["Contacts_AspectMin"]}
AspectMax = ${CAL_DEFAULTS["Contacts_AspectMax"]}

[Stylus]
TipDistance = ${CAL_DEFAULTS["Stylus_TipDistance"]}

[DFT]
PositionMinAmp = ${CAL_DEFAULTS["DFT_PositionMinAmp"]}
PositionMinMag = ${CAL_DEFAULTS["DFT_PositionMinMag"]}
PositionExp = ${CAL_DEFAULTS["DFT_PositionExp"]}
ButtonMinMag = ${CAL_DEFAULTS["DFT_ButtonMinMag"]}
FreqMinMag = ${CAL_DEFAULTS["DFT_FreqMinMag"]}
EOF
        echo ""
        echo -e "${GREEN}[+] Custom calibration saved to $CAL_FILE${NC}"
        echo -e "${YELLOW}Please reboot for changes to take full effect.${NC}"
    else
        echo -e "${YELLOW}Discarded. Defaults kept in memory only.${NC}"
    fi
    pause
}

# ==============================================================================
# Menu 10: Show Current Calibration
# ==============================================================================

menu_show_calibration() {
    echo -e "${BLUE}========== Current Calibration File ==========${NC}"
    if [[ -f "$CAL_FILE" ]]; then
        echo -e "${GREEN}File: $CAL_FILE${NC}"
        echo ""
        cat "$CAL_FILE"
    else
        echo -e "${RED}No calibration file found at $CAL_FILE${NC}"
        echo -e "${YELLOW}Use option 8 or 9 to create one.${NC}"
    fi
    pause
}

# ==============================================================================
# Menu 11: Verify Installation
# ==============================================================================

menu_verify() {
    echo -e "${BLUE}========== Verification ==========${NC}"
    echo ""

    echo -e "${CYAN}Kernel Info:${NC}"
    uname -a
    echo ""

    if check_kernel_surface; then
        echo -e "${GREEN}✓ You are running the Surface kernel!${NC}"
    else
        echo -e "${RED}✗ You are NOT running the Surface kernel.${NC}"
        echo -e "${YELLOW}  → Run option 7 (Set Default Kernel) and reboot.${NC}"
    fi
    echo ""

    echo -e "${CYAN}Installed Surface Packages:${NC}"
    rpm -qa | grep -E "surface|iptsd|libwacom-surface" || echo -e "${RED}None found.${NC}"
    echo ""

    echo -e "${CYAN}Touch Service (iptsd):${NC}"
    systemctl status iptsd --no-pager 2>/dev/null || echo -e "${RED}iptsd service not found.${NC}"
    echo ""

    echo -e "${CYAN}Watchdog Service:${NC}"
    systemctl status linux-surface-default-watchdog.path --no-pager 2>/dev/null || echo -e "${RED}Watchdog not enabled.${NC}"
    echo ""

    echo -e "${CYAN}Calibration:${NC}"
    if [[ -f "$CAL_FILE" ]]; then
        echo -e "${GREEN}Found at $CAL_FILE${NC}"
    else
        echo -e "${RED}Not configured.${NC}"
    fi

    pause
}

# ==============================================================================
# Menu 12: Uninstall linux-surface
# ==============================================================================

menu_uninstall() {
    echo -e "${RED}========== Uninstall linux-surface ==========${NC}"
    echo -e "${YELLOW}This will remove the Surface kernel and related packages.${NC}"
    echo ""

    if ! ask_yes_no "Are you sure you want to uninstall?"; then
        echo -e "${YELLOW}Cancelled.${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Stopping services...${NC}"
    sudo systemctl stop iptsd 2>/dev/null || true
    sudo systemctl disable linux-surface-default-watchdog.path 2>/dev/null || true

    echo -e "${CYAN}Removing packages...${NC}"
    sudo dnf remove -y kernel-surface kernel-surface-devel iptsd libwacom-surface surface-secureboot kernel-surface-default-watchdog 2>/dev/null || true

    echo -e "${CYAN}Removing repository...${NC}"
    sudo rm -f "$REPO_FILE"

    echo -e "${CYAN}Removing calibration...${NC}"
    sudo rm -f "$CAL_FILE"

    echo ""
    echo -e "${GREEN}[+] linux-surface has been removed.${NC}"
    echo -e "${YELLOW}Reboot to return to the default Fedora kernel.${NC}"
    pause
}

# ==============================================================================
# Main Menu
# ==============================================================================

main_menu() {
    while true; do
        print_banner

        echo -e "  ${GREEN}1.${NC} Check System Status"
        echo -e "  ${GREEN}2.${NC} Update Fedora (dnf update/upgrade)"
        echo -e "  ${GREEN}3.${NC} Add linux-surface Repository"
        echo -e "  ${GREEN}4.${NC} Install Surface Kernel & Dependencies"
        echo -e "  ${GREEN}5.${NC} Install Secure Boot Key (MOK)"
        echo -e "  ${GREEN}6.${NC} Reboot & MOK Enrollment Instructions"
        echo -e "  ${GREEN}7.${NC} Set Surface Kernel as Default Boot"
        echo -e "  ${GREEN}8.${NC} Apply Default Calibration ${MAGENTA}(Medium→Big Fingers)${NC}"
        echo -e "  ${GREEN}9.${NC} Apply Custom Calibration ${CYAN}(Interactive)${NC}"
        echo -e " ${GREEN}10.${NC} Show Current Calibration"
        echo -e " ${GREEN}11.${NC} Verify Installation"
        echo -e " ${GREEN}12.${NC} Uninstall linux-surface"
        echo -e " ${RED}13.${NC} Exit"
        echo ""
        read -rp "$(echo -e "${YELLOW}Choose an option [1-13]: ${NC}")" choice

        case "$choice" in
            1) menu_check_status ;;
            2) menu_update_fedora ;;
            3) menu_add_repo ;;
            4) menu_install_kernel ;;
            5) menu_secureboot ;;
            6) menu_reboot_instructions ;;
            7) menu_set_default_kernel ;;
            8) menu_default_calibration ;;
            9) menu_custom_calibration ;;
            10) menu_show_calibration ;;
            11) menu_verify ;;
            12) menu_uninstall ;;
            13)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please choose 1-13.${NC}"
                pause
                ;;
        esac
    done
}

# ==============================================================================
# Entry Point
# ==============================================================================

if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}Do not run this script as root. It will ask for sudo when needed.${NC}"
   exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    echo -e "${RED}Cannot detect OS. Exiting.${NC}"
    exit 1
fi

. /etc/os-release
if [[ "$ID" != "fedora" ]]; then
    echo -e "${YELLOW}Warning: This script is designed for Fedora. Detected: $ID${NC}"
    if ! ask_yes_no "Continue anyway?"; then
        exit 1
    fi
fi

main_menu
