#!/bin/bash

# =============================================================================
# Fedora 44 System Integrity & Maintenance Script
# =============================================================================
# Comprehensive menu-driven system verification and maintenance
# for Fedora 44 Workstation / KDE Plasma / Silverblue
# SSD-optimized: No defragmentation
# =============================================================================

set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Silent mode flag (for non-interactive full runs)
SILENT_MODE=false

# =============================================================================
# Output Helpers
# =============================================================================

log()      { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success()  { echo -e "${GREEN}[✓]${NC} $1"; }
warning()  { echo -e "${YELLOW}[!]${NC} $1"; }
error()    { echo -e "${RED}[✗]${NC} $1"; }
info()     { echo -e "${CYAN}[i]${NC} $1"; }
header()   { echo -e "\n${WHITE}══════════════════════════════════════════════════════════════════${NC}"; echo -e "${WHITE}$1${NC}"; echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"; }

pause() {
    echo ""
    read -rp "$(echo -e "${YELLOW}Press Enter to continue...${NC}")" dummy
}

ask_yes_no() {
    local prompt="$1"
    if [[ "$SILENT_MODE" == true ]]; then
        echo -e "${YELLOW}$prompt [y/N]: ${NC}${GREEN}Y (silent mode)${NC}"
        return 0
    fi
    while true; do
        read -rp "$(echo -e "${YELLOW}$prompt [y/N]: ${NC}")" yn
        case $yn in [Yy]* ) return 0;; [Nn]* | "" ) return 1;; * ) echo "Please answer yes or no.";; esac
    done
}

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║         Fedora 44 System Integrity & Maintenance Manager             ║"
    echo "║     SSD Optimized | Kernel | DNF | Filesystem | Services             ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  OS: ${GREEN}$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)${NC}"
    echo -e "  Kernel: ${GREEN}$(uname -r)${NC}"
    echo -e "  Uptime: ${GREEN}$(uptime -p 2>/dev/null || uptime)${NC}"
    echo ""
}

# =============================================================================
# 1. RPM File Verification
# =============================================================================

