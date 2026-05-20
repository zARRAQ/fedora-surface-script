#!/bin/bash
# ==============================================================================
# Linux-Surface Universal Installer & Manager
# Auto-detects OS, supports: Fedora, Debian/Ubuntu, Arch, openSUSE, Silverblue
# Based on: https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Global vars
DETECTED_OS=""
DETECTED_ID=""
DETECTED_VERSION=""
DETECTED_LIKE=""
IS_SURFACE_KERNEL=false
CAL_DIR="/etc/iptsd.d"
CAL_FILE="/etc/iptsd.d/90-calibration.conf"

# Supported distros
SUPPORTED_DISTROS=("fedora" "debian" "ubuntu" "arch" "opensuse-tumbleweed" "fedora-silverblue")

# Default calibration values (medium to big fingers)
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
    echo "║           Linux-Surface Universal Installer & Manager              ║"
    echo "║         Patched Kernel | Touch | Stylus | Secure Boot              ║"
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

check_surface_kernel() {
    if uname -r | grep -qi "surface"; then
        IS_SURFACE_KERNEL=true
        return 0
    else
        IS_SURFACE_KERNEL=false
        return 1
    fi
}

check_pkg_installed() {
    case "$DETECTED_ID" in
        fedora|fedora-silverblue)
            rpm -q "$1" &>/dev/null
            ;;
        debian|ubuntu)
            dpkg -l "$1" 2>/dev/null | grep -q "^ii"
            ;;
        arch)
            pacman -Q "$1" &>/dev/null
            ;;
        opensuse-tumbleweed)
            rpm -q "$1" &>/dev/null
            ;;
        *) return 1 ;;
    esac
}

# ==============================================================================
# OS Detection
# ==============================================================================

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}Cannot detect OS. /etc/os-release not found.${NC}"
        exit 1
    fi

    . /etc/os-release
    DETECTED_ID="$ID"
    DETECTED_OS="$NAME"
    DETECTED_VERSION="$VERSION_ID"
    DETECTED_LIKE="$ID_LIKE"

    # Detect Silverblue
    if [[ "$VARIANT_ID" == "silverblue" ]] || [[ "$VARIANT" == *"Silverblue"* ]]; then
        DETECTED_ID="fedora-silverblue"
    fi
}

show_detected_os() {
    echo -e "${BLUE}========== System Detection ==========${NC}"
    echo ""
    echo -e "Detected OS:     ${CYAN}$DETECTED_OS${NC}"
    echo -e "Version:         ${CYAN}$DETECTED_VERSION${NC}"
    echo -e "ID:              ${CYAN}$DETECTED_ID${NC}"
    echo -e "Kernel:          ${CYAN}$(uname -r)${NC}"
    if check_surface_kernel; then
        echo -e "Surface Kernel:  ${GREEN}YES ✓${NC}"
    else
        echo -e "Surface Kernel:  ${RED}NO ✗${NC}"
    fi
    echo ""

    local supported=false
    for d in "${SUPPORTED_DISTROS[@]}"; do
        if [[ "$DETECTED_ID" == "$d" ]]; then
            supported=true
            break
        fi
    done

    if $supported; then
        echo -e "Status: ${GREEN}SUPPORTED by linux-surface project ✓${NC}"
    else
        echo -e "Status: ${RED}NOT directly supported by linux-surface binary repos${NC}"
        echo -e "${YELLOW}You may need to compile from source or use an alternative method.${NC}"
    fi
    echo ""
}

# ==============================================================================
# OS Selection Menu (if detection is wrong)
# ==============================================================================

