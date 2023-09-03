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

# Print our PR Logo
print_logo

# LED Signal waiting for network
led_signal_waiting_for_net

# Wait for Internet connection
wait_for_internet

# Install our base requirements and dns fix
# This also takes care of opkg update
base_requirements_check && log_say "Requirements check successful." || { log_say "Requirements check failed."; exit 1; }

led_stop_signaling
led_signal_autoprovision_working

# List of our packages to install
PACKAGE_LIST="luci-proto-modemmanager modemmanager v2raya wireguard-tools openvpn-openssl git git-http jq curl wget htop resize2fs debootstrap usbmuxd usbutils ttyd fail2ban speedtest-netperf mwan3 luci-ssl luci-app-statistics luci-mod-dashboard luci-app-vnstat luci-app-openvpn luci-app-wireguard adblock kmod-rt2800-usb kmod-lib80211 kmod-rtl8192cu kmod-usb-ohci kmod-usb-uhci luci-compat luci-lib-ipkg kmod-fs-exfat kmod-usb-net-rndis luci-mod-dashboard luci-app-commands luci-app-vnstat luci-app-statistics kmod-usb-net-cdc-eem kmod-usb-net-cdc-ether kmod-usb-net-cdc-subset kmod-usb-net-cdc-ether kmod-usb-net-ipheth libimobiledevice luci-app-nlbwmon comgt kmod-usb-serial-option kmod-usb-serial-wwan usb-modeswitch kmod-usb-serial-wwan kmod-usb-serial-option kmod-usb-net-cdc-mbim qmi-utils luci-proto-qmi umbim kmod-usb-serial-option kmod-usb-serial-wwan kmod-usb-net-rndis kmod-usb-net-cdc-ether rt2800-usb-firmware"

count=$(echo "$PACKAGE_LIST" | wc -w)
log_say "Packages to install: ${count}"

for package in $PACKAGE_LIST; do
    if ! opkg list-installed | grep -q "^$package -"; then
        echo "Installing $package..."
        opkg install $package
        if [ $? -eq 0 ]; then
            echo "$package installed successfully."
        else
            echo "Failed to install $package."
        fi
    else
        echo "$package is already installed."
    fi
done

# Disable mwan3 until the user wants it
if [ -f /etc/config/mwan3 ]; then
    log_say "Disabling mwan3"
    uci set mwan3.wan.enabled='0'
    uci commit mwan3
fi

# Remove package dnsmasq so we can install dnsmasq-full
log_say "Removing original dnsmasq and installing dnsmasq-full"
opkg remove dnsmasq
rm /etc/config/dhcp
opkg install dnsmasq-full

# Install v2raya
log_say "Installing v2raya"
wget -qO /tmp/luci-app-v2ray_2.0.0-1_all.ipk https://github.com/kuoruan/luci-app-v2ray/releases/download/v2.0.0-1/luci-app-v2ray_2.0.0-1_all.ipk
opkg install /tmp/luci-app-v2ray_2.0.0-1_all.ipk

# Configure our PrivateRouter Wireless
uci del wireless.default_radio0
uci del wireless.radio0.disabled
uci commit wireless

uci set wireless.wifinet0=wifi-iface
uci set wireless.wifinet0.device='radio0'
uci set wireless.wifinet0.mode='ap'
uci set wireless.wifinet0.ssid='PrivateRouter'
uci set wireless.wifinet0.encryption='psk2'
uci set wireless.wifinet0.key='privaterouter'
uci set wireless.wifinet0.network='lan'
uci commit wireless

wifi down radio0
wifi up radio0

# Check if we have /etc/config/openvpn and if we do, echo the contents of /pr-scripts/config/openvpn into it
if [ -f /etc/config/openvpn ]; then
    cat </pr-scripts/config/openvpn >/etc/config/openvpn
fi

# Rewrite our rc.local to run our stage3 script
cat << EOF > /etc/rc.local
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

# Run Stage3 Script
sh /pr-scripts/auto-provision/stage3.sh

exit 0
EOF

led_stop_signaling

reboot

exit 0
