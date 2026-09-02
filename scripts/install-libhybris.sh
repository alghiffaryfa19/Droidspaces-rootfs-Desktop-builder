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
        libwayland-dev libdrm-dev cmake clang
elif [ "$PKG_MGR" = "dnf" ]; then
    dnf install -y git gcc gcc-c++ make pkgconf autoconf automake libtool \
        wayland-devel libdrm-devel cmake clang
elif [ "$PKG_MGR" = "pacman" ]; then
    pacman -Sy --noconfirm git base-devel pkgconf wayland libdrm cmake clang
fi

WORKDIR=$(mktemp -d)
cd "$WORKDIR"

echo "Installing android-headers..."
git clone --depth=1 -b halium-11.0 https://github.com/Halium/android-headers.git
cd android-headers
make install PREFIX=/usr
cd "$WORKDIR"

echo "Installing prebuilt libhybris from UBPorts..."
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    DEB_ARCH="arm64"
elif [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "armv8l" ]; then
    DEB_ARCH="armhf"
else
    DEB_ARCH="i386"
fi

HYB_URL="http://repo.ubports.com/pool/main/libh/libhybris/"
HYB_COM=$(curl -s $HYB_URL | grep -o "libhybris_[0-9][^\"]*_${DEB_ARCH}\.deb" | sort -V | tail -n 1)
HYB_DEV=$(curl -s $HYB_URL | grep -o "libhybris-dev_[0-9][^\"]*_${DEB_ARCH}\.deb" | sort -V | tail -n 1)

wget -q ${HYB_URL}${HYB_COM}
wget -q ${HYB_URL}${HYB_DEV}

if command -v dpkg >/dev/null 2>&1; then
    dpkg -x ${HYB_COM} /
    dpkg -x ${HYB_DEV} /
else
    ar x ${HYB_COM} data.tar.xz && tar xf data.tar.xz -C /
    ar x ${HYB_DEV} data.tar.xz && tar xf data.tar.xz -C /
fi

echo "Cloning libhybris source for internal headers (required by create-disp)..."
git clone --depth=1 https://github.com/Linux-on-droid/libhybris.git
mkdir -p /usr/include/hybris
cp -r libhybris/hybris/include/hybris/* /usr/include/hybris/
cd "$WORKDIR"

echo "Configuring dynamic linker for Android partitions..."
mkdir -p /android/system /android/vendor /android/odm
cat > /etc/ld.so.conf.d/00-libhybris.conf <<EOF
/android/system/lib64
/android/vendor/lib64
/android/odm/lib64
/android/system/lib
/android/vendor/lib
/android/odm/lib
EOF
ldconfig || true

echo "Setting up udev rules for Lindroid DRM and Binder..."
mkdir -p /etc/udev/rules.d
echo 'KERNEL=="binder", MODE="0666", GROUP="video"' > /etc/udev/rules.d/99-binder.rules
echo 'SUBSYSTEM=="drm", KERNEL=="card*", GROUP="video", MODE="0660"' > /etc/udev/rules.d/99-lindroid.rules

echo "Setting up graphics environment variables..."
cat > /etc/profile.d/droidspaces-graphics.sh <<EOF
export EGL_PLATFORM=hwcomposer
export HYBRIS_EGLPLATFORM=wayland
EOF
chmod +x /etc/profile.d/droidspaces-graphics.sh

echo "Building create-disp daemon..."
# Clone create-disp repository
git clone --depth=1 https://github.com/Linux-on-droid/create-disp.git
cd create-disp
# Fix CMake configuration to find libhybris and remove hybris-platformcommon
sed -i 's/hybris-platformcommon//g' CMakeLists.txt
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