menu_select_os() {
    echo -e "${BLUE}========== Select Your Distribution ==========${NC}"
    echo ""
    echo -e "${YELLOW}If the detected OS is incorrect, choose the right one below.${NC}"
    echo ""
    echo -e " ${GREEN}1.${NC} Fedora (Workstation, KDE, etc.)"
    echo -e " ${GREEN}2.${NC} Fedora Silverblue"
    echo -e " ${GREEN}3.${NC} Debian / Ubuntu"
    echo -e " ${GREEN}4.${NC} Arch Linux"
    echo -e " ${GREEN}5.${NC} openSUSE Tumbleweed"
    echo -e " ${GREEN}6.${NC} Other / Build from Source"
    echo -e " ${RED}7.${NC} Exit"
    echo ""
    read -rp "$(echo -e "${YELLOW}Select your system [1-7]: ${NC}")" choice

    case "$choice" in
        1) DETECTED_ID="fedora"; DETECTED_OS="Fedora" ;;
        2) DETECTED_ID="fedora-silverblue"; DETECTED_OS="Fedora Silverblue" ;;
        3) DETECTED_ID="debian"; DETECTED_OS="Debian/Ubuntu" ;;
        4) DETECTED_ID="arch"; DETECTED_OS="Arch Linux" ;;
        5) DETECTED_ID="opensuse-tumbleweed"; DETECTED_OS="openSUSE Tumbleweed" ;;
        6)
            echo -e "${YELLOW}For unsupported distros, see:${NC}"
            echo -e "${CYAN}https://github.com/linux-surface/linux-surface/wiki/Compiling-the-Kernel-from-Source${NC}"
            exit 0
            ;;
        7) exit 0 ;;
        *)
            echo -e "${RED}Invalid choice. Defaulting to detected OS.${NC}"
            ;;
    esac
}

# ==============================================================================
# Step-by-Step Installation Menus (Per Distro)
# ==============================================================================

# --- Fedora Steps ---

fedora_step_repo() {
    echo -e "${BLUE}--- Step 1: Add linux-surface Repository ---${NC}"
    local repo_file="/etc/yum.repos.d/linux-surface.repo"

    if [[ -f "$repo_file" ]]; then
        echo -e "${GREEN}Repository already exists.${NC}"
        if ! ask_yes_no "Re-add/refresh repository?"; then
            return
        fi
        sudo rm -f "$repo_file"
    fi

    echo -e "${CYAN}Trying DNF5 config-manager...${NC}"
    if sudo dnf config-manager addrepo --from-repofile="https://pkg.surfacelinux.com/fedora/linux-surface.repo" 2>/dev/null; then
        echo -e "${GREEN}[+] Repository added via DNF5.${NC}"
    else
        echo -e "${YELLOW}[!] DNF5 failed. Trying DNF4...${NC}"
        if sudo dnf config-manager --add-repo="https://pkg.surfacelinux.com/fedora/linux-surface.repo" 2>/dev/null; then
            echo -e "${GREEN}[+] Repository added via DNF4.${NC}"
        else
            echo -e "${YELLOW}[!] Creating repo file manually...${NC}"
            sudo tee "$repo_file" > /dev/null <<'EOF'
[linux-surface]
name=Linux Surface
baseurl=https://pkg.surfacelinux.com/fedora/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://pkg.surfacelinux.com/fedora/linux-surface.pub
EOF
            echo -e "${GREEN}[+] Repository file created.${NC}"
        fi
    fi
}

fedora_step_kernel() {
    echo -e "${BLUE}--- Step 2: Install Surface Kernel & Dependencies ---${NC}"
    if check_pkg_installed "kernel-surface"; then
        echo -e "${GREEN}kernel-surface already installed.${NC}"
        if ! ask_yes_no "Reinstall/update?"; then return; fi
    fi
    sudo dnf install --allowerasing -y kernel-surface iptsd libwacom-surface
    if ask_yes_no "Install kernel-surface-devel (for building kernel modules)?"; then
        sudo dnf install -y kernel-surface-devel
    fi
}

fedora_step_secureboot() {
    echo -e "${BLUE}--- Step 3: Install Secure Boot Key ---${NC}"
    if check_pkg_installed "surface-secureboot"; then
        echo -e "${GREEN}surface-secureboot already installed.${NC}"
        if ! ask_yes_no "Reinstall to re-trigger MOK enrollment?"; then return; fi
        sudo dnf remove -y surface-secureboot
    fi
    sudo dnf install -y surface-secureboot
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  IMPORTANT: After reboot, a BLUE menu (MokManager) will appear.      ║${NC}"
    echo -e "${MAGENTA}║                                                                      ║${NC}"
    echo -e "${MAGENTA}║  1. Select \"Enroll Key\" / \"Enroll MOK\"                               ║${NC}"
    echo -e "${MAGENTA}║  2. Select \"Continue\"                                                ║${NC}"
    echo -e "${MAGENTA}║  3. Enter password:  ${GREEN}surface${MAGENTA}                                          ║${NC}"
    echo -e "${MAGENTA}║  4. Select \"Reboot\"                                                  ║${NC}"
    echo -e "${MAGENTA}║                                                                      ║${NC}"
    echo -e "${MAGENTA}║  NOTE: MokManager uses QWERTY layout!                                ║${NC}"
    echo -e "${MAGENTA}║  If you miss the menu, uninstall then reinstall this package.        ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════╝${NC}"
}

