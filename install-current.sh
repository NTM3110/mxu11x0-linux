#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
kernel_version="$(uname -r)"
module_file="$project_dir/build-current/mxu11x0.ko"
build_dir="$project_dir/build-current"

rebuild_module() {
    local kernel_build="/lib/modules/$kernel_version/build"
    if [[ ! -d "$kernel_build" ]]; then
        echo "Missing kernel headers: $kernel_build"
        echo "Install the linux-headers-$kernel_version package, then retry."
        exit 1
    fi

    echo "Rebuilding the Moxa module for $kernel_version..."
    if [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
        runuser -u "$SUDO_USER" -- make -C "$kernel_build" M="$build_dir" clean
        runuser -u "$SUDO_USER" -- make -C "$kernel_build" M="$build_dir" modules
    else
        make -C "$kernel_build" M="$build_dir" clean
        make -C "$kernel_build" M="$build_dir" modules
    fi
}

if [[ $EUID -ne 0 ]]; then
    echo "Run this installer with sudo."
    exit 1
fi
module_kernel="$(modinfo -F vermagic "$module_file" 2>/dev/null || true)"
if [[ ${module_kernel%% *} != "$kernel_version" ]]; then
    rebuild_module
    module_kernel="$(modinfo -F vermagic "$module_file")"
fi
if [[ ${module_kernel%% *} != "$kernel_version" ]]; then
    echo "Built module still does not match the running kernel."
    exit 1
fi

# Stop if an existing serial driver cannot be unloaded safely.
if [[ -d /sys/module/mxu11x0 ]]; then
    modprobe -r mxu11x0
fi
if [[ -d /sys/module/ti_usb_3410_5052 ]]; then
    modprobe -r ti_usb_3410_5052
fi

install -D -m 0644 "$module_file" "/lib/modules/$kernel_version/updates/mxu11x0.ko"
install -d -m 0755 /etc/modprobe.d
printf '# Moxa UPort driver replaces the generic TI driver (vendor requirement).\nblacklist ti_usb_3410_5052\n' > /etc/modprobe.d/moxa-uport.conf
depmod -a "$kernel_version"
modprobe mxu11x0
echo "Moxa driver installed and loaded for $kernel_version."
modinfo -F filename mxu11x0
lsmod | awk 'NR == 1 || /mxu11x0|usbserial/'
echo "Connect the UPort adapter and check for /dev/ttyUSB*."
