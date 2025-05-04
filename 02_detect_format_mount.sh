#!/bin/bash
# Script 2: Detect, Format, and Mount New Partitions (v2 - Fixed Detection)

set -euo pipefail

# --- Configuration (Should match Script 1) ---
TARGET_DISK="/dev/nvme0n1"
BTRFS_OPTIONS="noatime,discard=async,space_cache=v2,compress=zstd:5"
SUBVOLUMES=("@" "@home" "@snapshots" "@var_cache" "@var_log" "@tmp")

# --- Helper Functions ---
get_partition_path() {
    local disk=$1
    local part_num=$2
    # Check if part_num is empty or not a number
    if [[ -z "$part_num" || ! "$part_num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Invalid partition number detected: 	$part_num" >&2
        return 1
    fi
    if [[ "$disk" == *nvme* || "$disk" == *mmcblk* ]]; then
        echo "${disk}p${part_num}"
    else
        echo "${disk}${part_num}"
    fi
}

# --- Partition Detection (v2 - Sort Numerically) ---
echo "Attempting to detect the new partitions on ${TARGET_DISK}..."

# Get partition info (Name, Partition Number, Type, Size), filter for partitions, sort numerically by partition number
# Using -p flag to get full paths directly might be simpler, but let's stick to parsing for now
mapfile -t partitions_sorted < <(lsblk -bno NAME,PARTN,TYPE,SIZE "${TARGET_DISK}" | grep "part" | sort -nk2)

# Assume the last 3 partitions (highest numbers) are the new ones (ESP, SWAP, ROOT)
num_partitions=${#partitions_sorted[@]}
if [[ $num_partitions -lt 3 ]]; then
    echo "ERROR: Expected at least 3 partitions, found ${num_partitions}. Cannot reliably detect new partitions."
    lsblk "${TARGET_DISK}"
    exit 1
fi

# Extract info for the presumed new partitions (last 3 lines after numeric sort)
presumed_esp_info=(${partitions_sorted[num_partitions-3]})
presumed_swap_info=(${partitions_sorted[num_partitions-2]})
presumed_root_info=(${partitions_sorted[num_partitions-1]})

# Extract partition numbers directly from the second column (PARTN)
presumed_esp_num=${presumed_esp_info[1]:-ERROR}
presumed_swap_num=${presumed_swap_info[1]:-ERROR}
presumed_root_num=${presumed_root_info[1]:-ERROR}

# Construct full paths using the partition number
DETECTED_ESP_PART=$(get_partition_path "${TARGET_DISK}" "${presumed_esp_num}") || exit 1
DETECTED_SWAP_PART=$(get_partition_path "${TARGET_DISK}" "${presumed_swap_num}") || exit 1
DETECTED_ROOT_PART=$(get_partition_path "${TARGET_DISK}" "${presumed_root_num}") || exit 1

# --- User Confirmation ---
echo ""
echo "Detected the following as the newly created partitions (highest numbers):"
# Adjust size calculation index from [2] to [3] because PARTN was added
echo "  ESP:  ${DETECTED_ESP_PART} (Num: ${presumed_esp_num}, Size: $((${presumed_esp_info[3]:-0} / 1024 / 1024)) MiB)"
echo "  SWAP: ${DETECTED_SWAP_PART} (Num: ${presumed_swap_num}, Size: $((${presumed_swap_info[3]:-0} / 1024 / 1024)) MiB)"
echo "  ROOT: ${DETECTED_ROOT_PART} (Num: ${presumed_root_num}, Size: $((${presumed_root_info[3]:-0} / 1024 / 1024)) MiB)"
echo ""
echo "These partitions will be formatted and mounted."
echo "!!! WARNING: Formatting is DESTRUCTIVE to the target partition !!!"
read -p "Are these the correct partitions to format and use for Arch Linux? (yes/NO): " CONFIRM
if [[ "${CONFIRM,,}" != "yes" ]]; then
    echo "Aborting. Please manually identify the correct partitions and format/mount them."
    exit 1
fi

# --- Set ESP Flag (Just in case Script 1 didn't or user needs to do it) ---
echo "Setting ESP flag on ${DETECTED_ESP_PART}..."
parted -s "${TARGET_DISK}" set "${presumed_esp_num}" esp on
if [[ $? -ne 0 ]]; then
    echo "WARNING: Failed to set ESP flag via parted. This might cause boot issues."
    read -p "Continue anyway? (yes/NO): " CONTINUE_FLAG
    if [[ "${CONTINUE_FLAG,,}" != "yes" ]]; then
        echo "Aborting."
        exit 1
    fi
fi

# --- Formatting ---
echo "Formatting partitions..."
mkfs.fat -F32 "${DETECTED_ESP_PART}"
echo "Formatting SWAP on ${DETECTED_SWAP_PART}..."
mkswap "${DETECTED_SWAP_PART}"
echo "Formatting ROOT (Btrfs) on ${DETECTED_ROOT_PART}..."
mkfs.btrfs -f -L ARCH_ROOT "${DETECTED_ROOT_PART}"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Formatting failed. Please check partition status."
    exit 1
fi

# --- Btrfs Subvolume Creation ---
echo "Creating Btrfs subvolumes..."
TEMP_BTRFS_MOUNT="/mnt/btrfs_temp"
mkdir -p "${TEMP_BTRFS_MOUNT}"
mount -t btrfs -o defaults,compress=zstd:1 "${DETECTED_ROOT_PART}" "${TEMP_BTRFS_MOUNT}"

for vol in "${SUBVOLUMES[@]}"; do
    echo "Creating subvolume: ${vol}"
    btrfs subvolume create "${TEMP_BTRFS_MOUNT}/${vol}"
done

echo "Finished creating subvolumes."
umount "${TEMP_BTRFS_MOUNT}"
rmdir "${TEMP_BTRFS_MOUNT}"

# --- Mounting ---
echo "Mounting filesystems..."

# Mount root subvolume
mount -t btrfs -o subvol=@,${BTRFS_OPTIONS} "${DETECTED_ROOT_PART}" /mnt

# Create mount points for other subvolumes and ESP
mkdir -p /mnt/home
mkdir -p /mnt/.snapshots
mkdir -p /mnt/var/cache
mkdir -p /mnt/var/log
mkdir -p /mnt/tmp
mkdir -p /mnt/boot

# Mount other subvolumes
mount -t btrfs -o subvol=@home,${BTRFS_OPTIONS} "${DETECTED_ROOT_PART}" /mnt/home
mount -t btrfs -o subvol=@snapshots,${BTRFS_OPTIONS} "${DETECTED_ROOT_PART}" /mnt/.snapshots
mount -t btrfs -o subvol=@var_cache,${BTRFS_OPTIONS} "${DETECTED_ROOT_PART}" /mnt/var/cache
mount -t btrfs -o subvol=@var_log,${BTRFS_OPTIONS} "${DETECTED_ROOT_PART}" /mnt/var/log
mount -t btrfs -o subvol=@tmp,${BTRFS_OPTIONS} "${DETECTED_ROOT_PART}" /mnt/tmp

# Mount ESP
mount "${DETECTED_ESP_PART}" /mnt/boot

# Activate Swap
swapon "${DETECTED_SWAP_PART}"

echo "Filesystems formatted and mounted."
lsblk "${TARGET_DISK}"

echo ""
echo "Script 2 finished. Please run the next script (03_base_install.sh) to install the base system."

exit 0

