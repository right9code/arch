#!/bin/bash
# Script 3: Install Base System and Packages

set -euo pipefail

# --- Packages (Based on req.txt / alis-packages.conf) ---
PACKAGES=(
    "base"
    "linux"             # Standard kernel
    "linux-firmware"
    "amd-ucode"         # Microcode for AMD Ryzen 5 6600H
    "base-devel"        # Common development tools
    "git"
    "vim"               # Or nano, etc.
    "btrfs-progs"
    "grub"
    "efibootmgr"
    "os-prober"
    "networkmanager"
    "nvidia"            # Proprietary NVIDIA driver
    "snapper"
    "grub-btrfs"
    "snap-pac"
    "sudo"              # Explicitly add sudo
    "man-db"
    "man-pages"
    "texinfo"
)

# --- Check Mountpoint ---
echo "Verifying that /mnt is mounted..."
if ! mountpoint -q /mnt; then
    echo "ERROR: /mnt does not appear to be a mountpoint."
    echo "Please ensure Script 2 completed successfully and filesystems are mounted."
    exit 1
fi
if ! mountpoint -q /mnt/boot; then
    echo "ERROR: /mnt/boot does not appear to be a mountpoint."
    echo "Please ensure Script 2 completed successfully and the ESP is mounted."
    exit 1
fi

echo "Mountpoints verified."

# --- Pacstrap ---
echo "Starting base system installation (pacstrap)..."
echo "This may take a while depending on your internet connection and mirror speed."

pacstrap -K /mnt "${PACKAGES[@]}"

if [[ $? -ne 0 ]]; then
    echo "ERROR: pacstrap failed. Please check the output for errors."
    exit 1
fi

echo "Base system installation complete."

# --- Generate fstab ---
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Verify fstab contents (optional but recommended)
echo "--- Generated /mnt/etc/fstab --- "
cat /mnt/etc/fstab
echo "--------------------------------"
echo "Please review the generated fstab above for correctness, especially mount options."
read -p "Press Enter to continue..."

echo ""
echo "Script 3 finished. Please run the next script (04_configure_system.sh) to configure the installed system."

exit 0