fedora_step_watchdog() {
    echo -e "${BLUE}--- Step 4: Set Surface Kernel as Default ---${NC}"
    if ! check_pkg_installed "kernel-surface-default-watchdog"; then
        echo -e "${YELLOW}Installing watchdog package...${NC}"
        sudo dnf install -y kernel-surface-default-watchdog
    fi
    sudo systemctl enable --now linux-surface-default-watchdog.path
    sudo linux-surface-default-watchdog.py
    echo -e "${GREEN}[+] Surface kernel set as default.${NC}"
}

fedora_step_reboot() {
    echo -e "${BLUE}--- Step 5: Reboot & Verify ---${NC}"
    echo -e "${YELLOW}You should reboot now to boot into the Surface kernel.${NC}"
    if ask_yes_no "Reboot now?"; then
        sudo reboot
    else
        echo -e "${YELLOW}Skipped. Remember to reboot manually!${NC}"
    fi
}

# --- Debian/Ubuntu Steps ---

debian_step_repo() {
    echo -e "${BLUE}--- Step 1: Add GPG Key & Repository ---${NC}"
    if [[ -f /etc/apt/trusted.gpg.d/linux-surface.gpg ]]; then
        echo -e "${GREEN}GPG key already exists.${NC}"
    else
        wget -qO - https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
            | gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/linux-surface.gpg
        echo -e "${GREEN}[+] GPG key added.${NC}"
    fi

    if [[ -f /etc/apt/sources.list.d/linux-surface.list ]]; then
        echo -e "${GREEN}Repository already exists.${NC}"
    else
        echo "deb [arch=amd64] https://pkg.surfacelinux.com/debian release main" \
            | sudo tee /etc/apt/sources.list.d/linux-surface.list
        echo -e "${GREEN}[+] Repository added.${NC}"
    fi
    sudo apt update
}

debian_step_kernel() {
    echo -e "${BLUE}--- Step 2: Install Surface Kernel ---${NC}"
    if check_pkg_installed "linux-image-surface"; then
        echo -e "${GREEN}linux-image-surface already installed.${NC}"
        if ! ask_yes_no "Reinstall/update?"; then return; fi
    fi
    # Ubuntu 26.04 bug: skip libwacom-surface
    if [[ "$DETECTED_OS" == *"Ubuntu"* ]] && [[ "$DETECTED_VERSION" == "26.04" ]]; then
        echo -e "${YELLOW}Ubuntu 26.04 detected: Skipping libwacom-surface due to known bug.${NC}"
        sudo apt install -y linux-image-surface linux-headers-surface iptsd
    else
        sudo apt install -y linux-image-surface linux-headers-surface libwacom-surface iptsd
    fi
}

debian_step_secureboot() {
    echo -e "${BLUE}--- Step 3: Install Secure Boot Key ---${NC}"
    if check_pkg_installed "linux-surface-secureboot-mok"; then
        echo -e "${GREEN}Already installed.${NC}"
        if ! ask_yes_no "Reinstall to re-trigger MOK?"; then return; fi
        sudo apt remove -y linux-surface-secureboot-mok
    fi
    sudo apt install -y linux-surface-secureboot-mok
    echo -e "${MAGENTA}[!] After reboot, enter password: ${GREEN}surface${MAGENTA} in MokManager (QWERTY layout).${NC}"
}

debian_step_grub() {
    echo -e "${BLUE}--- Step 4: Update GRUB ---${NC}"
    sudo update-grub || sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo -e "${GREEN}[+] GRUB updated.${NC}"
}

# --- Arch Steps ---

