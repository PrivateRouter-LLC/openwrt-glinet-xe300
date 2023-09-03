#!/bin/bash

OUTPUT="$(pwd)/images"
BUILD_VERSION="22.03.5"
BOARD_NAME="ath79"
BOARD_SUBNAME="nand"
BUILDER="https://downloads.openwrt.org/releases/${BUILD_VERSION}/targets/${BOARD_NAME}/${BOARD_SUBNAME}/openwrt-imagebuilder-${BUILD_VERSION}-${BOARD_NAME}-${BOARD_SUBNAME}.Linux-x86_64.tar.xz"
FILENAME="${BUILDER##*/}"
BASENAME="${FILENAME%.tar.xz}"
BASEDIR=$(realpath "$0" | xargs dirname)

# download image builder
if [ ! -f "${FILENAME}" ] && [ ! -d "${BASENAME}" ]; then
	wget "$BUILDER"
	tar xJvf "${FILENAME}"
    rm "${FILENAME}"
fi

[ -d "${OUTPUT}" ] || mkdir "${OUTPUT}"

cd openwrt-imagebuilder-${BUILD_VERSION}-${BOARD_NAME}-${BOARD_SUBNAME}.Linux-x86_64

make image PROFILE="glinet_gl-xe300" \
        PACKAGES="block-mount kmod-fs-ext4 kmod-usb-storage blkid mount-utils swap-utils e2fsprogs fdisk luci dnsmasq lsblk nano bash" \
        FILES="${BASEDIR}/files/" \
        BIN_DIR="${OUTPUT}"
