#!/usr/bin/env bash
set -euo pipefail

# This script is meant to run inside the rootfs during Docker build
# It installs libhybris and create-disp for Droidspaces Linux containers

export DEBIAN_FRONTEND=noninteractive

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
else
    echo "Unsupported package manager. Cannot install libhybris dependencies."
    exit 1
fi

echo "Installing build dependencies..."
if [ "$PKG_MGR" = "apt" ]; then
    apt-get update
    apt-get install -y --no-install-recommends \
        git build-essential pkg-config autoconf automake libtool \
        libwayland-dev libdrm-dev
elif [ "$PKG_MGR" = "dnf" ]; then
    dnf install -y git gcc gcc-c++ make pkgconf autoconf automake libtool \
        wayland-devel libdrm-devel
elif [ "$PKG_MGR" = "pacman" ]; then
    pacman -Sy --noconfirm git base-devel pkgconf wayland libdrm
fi

WORKDIR=$(mktemp -d)
cd "$WORKDIR"

echo "Cloning and building libhybris..."
git clone --depth=1 https://github.com/libhybris/libhybris.git
cd libhybris/hybris
./autogen.sh --prefix=/usr
make -j$(nproc)
make install
cd "$WORKDIR"

echo "Configuring dynamic linker for Android partitions..."
cat > /etc/ld.so.conf.d/00-libhybris.conf <<EOF
/android/system/lib64
/android/vendor/lib64
/android/odm/lib64
/android/system/lib
/android/vendor/lib
/android/odm/lib
EOF
ldconfig || true

echo "Building create-disp daemon..."
# Clone Droidspaces-OSS to build create-disp
git clone --depth=1 https://github.com/alghiffaryfa19/Droidspaces-OSS.git
cd Droidspaces-OSS/create-disp
# Fix CMake configuration to find libhybris
mkdir build && cd build
if command -v cmake >/dev/null 2>&1; then
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc)
    if [ -f create-disp ]; then
        cp create-disp /usr/local/bin/
        chmod +x /usr/local/bin/create-disp
    else
        echo "Warning: create-disp binary not found after build."
    fi
else
    echo "Warning: cmake not found, skipping create-disp compilation."
fi

cd /
rm -rf "$WORKDIR"

echo "Creating systemd service for create-disp..."
cat > /etc/systemd/system/create-disp.service <<EOF
[Unit]
Description=Create DRM Display Node via Libhybris
Before=display-manager.service
ConditionPathExists=/usr/local/bin/create-disp

[Service]
Type=simple
ExecStart=/usr/local/bin/create-disp
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable create-disp.service || true

echo "Libhybris and create-disp installation completed successfully."