arch_step_repo() {
    echo -e "${BLUE}--- Step 1: Import & Sign Key ---${NC}"
    curl -s https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
        | sudo pacman-key --add -
    sudo pacman-key --finger 56C464BAAC421453
    sudo pacman-key --lsign-key 56C464BAAC421453
    echo -e "${GREEN}[+] Key imported and locally signed.${NC}"

    if grep -q "\[linux-surface\]" /etc/pacman.conf; then
        echo -e "${GREEN}Repository already in pacman.conf.${NC}"
    else
        echo -e "${CYAN}Adding repository to /etc/pacman.conf...${NC}"
        echo "" | sudo tee -a /etc/pacman.conf
        echo "[linux-surface]" | sudo tee -a /etc/pacman.conf
        echo "Server = https://pkg.surfacelinux.com/arch/" | sudo tee -a /etc/pacman.conf
        echo -e "${GREEN}[+] Repository added.${NC}"
    fi
    sudo pacman -Sy
}

arch_step_kernel() {
    echo -e "${BLUE}--- Step 2: Install Surface Kernel ---${NC}"
    if check_pkg_installed "linux-surface"; then
        echo -e "${GREEN}linux-surface already installed.${NC}"
        if ! ask_yes_no "Reinstall/update?"; then return; fi
    fi
    sudo pacman -S --noconfirm linux-surface linux-surface-headers iptsd

    # Extra firmware for older models
    if ask_yes_no "Install extra firmware for SP4/5/6, Book 1/2, Laptop 1/2?"; then
        sudo pacman -S --noconfirm linux-firmware-marvell linux-firmware-intel
    fi
}

arch_step_secureboot() {
    echo -e "${BLUE}--- Step 3: Install Secure Boot Key ---${NC}"
    echo -e "${YELLOW}WARNING: Arch does not support Secure Boot by default!${NC}"
    echo -e "${YELLOW}Only install this if you have already set up SHIM/Secure Boot.${NC}"
    if ! ask_yes_no "Proceed with linux-surface-secureboot-mok?"; then return; fi
    sudo pacman -S --noconfirm linux-surface-secureboot-mok
    echo -e "${MAGENTA}[!] After reboot, enter password: ${GREEN}surface${MAGENTA} in MokManager.${NC}"
}

arch_step_grub() {
    echo -e "${BLUE}--- Step 4: Update GRUB ---${NC}"
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo -e "${GREEN}[+] GRUB updated.${NC}"
}

# --- openSUSE Steps ---

opensuse_step_repo() {
    echo -e "${BLUE}--- Step 1: Add Repository ---${NC}"
    if zypper lr | grep -q "TaivasJumala"; then
        echo -e "${GREEN}Repository already added.${NC}"
    else
        sudo zypper addrepo https://download.opensuse.org/repositories/home:/TaivasJumala:/Surface/openSUSE_Tumbleweed/home:TaivasJumala:Surface.repo
        sudo zypper refresh
        echo -e "${GREEN}[+] Repository added.${NC}"
    fi
}

opensuse_step_kernel() {
    echo -e "${BLUE}--- Step 2: Install Kernel ---${NC}"
    if check_pkg_installed "kernel-default"; then
        echo -e "${GREEN}kernel-default already installed.${NC}"
        if ! ask_yes_no "Reinstall/update?"; then return; fi
    fi
    sudo zypper install -r 'Linux Surface (openSUSE_Tumbleweed)' kernel-default
    echo -e "${YELLOW}NOTE: iptsd and libwacom-surface may need to be built from source for openSUSE.${NC}"
}

# --- Silverblue Steps ---

silverblue_step_repo() {
    echo -e "${BLUE}--- Step 1: Add Repository ---${NC}"
    if [[ -f /etc/yum.repos.d/linux-surface.repo ]]; then
        echo -e "${GREEN}Repository already exists.${NC}"
    else
        sudo wget -O /etc/yum.repos.d/linux-surface.repo \
            https://pkg.surfacelinux.com/fedora/linux-surface.repo
        echo -e "${GREEN}[+] Repository added.${NC}"
    fi
}

