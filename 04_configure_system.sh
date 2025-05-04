#!/bin/bash
# Script 4: Configure Installed System (via Chroot)

set -euo pipefail

# --- Configuration (Verify!) ---
TIMEZONE="Asia/Kolkata" # e.g., "Europe/London", "America/New_York"
LOCALE="en_IN.UTF-8"
LOCALE_GEN="en_IN.UTF-8 UTF-8"
KEYMAP="us" # e.g., "uk", "de"
HOSTNAME="ideapad-arch"
USERNAME="archuser"

# --- Chroot Script Content ---
CHROOT_SCRIPT_CONTENT=$(cat << EOF
#!/bin/bash
set -euo pipefail

echo "--- Starting System Configuration (inside chroot) ---"

# Set Timezone
echo "Setting timezone to ${TIMEZONE}..."
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc
echo "Timezone set."

# Set Locale
echo "Setting locale (${LOCALE})..."
sed -i "s/^#${LOCALE_GEN}/${LOCALE_GEN}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "Locale configured."

# Set Hostname
echo "Setting hostname to ${HOSTNAME}..."
echo "${HOSTNAME}" > /etc/hostname
cat << HOSTS_EOF > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS_EOF
echo "Hostname set."

# Configure mkinitcpio (Usually defaults are fine with btrfs hook from base)
# Add modules if needed, e.g., nvidia, nvidia_modeset, nvidia_uvm, nvidia_drm
# echo "Updating mkinitcpio.conf if needed (e.g., for NVIDIA)..."
# sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
echo "Generating initramfs (mkinitcpio)..."
mkinitcpio -P
echo "Initramfs generated."

# Set Root Password
echo ""
echo "Set the root password:"
passwd root

# Create User
echo ""
echo "Creating user: ${USERNAME}"
useradd -m -G wheel "${USERNAME}"
echo "Set the password for user ${USERNAME}:"
passwd "${USERNAME}"

# Configure Sudo (uncomment wheel group)
echo "Configuring sudo for wheel group..."
EDITOR=tee visudo << SUDO_EOF
%wheel ALL=(ALL:ALL) ALL
SUDO_EOF
# Check if the line was uncommented successfully (simple check)
if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    echo "WARNING: Failed to automatically enable sudo for wheel group."
    echo "You may need to run 'visudo' manually after first boot."
    sleep 3
fi
echo "Sudo configured."

# Install GRUB
echo "Installing GRUB bootloader..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH --recheck
if [[ $? -ne 0 ]]; then echo "ERROR: grub-install failed."; exit 1; fi
echo "GRUB installed."

# Configure GRUB (os-prober, grub-btrfs)
echo "Configuring GRUB..."
sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
# Add BTRFS hook for grub-mkconfig if needed (usually handled by grub-btrfs package)
# systemctl enable grub-btrfsd.service # Enable the daemon for snapshot detection
echo "Enabling grub-btrfs snapshot detection service..."
systemctl enable grub-btrfsd.service
echo "Generating GRUB config file (grub-mkconfig)..."
grub-mkconfig -o /boot/grub/grub.cfg
if [[ $? -ne 0 ]]; then echo "ERROR: grub-mkconfig failed."; exit 1; fi
echo "GRUB configured."

# Configure Snapper
echo "Configuring Snapper..."
# Check if snapper config already exists (e.g., from previous attempt)
umount /.snapshots # Ensure it's not mounted if re-running
rmdir /.snapshots || true # Remove if empty

snapper -c root create-config /
if [[ $? -ne 0 ]]; then echo "ERROR: snapper create-config failed."; exit 1; fi

# Optional: Adjust Snapper config if needed (e.g., limits)
# sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="5"/' /etc/snapper/configs/root
# sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root

# Set permissions for .snapshots directory (important for grub-btrfs)
chmod 750 /.snapshots
# Optional: Allow user/group access if needed
# chown :wheel /.snapshots

echo "Enabling Snapper timers..."
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer
echo "Snapper configured."

# Enable NetworkManager
echo "Enabling NetworkManager..."
systemctl enable NetworkManager.service
echo "NetworkManager enabled."

echo "--- System Configuration Finished (inside chroot) ---"
exit 0

EOF
)

# --- Check Mountpoint ---
echo "Verifying that /mnt is mounted..."
if ! mountpoint -q /mnt; then
    echo "ERROR: /mnt does not appear to be a mountpoint."
    echo "Please ensure previous scripts completed successfully."
    exit 1
fi
echo "Mountpoint verified."

# --- Prepare and Run Chroot Script ---
echo "Preparing chroot environment..."
CHROOT_SCRIPT_PATH="/mnt/configure_chroot.sh"
echo "${CHROOT_SCRIPT_CONTENT}" > "${CHROOT_SCRIPT_PATH}"
chmod +x "${CHROOT_SCRIPT_PATH}"

echo "Entering chroot and running configuration script..."
arch-chroot /mnt /configure_chroot.sh
CHROOT_EXIT_CODE=$?

# --- Cleanup ---
echo "Cleaning up chroot script..."
rm "${CHROOT_SCRIPT_PATH}"

if [[ $CHROOT_EXIT_CODE -ne 0 ]]; then
    echo "ERROR: Configuration script failed inside chroot (Exit code: ${CHROOT_EXIT_CODE})."
    exit 1
fi

echo ""
echo "Script 4 finished successfully!"
echo "The Arch Linux system should now be configured."
echo ""
echo "FINAL STEPS:"
echo " 1. Exit the chroot environment if you are still in it (type 'exit')."
echo " 2. Unmount all partitions: 'umount -R /mnt' (run this multiple times if needed)."
echo " 3. Reboot the system: 'reboot'."
echo " 4. Remove the Arch Linux installation USB."
echo " 5. Select the 'ARCH' entry from your UEFI boot menu."

exit 0

