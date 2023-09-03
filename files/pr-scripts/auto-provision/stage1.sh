#!/bin/sh

# Source our reusable functions
if [ -f /pr-scripts/functions.sh ]; then
    . /pr-scripts/functions.sh
else
    echo "ERROR: /pr-scripts/functions.sh not found!"
    exit 1
fi

# Get the name of the script without the path
SCRIPT_NAME=$(basename "$0")

# Count the number of running instances of the script (excluding the current one)
NUM_INSTANCES=$(pgrep -f "${SCRIPT_NAME}" | grep -v "$$" | wc -l)

# If more than one instance is found, exit
if [ "$NUM_INSTANCES" -gt 1 ]; then
    log_say "${SCRIPT_NAME} is already running, exiting."
    exit 1
fi

# Set LED to waiting for drive
led_signal_waiting_for_drive

# Print our PR Logo
print_logo

# The physical drive we are going to partition
DESTINATION_DRIVE=/dev/sda

# Wait until we have a drive big enough inserted
until drive_is_big_enough "${DESTINATION_DRIVE}"; do
    log_say "Waiting for a pendrive to be inserted"
    sleep 3
done

led_stop_signaling
led_signal_autoprovision_working

# Check if we have a valid destination drive to protect overwrites, only if we're in the main repo
check_valid_drive "${DESTINATION_DRIVE}"
if [ $? -eq 0 ] && [ "$REPO" = "main" ]; then
        log_say "${DESTINATION_DRIVE} is not a valid destionation drive for partitioning."
        log_say "Please insert a USB/MicroSD drive with a single partition with the label 'SETUP' or no partitions at all (uninitialized)."
        log_say "Sleeping for 30s and then rebooting."
        sleep 30
        reboot
fi

# Tell openwrt not to automount new drives as they are added
uci set fstab.@global[0].auto_mount='0'
uci commit fstab

# Unmount any partitions from our destination drive
unmount_drive "${DESTINATION_DRIVE}"

# Erase any paritions on our destination drive
erase_partitions "${DESTINATION_DRIVE}"

# Create new partitions
echo -e "n\np\n1\n\n+512M\nn\np\n2\n\n\nw" | fdisk "${DESTINATION_DRIVE}"

mkfs.ext4 -F -L root -U "${ROOT_UUID}" "${DESTINATION_DRIVE}"1
mkfs.ext4 -F -L data -U "${DATA_UUID}" "${DESTINATION_DRIVE}"2

# Erase our current /etc/config/fstab and create a new one
cat << EOF > /etc/config/fstab
config global
   option anon_swap '0'
   option anon_mount '0'
   option auto_swap '0'
   option auto_mount '0'
   option delay_root '3'
   option check_fs '0'
EOF

service fstab restart

# Write our new fstab configuration
DEVICE="$(sed -n -e "/\s\/overlay\s.*$/s///p" /etc/mtab)"
uci -q delete fstab.rwm
uci set fstab.rwm="mount"
uci set fstab.rwm.device="${DEVICE}"
uci set fstab.rwm.target="/rwm"
uci set fstab.rwm.enabled="1"
uci commit fstab

# Set the overlay target in fstab configuration
uci -q delete fstab.overlay
uci set fstab.overlay="mount"
uci set fstab.overlay.uuid="${ROOT_UUID}"
uci set fstab.overlay.target="/overlay"
uci set fstab.overlay.fstype="ext4"
uci set fstab.overlay.options="rw,noatime"
uci set fstab.overlay.enabled="1"
uci set fstab.overlay.enabled_fsck="0"
uci commit fstab

uci -q delete fstab.data
uci set fstab.data="mount"
uci set fstab.data.uuid="${DATA_UUID}"
uci set fstab.data.target="/mnt/data"
uci set fstab.data.options="rw,noatime"
uci set fstab.data.fstype="ext4"
uci set fstab.data.enabled="1"
uci set fstab.data.enabled_fsck="0"
uci commit fstab

# Change our system hostname
uci set system.@system[0].hostname='PrivateRouter'
uci commit system

# Set our PrivateRouter IP
uci set network.lan.ipaddr='192.168.8.1'
uci commit network

# Set our PrivateRouter default password
set_root_password "torguard"

# Mount the new root
mount -U "${ROOT_UUID}" /mnt

# Copy our overlay to the new root
tar -C /overlay -cvf - . | tar -C /mnt -xf -

cat << EOF > /mnt/upper/etc/rc.local
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

# Run Stage2 Script
sh /pr-scripts/auto-provision/stage2.sh

exit 0
EOF

# Unmount the new root
umount /mnt

reboot

exit 0