silverblue_step_kernel() {
    echo -e "${BLUE}--- Step 2: Install Dummy Kernel & Surface Packages ---${NC}"
    if [[ ! -f kernel-20201215-1.x86_64.rpm ]]; then
        wget https://github.com/linux-surface/linux-surface/releases/download/silverblue-20201215-1/kernel-20201215-1.x86_64.rpm
    fi
    sudo rpm-ostree override replace ./*.rpm \
        --remove kernel-core \
        --remove kernel-modules \
        --remove kernel-modules-extra \
        --remove libwacom \
        --remove libwacom-data \
        --install kernel-surface \
        --install iptsd \
        --install libwacom-surface \
        --install libwacom-surface-data
    echo -e "${GREEN}[+] Packages layered. Reboot required.${NC}"
}

silverblue_step_secureboot() {
    echo -e "${BLUE}--- Step 3: Install Secure Boot Key ---${NC}"
    sudo rpm-ostree install surface-secureboot
    echo -e "${MAGENTA}[!] After reboot, enroll MOK with password: ${GREEN}surface${MAGENTA}.${NC}"
}

# ==============================================================================
# Unified Step Menu
# ==============================================================================

run_installation_steps() {
    local distro="$1"
    local step=1
    local total=5

    while true; do
        print_banner
        echo -e "${WHITE}Distribution: ${CYAN}$DETECTED_OS${NC}"
        echo -e "${WHITE}Installation Steps${NC}"
        echo ""

        # Show progress
        case "$distro" in
            fedora)
                echo -e " ${GREEN}1.${NC} Add Repository          $(check_step_done "repo" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}2.${NC} Install Kernel & Deps   $(check_step_done "kernel" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}3.${NC} Install Secure Boot Key $(check_step_done "secureboot" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}4.${NC} Set Default Kernel      $(check_step_done "watchdog" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}5.${NC} Reboot & Verify"
                echo -e " ${GREEN}6.${NC} Back to Main Menu"
                ;;
            debian)
                echo -e " ${GREEN}1.${NC} Add GPG Key & Repo      $(check_step_done "repo" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}2.${NC} Install Kernel          $(check_step_done "kernel" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}3.${NC} Install Secure Boot Key $(check_step_done "secureboot" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}4.${NC} Update GRUB             $(check_step_done "grub" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}5.${NC} Reboot & Verify"
                echo -e " ${GREEN}6.${NC} Back to Main Menu"
                ;;
            arch)
                echo -e " ${GREEN}1.${NC} Import & Sign Key     $(check_step_done "repo" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}2.${NC} Install Kernel          $(check_step_done "kernel" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}3.${NC} Install Secure Boot Key $(check_step_done "secureboot" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}4.${NC} Update GRUB             $(check_step_done "grub" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}5.${NC} Reboot & Verify"
                echo -e " ${GREEN}6.${NC} Back to Main Menu"
                ;;
            opensuse-tumbleweed)
                echo -e " ${GREEN}1.${NC} Add Repository          $(check_step_done "repo" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}2.${NC} Install Kernel          $(check_step_done "kernel" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}3.${NC} Reboot & Verify"
                echo -e " ${GREEN}4.${NC} Back to Main Menu"
                ;;
            fedora-silverblue)
                echo -e " ${GREEN}1.${NC} Add Repository          $(check_step_done "repo" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}2.${NC} Install Kernel & Deps   $(check_step_done "kernel" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}3.${NC} Install Secure Boot Key $(check_step_done "secureboot" && echo -e "${GREEN}[Done]${NC}" || echo "")"
                echo -e " ${GREEN}4.${NC} Reboot & Verify"
                echo -e " ${GREEN}5.${NC} Back to Main Menu"
                ;;
        esac

        echo ""
        read -rp "$(echo -e "${YELLOW}Choose step to run [1-6]: ${NC}")" choice

        case "$choice" in
            1)
                case "$distro" in
                    fedora) fedora_step_repo ;;
                    debian) debian_step_repo ;;
                    arch) arch_step_repo ;;
                    opensuse-tumbleweed) opensuse_step_repo ;;
                    fedora-silverblue) silverblue_step_repo ;;
                esac
                ;;
            2)
                case "$distro" in
                    fedora) fedora_step_kernel ;;
                    debian) debian_step_kernel ;;
                    arch) arch_step_kernel ;;
                    opensuse-tumbleweed) opensuse_step_kernel ;;
                    fedora-silverblue) silverblue_step_kernel ;;
                esac
                ;;
            3)
                case "$distro" in
                    fedora) fedora_step_secureboot ;;
                    debian) debian_step_secureboot ;;
                    arch) arch_step_secureboot ;;
                    opensuse-tumbleweed)
                        echo -e "${YELLOW}Secure Boot for openSUSE: Enroll MOK with root password on first reboot.${NC}"
                        ;;
                    fedora-silverblue) silverblue_step_secureboot ;;
                esac
                ;;
            4)
                case "$distro" in
                    fedora) fedora_step_watchdog ;;
                    debian) debian_step_grub ;;
                    arch) arch_step_grub ;;
                    opensuse-tumbleweed|fedora-silverblue)
                        echo -e "${YELLOW}Reboot required. Use step 5 (Reboot).${NC}"
                        ;;
                esac
                ;;
            5)
                case "$distro" in
                    fedora) fedora_step_reboot ;;
                    debian)
                        echo -e "${BLUE}--- Step 5: Reboot & Verify ---${NC}"
                        if ask_yes_no "Reboot now?"; then sudo reboot; fi
                        ;;
                    arch)
                        echo -e "${BLUE}--- Step 5: Reboot & Verify ---${NC}"
                        if ask_yes_no "Reboot now?"; then sudo reboot; fi
                        ;;
                    opensuse-tumbleweed)
                        echo -e "${BLUE}--- Step 3: Reboot & Verify ---${NC}"
                        if ask_yes_no "Reboot now?"; then sudo reboot; fi
                        ;;
                    fedora-silverblue)
                        echo -e "${BLUE}--- Step 4: Reboot & Verify ---${NC}"
                        if ask_yes_no "Reboot now?"; then sudo reboot; fi
                        ;;
                esac
                ;;
            6) return ;;
            *) echo -e "${RED}Invalid option.${NC}"; pause ;;
        esac
        pause
    done
}

check_step_done() {
    case "$1" in
        repo)
            case "$DETECTED_ID" in
                fedora|fedora-silverblue) [[ -f /etc/yum.repos.d/linux-surface.repo ]] && return 0 ;;
                debian) [[ -f /etc/apt/sources.list.d/linux-surface.list ]] && return 0 ;;
                arch) grep -q "\[linux-surface\]" /etc/pacman.conf 2>/dev/null && return 0 ;;
                opensuse-tumbleweed) zypper lr 2>/dev/null | grep -q "TaivasJumala" && return 0 ;;
            esac
            return 1
            ;;
        kernel)
            case "$DETECTED_ID" in
                fedora|fedora-silverblue) check_pkg_installed "kernel-surface" && return 0 ;;
                debian) check_pkg_installed "linux-image-surface" && return 0 ;;
                arch) check_pkg_installed "linux-surface" && return 0 ;;
                opensuse-tumbleweed) check_pkg_installed "kernel-default" && return 0 ;;
            esac
            return 1
            ;;
        secureboot)
            case "$DETECTED_ID" in
                fedora|fedora-silverblue) check_pkg_installed "surface-secureboot" && return 0 ;;
                debian) check_pkg_installed "linux-surface-secureboot-mok" && return 0 ;;
                arch) check_pkg_installed "linux-surface-secureboot-mok" && return 0 ;;
            esac
            return 1
            ;;
        watchdog)
            check_pkg_installed "kernel-surface-default-watchdog" && return 0
            return 1
            ;;
        grub)
            return 1  # Always show as not done (can be re-run)
            ;;
    esac
}

# ==============================================================================
# Calibration Menus
# ==============================================================================

menu_default_calibration() {
    echo -e "${BLUE}========== Apply Default Touch Calibration ==========${NC}"
    echo ""
    echo -e "${MAGENTA}NOTE: These values are tuned for MEDIUM to BIG size fingers.${NC}"
    echo -e "${MAGENTA}If you have small fingers or want different sensitivity, use Custom Calibration.${NC}"
    echo ""

    if ask_yes_no "Apply default calibration for medium/big fingers?"; then
        write_calibration_file
        echo ""
        echo -e "${GREEN}[+] Calibration applied to $CAL_FILE${NC}"
        echo -e "${YELLOW}Please reboot for changes to take full effect.${NC}"
    else
        echo -e "${YELLOW}Skipped.${NC}"
    fi
    pause
}

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
        write_calibration_file
        echo ""
        echo -e "${GREEN}[+] Custom calibration saved to $CAL_FILE${NC}"
        echo -e "${YELLOW}Please reboot for changes to take full effect.${NC}"
    else
        echo -e "${YELLOW}Discarded. Defaults kept in memory only.${NC}"
    fi
    pause
}

write_calibration_file() {
    sudo mkdir -p "$CAL_DIR"
    sudo tee "$CAL_FILE" > /dev/null <<EOF
# Linux-Surface iptsd Calibration
# Generated by linux-surface-manager script
# Date: $(date)

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
}

menu_show_calibration() {
    echo -e "${BLUE}========== Current Calibration File ==========${NC}"
    if [[ -f "$CAL_FILE" ]]; then
        echo -e "${GREEN}File: $CAL_FILE${NC}"
        echo ""
        cat "$CAL_FILE"
    else
        echo -e "${RED}No calibration file found at $CAL_FILE${NC}"
        echo -e "${YELLOW}Use option 6 or 7 to create one.${NC}"
    fi
    pause
}

# ==============================================================================
# System Status & Verification
# ==============================================================================

menu_system_status() {
    echo -e "${BLUE}========== System Status ==========${NC}"
    echo ""
    echo -e "OS:              ${CYAN}$DETECTED_OS $DETECTED_VERSION${NC}"
    echo -e "Kernel:          ${CYAN}$(uname -r)${NC}"
    if check_surface_kernel; then
        echo -e "Surface Kernel:  ${GREEN}YES ✓${NC}"
    else
        echo -e "Surface Kernel:  ${RED}NO ✗${NC}"
    fi
    echo ""

    echo -e "${CYAN}Installed Surface Packages:${NC}"
    case "$DETECTED_ID" in
        fedora|fedora-silverblue)
            rpm -qa | grep -E "surface|iptsd|libwacom-surface" || echo -e "${RED}None found.${NC}"
            ;;
        debian|ubuntu)
            dpkg -l | grep -E "surface|iptsd|libwacom" || echo -e "${RED}None found.${NC}"
            ;;
        arch)
            pacman -Q | grep -E "surface|iptsd|libwacom" || echo -e "${RED}None found.${NC}"
            ;;
        opensuse-tumbleweed)
            rpm -qa | grep -E "surface|kernel-default" || echo -e "${RED}None found.${NC}"
            ;;
    esac
    echo ""

    echo -e "${CYAN}Services:${NC}"
    systemctl status iptsd --no-pager 2>/dev/null || echo -e "${RED}iptsd not active${NC}"
    systemctl status linux-surface-default-watchdog.path --no-pager 2>/dev/null || echo -e "${RED}watchdog not enabled${NC}"
    echo ""

    if [[ -f "$CAL_FILE" ]]; then
        echo -e "Calibration: ${GREEN}Found${NC}"
    else
        echo -e "Calibration: ${RED}Not Found${NC}"
    fi
    pause
}

menu_verify_kernel() {
    echo -e "${BLUE}========== Kernel Verification ==========${NC}"
    echo ""
    echo -e "${CYAN}uname -a:${NC}"
    uname -a
    echo ""
    if check_surface_kernel; then
        echo -e "${GREEN}✓ SUCCESS: You are running the linux-surface kernel!${NC}"
    else
        echo -e "${RED}✗ FAIL: You are NOT running the linux-surface kernel.${NC}"
        echo -e "${YELLOW}  → If you already installed, run Step 4 (Set Default Kernel) and reboot.${NC}"
    fi
    pause
}

# ==============================================================================
# Update System
# ==============================================================================

menu_update_system() {
    echo -e "${BLUE}========== Update System ==========${NC}"
    case "$DETECTED_ID" in
        fedora|fedora-silverblue)
            if ask_yes_no "Run sudo dnf update -y && sudo dnf upgrade -y?"; then
                sudo dnf update -y
                sudo dnf upgrade -y
            fi
            ;;
        debian|ubuntu)
            if ask_yes_no "Run sudo apt update && sudo apt upgrade -y?"; then
                sudo apt update
                sudo apt upgrade -y
            fi
            ;;
        arch)
            if ask_yes_no "Run sudo pacman -Syu?"; then
                sudo pacman -Syu --noconfirm
            fi
            ;;
        opensuse-tumbleweed)
            if ask_yes_no "Run sudo zypper update?"; then
                sudo zypper update -y
            fi
            ;;
    esac
    pause
}

# ==============================================================================
# Uninstall
# ==============================================================================

menu_uninstall() {
    echo -e "${RED}========== Uninstall linux-surface ==========${NC}"
    echo -e "${YELLOW}This will remove the Surface kernel and related packages.${NC}"
    if ! ask_yes_no "Are you sure?"; then
        echo -e "${YELLOW}Cancelled.${NC}"
        pause
        return
    fi

    sudo systemctl stop iptsd 2>/dev/null || true
    sudo systemctl disable linux-surface-default-watchdog.path 2>/dev/null || true

    case "$DETECTED_ID" in
        fedora|fedora-silverblue)
            sudo dnf remove -y kernel-surface kernel-surface-devel iptsd libwacom-surface surface-secureboot kernel-surface-default-watchdog 2>/dev/null || true
            sudo rm -f /etc/yum.repos.d/linux-surface.repo
            ;;
        debian|ubuntu)
            sudo apt remove -y linux-image-surface linux-headers-surface iptsd libwacom-surface linux-surface-secureboot-mok 2>/dev/null || true
            sudo rm -f /etc/apt/sources.list.d/linux-surface.list /etc/apt/trusted.gpg.d/linux-surface.gpg
            ;;
        arch)
            sudo pacman -R --noconfirm linux-surface linux-surface-headers iptsd linux-surface-secureboot-mok 2>/dev/null || true
            ;;
        opensuse-tumbleweed)
            sudo zypper remove -y kernel-default 2>/dev/null || true
            ;;
    esac

    sudo rm -f "$CAL_FILE"
    echo -e "${GREEN}[+] linux-surface removed. Reboot to use stock kernel.${NC}"
    pause
}

# ==============================================================================
# Main Menu
# ==============================================================================

main_menu() {
    while true; do
        print_banner
        echo -e "${WHITE}Current System: ${CYAN}$DETECTED_OS${NC}"
        echo -e "${WHITE}Kernel: ${CYAN}$(uname -r)${NC}"
        if check_surface_kernel; then
            echo -e "${WHITE}Surface Kernel: ${GREEN}Active ✓${NC}"
        else
            echo -e "${WHITE}Surface Kernel: ${RED}Not Active${NC}"
        fi
        echo ""

        echo -e " ${GREEN}1.${NC} Check System Status"
        echo -e " ${GREEN}2.${NC} Update System"
        echo -e " ${GREEN}3.${NC} ${CYAN}→ Install linux-surface (Step-by-Step)${NC}"
        echo -e " ${GREEN}4.${NC} Verify Kernel (uname -a)"
        echo -e " ${GREEN}5.${NC} Apply Default Calibration ${MAGENTA}(Medium→Big Fingers)${NC}"
        echo -e " ${GREEN}6.${NC} Apply Custom Calibration ${CYAN}(Interactive)${NC}"
        echo -e " ${GREEN}7.${NC} Show Current Calibration"
        echo -e " ${GREEN}8.${NC} Change OS Selection"
        echo -e " ${RED}9.${NC} Uninstall linux-surface"
        echo -e " ${RED}10.${NC} Exit"
        echo ""
        read -rp "$(echo -e "${YELLOW}Choose an option [1-10]: ${NC}")" choice

        case "$choice" in
            1) menu_system_status ;;
            2) menu_update_system ;;
            3) run_installation_steps "$DETECTED_ID" ;;
            4) menu_verify_kernel ;;
            5) menu_default_calibration ;;
            6) menu_custom_calibration ;;
            7) menu_show_calibration ;;
            8)
                menu_select_os
                echo -e "${GREEN}Switched to: $DETECTED_OS${NC}"
                pause
                ;;
            9) menu_uninstall ;;
            10)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please choose 1-10.${NC}"
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

detect_os
print_banner
show_detected_os

if ask_yes_no "Is this the correct system?"; then
    echo -e "${GREEN}Proceeding with $DETECTED_OS...${NC}"
else
    menu_select_os
fi

main_menu
