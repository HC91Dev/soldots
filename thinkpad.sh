#!/bin/bash

set -euo pipefail

# ===== ERROR TRAP =====
trap 'print_error "Command failed: $BASH_COMMAND (line $LINENO)"' ERR

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_FILE="$SCRIPT_DIR/install_script.log"
BACKUP_DIR="$HOME/.config/config.bak"

exec > >(tee -a "$LOG_FILE") 2>&1

print_msg() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_error() { echo -e "${RED}[!]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

check_privileges() {
	if [ "$EUID" -ne 0 ]; then
		print_error "Run as sudo actually"
		exit 1
	fi

	if [ -z "${SUDO_USER:-}" ]; then
		print_error "SUDO_USER not set. Run with sudo -E"
		exit 1
	fi

	USER_HOME=$(eval echo ~"$SUDO_USER")
	print_msg "Installing for user: $SUDO_USER"
}

update_system() {
	print_msg "Updating system..."
	pacman -Syu --noconfirm
	print_success "System updated"
}

install_packages() {
	print_msg "Installing packages with detailed error reporting..."

	local packages=(
		base base-devel git

		# Hyprland ecosystem
		hyprland hyprlock hyprshot hyprpicker
		waybar wl-clipboard wtype
		xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils

		# Fonts
		ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols
		ttf-nerd-fonts-symbols-mono noto-fonts noto-fonts-emoji

		# Shell and utilities
		zsh wget curl feh rofi-wayland ffmpeg jq poppler
		fd fzf zoxide imagemagick less man-db man-pages

		# Applications
		firefox kitty

		# System utilities
		npm ntfs-3g p7zip pavucontrol ripgrep rsync tree unzip
		cronie lm_sensors blueman bluez-utils swww openvpn wireplumber

		# ThinkPad AMD essentials (correct list)
		acpi_call tlp smartmontools fwupd
		wpa_supplicant sof-firmware
	)

	for pkg in "${packages[@]}"; do
		print_msg "Installing package: $pkg"
		if ! pacman -S --needed --noconfirm "$pkg"; then
			print_error "FAILED PACKAGE: $pkg"
			exit 1
		fi
		print_success "Installed: $pkg"
	done

	print_success "All system packages installed successfully"
}

detect_aur_helper() {
	if command -v paru &>/dev/null; then echo "paru"
	elif command -v yay &>/dev/null; then echo "yay"
	else echo "paru"
	fi
}

install_aur_helper() {
	local aur_helper
	aur_helper=$(detect_aur_helper)

	print_msg "Checking for AUR helper..."

	if command -v "$aur_helper" &>/dev/null; then
		print_msg "$aur_helper already installed"
		echo "$aur_helper"
		return
	fi

	print_msg "Installing $aur_helper..."

	local temp_dir="/tmp/${aur_helper}_install"
	rm -rf "$temp_dir"

	git clone "https://aur.archlinux.org/${aur_helper}.git" "$temp_dir"
	chown -R "$SUDO_USER:$SUDO_USER" "$temp_dir"

	(cd "$temp_dir" && sudo -u "$SUDO_USER" makepkg -si --noconfirm)

	rm -rf "$temp_dir"
	print_success "$aur_helper installed"
	echo "$aur_helper"
}

install_aur_packages() {
	local aur_helper="$1"

	print_msg "Installing AUR packages with detailed debug..."

	local aur_packages=(
		qdirstat
	)

	for pkg in "${aur_packages[@]}"; do
		print_msg "AUR installing: $pkg"
		if ! sudo -u "$SUDO_USER" "$aur_helper" -S --needed --noconfirm "$pkg"; then
			print_error "FAILED AUR PACKAGE: $pkg"
			exit 1
		fi
		print_success "Installed AUR: $pkg"
	done

	print_success "AUR packages installed"
}

backup_existing_configs() {
	print_msg "Backing up existing configs..."

	mkdir -p "$BACKUP_DIR"
	local config_dirs=("hypr" "waybar" "kitty" "gtk-2.0" "gtk-3.0" "gtk-4.0" "rofi")
	local backed_up=false

	for dir in "${config_dirs[@]}"; do
		local target="$USER_HOME/.config/$dir"
		if [ -e "$target" ]; then
			cp -r "$target" "$BACKUP_DIR/"
			chown -R "$SUDO_USER:$SUDO_USER" "$BACKUP_DIR/$dir"
			print_msg "Backed up: $dir"
			backed_up=true
		fi
	done

	$backed_up && print_success "Backup complete" || print_msg "No configs to back up"
}

create_symlinks() {
	print_msg "Creating symlinks..."

	local config_dir="$USER_HOME/.config"
	mkdir -p "$config_dir"
	chown "$SUDO_USER:$SUDO_USER" "$config_dir"

	local config_dirs=("hypr" "waybar" "kitty" "gtk-2.0" "gtk-3.0" "gtk-4.0" "rofi")

	for dir in "${config_dirs[@]}"; do
		local src="$SCRIPT_DIR/$dir"
		local dest="$config_dir/$dir"

		if [ ! -e "$src" ]; then
			print_warning "$dir missing from script directory, skipping"
			continue
		fi

		rm -rf "$dest"

		sudo -u "$SUDO_USER" ln -sf "$src" "$dest"
		print_success "Linked: $dir"
	done
}

install_fonts() {
	print_msg "Installing fonts..."
	local fonts_dir="$USER_HOME/.local/share/fonts"
	mkdir -p "$fonts_dir"
	chown -R "$SUDO_USER:$SUDO_USER" "$fonts_dir"

	if [ -d "$SCRIPT_DIR/fonts" ]; then
		cp "$SCRIPT_DIR/fonts"/*.{ttf,otf} "$fonts_dir/" 2>/dev/null || true
		chown -R "$SUDO_USER:$SUDO_USER" "$fonts_dir"
		sudo -u "$SUDO_USER" fc-cache -fv >/dev/null
		print_success "Fonts installed"
	else
		print_msg "No fonts directory, skipping"
	fi
}

cleanup() {
	print_msg "Cleaning up..."
	rm -rf /tmp/*_install 2>/dev/null || true
	print_success "Cleanup done"
}

main() {
	print_msg "Starting Hyprland dotfiles install..."
	print_msg "Log: $LOG_FILE"

	check_privileges
	update_system
	install_packages

	local aur_helper
	aur_helper=$(install_aur_helper)

	install_aur_packages "$aur_helper"
	backup_existing_configs
	create_symlinks
	install_fonts
	cleanup

	print_success "🎉 Done!"
	print_msg "Reboot if you want life to improve"
}

main "$@"
