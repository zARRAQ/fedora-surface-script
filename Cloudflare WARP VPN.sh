#!/bin/bash
# Cloudflare WARP (1.1.1.1 VPN) Installer & Manager for Fedora 44 KDE Plasma
# Uses official DNF repository: https://pkg.cloudflareclient.com

set -e

REPO_URL="https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo"
PKG_NAME="cloudflare-warp"
SERVICE_NAME="warp-svc"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "=========================================="
    echo "   Cloudflare WARP VPN (1.1.1.1)"
    echo "   Fedora 44 KDE Plasma Manager"
    echo "=========================================="
    echo -e "${NC}"
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

check_installed() {
    if rpm -q "$PKG_NAME" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

install_warp() {
    echo -e "${BLUE}[*] Adding Cloudflare WARP repository...${NC}"

    if sudo dnf config-manager addrepo --from-repofile="$REPO_URL" 2>/dev/null; then
        echo -e "${GREEN}[+] Repository added via config-manager.${NC}"
    else
        echo -e "${YELLOW}[!] config-manager failed, trying manual repo file...${NC}"
        sudo tee /etc/yum.repos.d/cloudflare-warp.repo > /dev/null <<EOF
[cloudflare-warp]
name=Cloudflare WARP
baseurl=https://pkg.cloudflareclient.com/rpm
enabled=1
gpgcheck=1
gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg
EOF
        echo -e "${GREEN}[+] Repository file created manually.${NC}"
    fi

    echo -e "${BLUE}[*] Installing $PKG_NAME...${NC}"
    sudo dnf install -y "$PKG_NAME"

    echo -e "${BLUE}[*] Enabling and starting $SERVICE_NAME service...${NC}"
    sudo systemctl enable --now "$SERVICE_NAME"

    echo -e "${GREEN}[+] Installation complete!${NC}"
}

register_warp() {
    echo -e "${BLUE}[*] Registering WARP client...${NC}"
    warp-cli registration new
    echo -e "${GREEN}[+] Registration complete.${NC}"
}

connect_warp() {
    echo -e "${BLUE}[*] Connecting to WARP...${NC}"
    warp-cli connect
    sleep 2
    echo -e "${GREEN}[+] Status:${NC}"
    warp-cli status
    echo ""
    echo -e "${BLUE}[*] Verifying with Cloudflare...${NC}"
    curl -s https://www.cloudflare.com/cdn-cgi/trace | grep warp || true
}

disconnect_warp() {
    echo -e "${BLUE}[*] Disconnecting WARP...${NC}"
    warp-cli disconnect
    sleep 1
    echo -e "${GREEN}[+] Disconnected.${NC}"
    warp-cli status
}

show_status() {
    echo -e "${BLUE}[*] Current WARP Status:${NC}"
    warp-cli status
    echo ""
    echo -e "${BLUE}[*] Cloudflare Trace (warp=on means active):${NC}"
    curl -s https://www.cloudflare.com/cdn-cgi/trace | grep warp || true
}

uninstall_warp() {
    echo -e "${RED}[!] Uninstalling WARP...${NC}"
    sudo systemctl stop "$SERVICE_NAME" || true
    sudo systemctl disable "$SERVICE_NAME" || true
    sudo dnf remove -y "$PKG_NAME"
    sudo rm -f /etc/yum.repos.d/cloudflare-warp.repo
    echo -e "${GREEN}[+] WARP removed.${NC}"
}

main_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}========== WARP Manager Menu ==========${NC}"
        echo "1) Check WARP installation"
        echo "2) Install / Reinstall WARP"
        echo "3) Register client (first time only)"
        echo "4) Connect (Activate VPN)"
        echo "5) Disconnect (Deactivate VPN)"
        echo "6) Show status"
        echo "7) Uninstall WARP"
        echo "8) Exit"
        echo -e "${BLUE}=======================================${NC}"
        read -rp "Choose an option [1-8]: " choice

        case $choice in
            1)
                if check_installed; then
                    echo -e "${GREEN}[+] $PKG_NAME is installed.${NC}"
                    warp-cli --version 2>/dev/null || true
                else
                    echo -e "${RED}[-] $PKG_NAME is NOT installed.${NC}"
                fi
                ;;
            2)
                if check_installed; then
                    if ask_yes_no "WARP is already installed. Reinstall?"; then
                        uninstall_warp
                        install_warp
                    fi
                else
                    install_warp
                fi
                ;;
            3)
                if ! check_installed; then
                    echo -e "${RED}[-] WARP is not installed yet. Install first (option 2).${NC}"
                else
                    register_warp
                fi
                ;;
            4)
                if ! check_installed; then
                    echo -e "${RED}[-] WARP is not installed. Install first (option 2).${NC}"
                else
                    connect_warp
                fi
                ;;
            5)
                if ! check_installed; then
                    echo -e "${RED}[-] WARP is not installed.${NC}"
                else
                    disconnect_warp
                fi
                ;;
            6)
                if ! check_installed; then
                    echo -e "${RED}[-] WARP is not installed.${NC}"
                else
                    show_status
                fi
                ;;
            7)
                if ! check_installed; then
                    echo -e "${RED}[-] WARP is not installed.${NC}"
                else
                    if ask_yes_no "Are you sure you want to uninstall WARP?"; then
                        uninstall_warp
                    fi
                fi
                ;;
            8)
                echo -e "${GREEN}Bye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please choose 1-8.${NC}"
                ;;
        esac
    done
}

# === MAIN ===
print_banner

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "fedora" ]]; then
        echo -e "${YELLOW}[!] Warning: This script is optimized for Fedora. Detected: $ID${NC}"
        if ! ask_yes_no "Continue anyway?"; then
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}[!] Cannot detect OS. Proceed with caution.${NC}"
fi

if [[ $# -eq 0 ]]; then
    main_menu
else
    case "$1" in
        install) install_warp ;;
        register) register_warp ;;
        connect) connect_warp ;;
        disconnect) disconnect_warp ;;
        status) show_status ;;
        uninstall) uninstall_warp ;;
        *) echo "Usage: $0 {install|register|connect|disconnect|status|uninstall}"; exit 1 ;;
    esac
fi
