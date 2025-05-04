#!/bin/bash
# Script 1: Partitioning for Arch Linux Dual-Boot

set -euo pipefail # Exit on error, unset variable, or pipe failure

# --- Configuration (Verify!) ---
TARGET_DISK="/dev/nvme0n1"
FREE_SPACE_START_SECTOR=262778880
FREE_SPACE_END_SECTOR=998881279

# Partition sizes (adjust if needed, ensure they fit in free space)
ESP_SIZE_GIB=1
SWAP_SIZE_GIB=16

# Calculate sector counts (assuming 512 byte sectors)
BYTES_PER_GIB=$((1024 * 1024 * 1024))
SECTORS_PER_GIB=$(($BYTES_PER_GIB / 512))

ESP_SIZE_SECTORS=$(($ESP_SIZE_GIB * $SECTORS_PER_GIB))
SWAP_SIZE_SECTORS=$(($SWAP_SIZE_GIB * $SECTORS_PER_GIB))

# Calculate partition end sectors (ensure alignment, parted handles MiB alignment well)
ESP_END_SECTOR=$(($FREE_SPACE_START_SECTOR + $ESP_SIZE_SECTORS))
SWAP_END_SECTOR=$(($ESP_END_SECTOR + $SWAP_SIZE_SECTORS))
ROOT_END_SECTOR=$FREE_SPACE_END_SECTOR # Use remaining space

# Convert sectors to MiB for parted (parted prefers MiB/GiB for alignment)
# sectors * 512 / (1024 * 1024) = sectors / 2048
START_MIB=$(($FREE_SPACE_START_SECTOR / 2048))
ESP_END_MIB=$(($ESP_END_SECTOR / 2048))
SWAP_END_MIB=$(($SWAP_END_SECTOR / 2048))
ROOT_END_MIB=$(($ROOT_END_SECTOR / 2048))

# --- Safety Checks ---
echo "!!! WARNING !!!"
echo "This script will attempt to create partitions on ${TARGET_DISK} between sectors ${FREE_SPACE_START_SECTOR} and ${FREE_SPACE_END_SECTOR}."
echo "It expects this space to be entirely free."
echo "EXISTING DATA OUTSIDE THIS RANGE SHOULD BE UNAFFECTED, BUT BACKUP FIRST!"
echo ""
echo "Target Disk: ${TARGET_DISK}"
echo "Free Space: Sectors ${FREE_SPACE_START_SECTOR} - ${FREE_SPACE_END_SECTOR} (~${START_MIB}MiB - ~${ROOT_END_MIB}MiB)"
echo ""
echo "Proposed new partitions within this space:"
echo " 1. ESP:   ${ESP_SIZE_GIB}GiB (FAT32)  (~${START_MIB}MiB - ~${ESP_END_MIB}MiB)"
echo " 2. SWAP:  ${SWAP_SIZE_GIB}GiB (swap)   (~${ESP_END_MIB}MiB - ~${SWAP_END_MIB}MiB)"
echo " 3. ROOT:  Remaining (Btrfs) (~${SWAP_END_MIB}MiB - ~${ROOT_END_MIB}MiB)"
echo ""
read -p "Do you want to proceed with partitioning ${TARGET_DISK}? (yes/NO): " CONFIRM
if [[ "${CONFIRM,,}" != "yes" ]]; then
    echo "Aborting partitioning."
    exit 1
fi

# --- Partitioning ---
echo "Starting partitioning..."

parted -s "${TARGET_DISK}" -- \
    mkpart ARCH_ESP fat32 ${START_MIB}MiB ${ESP_END_MIB}MiB \
    mkpart ARCH_SWAP linux-swap ${ESP_END_MIB}MiB ${SWAP_END_MIB}MiB \
    mkpart ARCH_ROOT btrfs ${SWAP_END_MIB}MiB ${ROOT_END_MIB}MiB

if [[ $? -ne 0 ]]; then
    echo "ERROR: parted command failed. Please check disk status and free space."
    exit 1
fi

echo "Partitioning commands sent."

# --- Update Kernel Partition Table ---
echo "Waiting a few seconds and attempting to re-read partition table..."
sleep 5
partprobe "${TARGET_DISK}"
sleep 2

echo "Partitioning script finished."
echo "Please run the next script (02_detect_format_mount.sh) to detect, format, and mount the new partitions."
echo "You may want to run 'lsblk ${TARGET_DISK}' or 'parted ${TARGET_DISK} print' now to see the new partitions."

exit 0