menu_rpm_verify() {
    header "1. RPM File Verification & Integrity Check"
    log "Verifying all installed package files against RPM database..."
    echo -e "${YELLOW}(This may take a few minutes...)${NC}\n"

    local tmpfile
    tmpfile=$(mktemp)
    sudo rpm -Va --nofiles --nomtime > "$tmpfile" 2>&1
    local exitcode=$?

    if [[ $exitcode -eq 0 ]] && [[ ! -s "$tmpfile" ]]; then
        success "RPM verification completed — no discrepancies found."
    else
        warning "RPM verification completed with discrepancies."
        echo ""
        echo -e "${CYAN}--- Discrepancies Found ---${NC}"
        cat "$tmpfile" | head -n 50
        local count
        count=$(wc -l < "$tmpfile")
        [[ $count -gt 50 ]] && warning "...and $((count - 50)) more lines (see full output above)"
    fi

    rm -f "$tmpfile"
    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 2. Reinstall Broken Packages
# =============================================================================

menu_reinstall_broken() {
    header "2. Reinstall Packages with Missing/Corrupted Files"

    log "Scanning for packages with missing or corrupted files..."
    local broken_files
    broken_files=$(sudo rpm -Va 2>/dev/null | grep -E '^..5' | awk '{print $NF}')

    if [[ -z "$broken_files" ]]; then
        success "No packages with missing/corrupted files found."
        [[ "$SILENT_MODE" == false ]] && pause
        return
    fi

    local broken_packages
    broken_packages=$(echo "$broken_files" | xargs -I {} rpm -qf {} 2>/dev/null | sort -u)

    warning "Found packages with issues:"
    echo "$broken_packages"
    echo ""

    if ask_yes_no "Reinstall all affected packages?"; then
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] || continue
            log "Reinstalling: $pkg"
            sudo dnf reinstall -y "$pkg" || warning "Failed to reinstall $pkg"
        done <<< "$broken_packages"
        success "Reinstallation process completed."
    else
        info "Skipped reinstallation."
    fi
    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 3. Dependency & Library Check
# =============================================================================

menu_dependencies() {
    header "3. Library & Dependency Checking"

    log "Checking for broken dependencies (dnf repoquery --unsatisfied)..."
    local unsatisfied
    unsatisfied=$(sudo dnf repoquery --unsatisfied 2>/dev/null)
    if [[ -z "$unsatisfied" ]]; then
        success "No broken dependencies found."
    else
        warning "Broken dependencies detected:"
        echo "$unsatisfied"
        if ask_yes_no "Attempt to fix with dnf distro-sync?"; then
            sudo dnf distro-sync -y || warning "distro-sync completed with warnings"
        fi
    fi
    echo ""

    log "Updating dynamic linker cache (ldconfig)..."
    sudo ldconfig
    success "Library cache updated."

    echo ""
    log "Checking for orphaned packages..."
    local orphaned
    orphaned=$(sudo dnf repoquery --unneeded 2>/dev/null)
    if [[ -n "$orphaned" ]]; then
        warning "Orphaned packages found:"
        echo "$orphaned"
        if ask_yes_no "Remove orphaned packages?"; then
            sudo dnf autoremove -y
        fi
    else
        success "No orphaned packages found."
    fi
    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 4. Filesystem Maintenance (SSD Optimized — No Defrag)
# =============================================================================

menu_filesystem() {
    header "4. Filesystem Maintenance (SSD Optimized)"

    local root_fs
    root_fs=$(findmnt -n -o FSTYPE /)
    info "Root filesystem type: $root_fs"

    # Disk usage check
    echo ""
    log "Disk usage:"
    df -h / /home /boot 2>/dev/null | grep -E "(Filesystem|/dev/)"

    echo ""
    log "Inode usage:"
    df -i / /home /boot 2>/dev/null | grep -E "(Filesystem|/dev/)"

    echo ""
    if [[ "$root_fs" == "btrfs" ]]; then
        info "Btrfs detected — running Btrfs maintenance..."

        log "Btrfs filesystem show:"
        sudo btrfs filesystem show 2>/dev/null || true

        log "Starting Btrfs scrub on / ..."
        sudo btrfs scrub start / 2>/dev/null || warning "Scrub already running or failed"
        sleep 1
        sudo btrfs scrub status / 2>/dev/null || true

        if ask_yes_no "Run light Btrfs balance? (can take time)"; then
            sudo btrfs balance start -dusage=50 -musage=50 / || warning "Balance completed with warnings"
        fi

        success "Btrfs maintenance completed."
    else
        info "Non-Btrfs filesystem ($root_fs)."

        if [[ "$root_fs" == ext* ]]; then
            local root_dev
            root_dev=$(findmnt -n -o SOURCE /)
            log "Filesystem check info for $root_dev:"
            sudo tune2fs -l "$root_dev" 2>/dev/null | grep -E "(Check count|Maximum mount count|Last checked|Next check after)" || true

            if ask_yes_no "Schedule fsck on next reboot?"; then
                sudo tune2fs -c 1 "$root_dev" && success "fsck scheduled for next boot."
            fi
        fi
    fi
    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 5. DNF / Package Maintenance
# =============================================================================

menu_dnf_maintenance() {
    header "5. DNF Package Maintenance"

    log "Cleaning package cache and metadata..."
    sudo dnf clean all
    success "Cache cleaned."

    echo ""
    log "Refreshing repository metadata..."
    sudo dnf makecache
    success "Metadata refreshed."

    echo ""
    log "Checking for system updates..."
    sudo dnf check-update || true

    echo ""
    if ask_yes_no "Upgrade all packages now? (dnf upgrade -y)"; then
        sudo dnf upgrade -y
        success "System packages upgraded."
    fi

    echo ""
    log "Rebuilding RPM database..."
    sudo rpm --rebuilddb
    success "RPM database rebuilt."

    echo ""
    log "Verifying RPM database integrity..."
    if sudo rpmdb --verifydb; then
        success "RPM database integrity verified."
    else
        warning "RPM database verification completed with warnings."
    fi

    echo ""
    log "DNF repository list:"
    sudo dnf repolist

    echo ""
    log "DNF package check:"
    sudo dnf check || true

    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 6. Systemd Services Check
# =============================================================================

menu_systemd() {
    header "6. Systemd Services & Failed Units"

    log "Checking for failed systemd units..."
    local failed
    failed=$(systemctl --failed --no-pager --no-legend 2>/dev/null)
    if [[ -n "$failed" ]]; then
        warning "Failed units detected:"
        echo "$failed"
        echo ""
        if ask_yes_no "Attempt to restart failed services?"; then
            systemctl --failed --no-legend | awk '{print $1}' | while read -r unit; do
                log "Restarting $unit ..."
                sudo systemctl restart "$unit" 2>/dev/null || warning "Failed to restart $unit"
            done
        fi
    else
        success "No failed systemd units."
    fi

    echo ""
    log "Systemd journal disk usage:"
    journalctl --disk-usage 2>/dev/null || true

    if ask_yes_no "Vacuum old journal logs (keep 2 weeks)?"; then
        sudo journalctl --vacuum-time=2weeks
        success "Old logs removed."
    fi

    echo ""
    log "Timer status:"
    systemctl list-timers --all --no-pager 2>/dev/null | head -n 20 || true

    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 7. Boot & Kernel Maintenance
# =============================================================================

menu_boot_kernel() {
    header "7. Boot & Kernel Maintenance"

    log "Installed kernels:"
    rpm -qa | grep -E "^kernel" | sort || true

    echo ""
    log "Current running kernel:"
    uname -r

    echo ""
    log "GRUB boot entries:"
    sudo grub2-editenv list 2>/dev/null || true

    echo ""
    log "Boot partition usage:"
    df -h /boot 2>/dev/null || true

    echo ""
    local old_kernels
    old_kernels=$(sudo dnf repoquery --installonly --latest-limit=-2 -q 2>/dev/null)
    if [[ -n "$old_kernels" ]]; then
        warning "Old kernels found (keeping latest 2):"
        echo "$old_kernels"
        if ask_yes_no "Remove old kernels?"; then
            sudo dnf remove --oldinstallonly --setopt installonly_limit=2 -y || warning "Some kernels may be protected"
        fi
    else
        success "No excess old kernels found."
    fi

    echo ""
    if command -v linux-surface-default-watchdog.py &>/dev/null; then
        log "Running linux-surface-default-watchdog.py ..."
        sudo linux-surface-default-watchdog.py
        success "Watchdog executed."
    else
        info "linux-surface-default-watchdog.py not found."
    fi

    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 8. SELinux & Security
# =============================================================================

menu_security() {
    header "8. SELinux & Security Status"

    log "SELinux status:"
    sestatus 2>/dev/null || echo -e "${YELLOW}SELinux tools not installed${NC}"

    echo ""
    log "SELinux denials (since last boot):"
    sudo ausearch -m avc -ts recent 2>/dev/null | tail -n 10 || info "No recent denials or auditd not running."

    echo ""
    log "Firewall status (firewalld):"
    sudo firewall-cmd --state 2>/dev/null || warning "firewalld not running"
    sudo firewall-cmd --get-active-zones 2>/dev/null || true
    sudo firewall-cmd --list-all 2>/dev/null | head -n 20 || true

    echo ""
    log "Failed login attempts:"
    sudo lastb 2>/dev/null | head -n 10 || info "No failed login data available."

    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 9. Hardware & Sensors
# =============================================================================

menu_hardware() {
    header "9. Hardware & Sensor Check"

    log "CPU temperature sensors:"
    sensors 2>/dev/null | head -n 20 || warning "lm_sensors not installed or not configured."

    echo ""
    log "Memory usage:"
    free -h

    echo ""
    log "Top 5 memory-consuming processes:"
    ps aux --sort=-%mem | head -n 6

    echo ""
    log "Top 5 CPU-consuming processes:"
    ps aux --sort=-%cpu | head -n 6

    echo ""
    log "USB devices:"
    lsusb 2>/dev/null | head -n 15 || true

    echo ""
    log "PCI devices (relevant):"
    lspci 2>/dev/null | grep -E "(VGA|Network|Audio|Surface)" | head -n 10 || true

    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 10. Flatpak Maintenance
# =============================================================================

menu_flatpak() {
    header "10. Flatpak Maintenance"

    if ! command -v flatpak &>/dev/null; then
        warning "Flatpak is not installed."
        [[ "$SILENT_MODE" == false ]] && pause
        return
    fi

    log "Installed Flatpaks:"
    flatpak list --app --columns=application,version,size 2>/dev/null || true

    echo ""
    log "Checking for Flatpak updates..."
    flatpak remote-ls --updates 2>/dev/null || info "No updates or no remotes configured."

    echo ""
    if ask_yes_no "Update all Flatpaks?"; then
        flatpak update -y
        success "Flatpaks updated."
    fi

    echo ""
    if ask_yes_no "Remove unused Flatpak runtimes?"; then
        flatpak uninstall --unused -y
        success "Unused runtimes removed."
    fi

    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 11. Surface-Specific Check
# =============================================================================

menu_surface_check() {
    header "11. Surface-Specific Check"

    log "Checking for Surface kernel..."
    if uname -r | grep -qi "surface"; then
        success "Surface kernel is ACTIVE: $(uname -r)"
    else
        warning "Surface kernel NOT detected. Running: $(uname -r)"
    fi

    echo ""
    log "Surface packages installed:"
    rpm -qa | grep -E "surface|iptsd|libwacom-surface" || warning "No surface packages found."

    echo ""
    log "iptsd service status:"
    systemctl status iptsd --no-pager 2>/dev/null || warning "iptsd not running."

    echo ""
    log "Surface watchdog status:"
    systemctl status linux-surface-default-watchdog.path --no-pager 2>/dev/null || warning "Watchdog not enabled."

    echo ""
    if [[ -f /etc/iptsd.d/90-calibration.conf ]]; then
        success "Touch calibration found:"
        cat /etc/iptsd.d/90-calibration.conf
    else
        warning "No touch calibration file at /etc/iptsd.d/90-calibration.conf"
    fi

    [[ "$SILENT_MODE" == false ]] && pause
}

# =============================================================================
# 12. Run ALL with Confirmation
# =============================================================================

menu_run_all() {
    header "RUN ALL MAINTENANCE TASKS"
    warning "This will run all checks sequentially and prompt for confirmation at each step."
    if ! ask_yes_no "Continue with full maintenance run?"; then
        return
    fi

    menu_rpm_verify
    menu_reinstall_broken
    menu_dependencies
    menu_filesystem
    menu_dnf_maintenance
    menu_systemd
    menu_boot_kernel
    menu_security
    menu_hardware
    menu_flatpak
    menu_surface_check

    header "FULL MAINTENANCE COMPLETE"
    success "All maintenance tasks finished!"
    log "Consider rebooting if the kernel or critical packages were updated."
    pause
}

# =============================================================================
# 13. Run ALL without Prompts (Silent)
# =============================================================================

menu_run_all_silent() {
    header "RUN ALL MAINTENANCE TASKS (SILENT / NO PROMPTS)"
    warning "This will run ALL maintenance tasks automatically without asking."
    warning "Auto-answering YES to all optional steps. Defragmentation is skipped (SSD)."
    echo ""

    SILENT_MODE=true

    menu_rpm_verify
    menu_reinstall_broken
    menu_dependencies
    menu_filesystem
    menu_dnf_maintenance
    menu_systemd
    menu_boot_kernel
    menu_security
    menu_hardware
    menu_flatpak
    menu_surface_check

    SILENT_MODE=false

    header "SILENT MAINTENANCE COMPLETE"
    success "All maintenance tasks finished automatically!"
    log "Review the output above for any warnings."
    log "Reboot if the kernel or critical packages were updated."
    pause
}

# =============================================================================
# Main Menu
# =============================================================================

main_menu() {
    while true; do
        print_banner

        echo -e " ${GREEN} 1.${NC} RPM File Verification"
        echo -e " ${GREEN} 2.${NC} Reinstall Broken Packages"
        echo -e " ${GREEN} 3.${NC} Dependency & Library Check"
        echo -e " ${GREEN} 4.${NC} Filesystem Maintenance (SSD)"
        echo -e " ${GREEN} 5.${NC} DNF Package Maintenance (Update + Clean)"
        echo -e " ${GREEN} 6.${NC} Systemd Services & Journal"
        echo -e " ${GREEN} 7.${NC} Boot & Kernel Maintenance"
        echo -e " ${GREEN} 8.${NC} SELinux & Security"
        echo -e " ${GREEN} 9.${NC} Hardware & Sensors"
        echo -e " ${GREEN}10.${NC} Flatpak Maintenance"
        echo -e " ${CYAN}11.${NC} Surface-Specific Check"
        echo -e " ${MAGENTA}12.${NC} ${MAGENTA}→ Run ALL with Prompts${NC}"
        echo -e " ${MAGENTA}13.${NC} ${MAGENTA}→ Run ALL without Prompts (Silent)${NC}"
        echo -e " ${RED}14.${NC} Exit"
        echo ""
        read -rp "$(echo -e "${YELLOW}Choose an option [1-14]: ${NC}")" choice

        case "$choice" in
            1)  menu_rpm_verify ;;
            2)  menu_reinstall_broken ;;
            3)  menu_dependencies ;;
            4)  menu_filesystem ;;
            5)  menu_dnf_maintenance ;;
            6)  menu_systemd ;;
            7)  menu_boot_kernel ;;
            8)  menu_security ;;
            9)  menu_hardware ;;
            10) menu_flatpak ;;
            11) menu_surface_check ;;
            12) menu_run_all ;;
            13) menu_run_all_silent ;;
            14)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please choose 1-14.${NC}"
                pause
                ;;
        esac
    done
}

# =============================================================================
# Entry Point
# =============================================================================

if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}Do not run this script as root. It will ask for sudo when needed.${NC}"
    exit 1
fi

if [[ ! -f /etc/fedora-release ]]; then
    echo -e "${YELLOW}Warning: This script is designed for Fedora.${NC}"
    . /etc/os-release 2>/dev/null
    echo -e "Detected: ${CYAN}${NAME:-Unknown}${NC}"
    if ! ask_yes_no "Continue anyway?"; then
        exit 1
    fi
fi

main_menu

