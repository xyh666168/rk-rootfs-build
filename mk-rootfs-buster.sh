#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

if [ "$ARCH" == "armhf" ]; then
	ARCH='armhf'
elif [ "$ARCH" == "arm64" ]; then
	ARCH='arm64'
else
    echo -e "\033[36m please input is: armhf or arm64...... \033[0m"
fi

if [ ! $VERSION ]; then
	VERSION="debug"
fi

if [ ! -e linaro-buster-alip-*.tar.gz ]; then
	echo "\033[36m Run mk-base-debian.sh first \033[0m"
fi

finish() {
	sudo umount $TARGET_ROOTFS_DIR/dev
	exit -1
}
trap finish ERR

echo -e "\033[36m Extract image \033[0m"
sudo tar -xpf linaro-buster-alip-*.tar.gz

echo -e "\033[36m Copy overlay to rootfs \033[0m"
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

# some configs
sudo cp -rf overlay/etc $TARGET_ROOTFS_DIR/
sudo cp -rf overlay/lib $TARGET_ROOTFS_DIR/usr/
sudo cp -rf overlay/usr $TARGET_ROOTFS_DIR/

if [ "$ARCH" == "armhf"  ]; then
    sudo cp overlay-firmware/usr/bin/brcm_patchram_plus1_32 $TARGET_ROOTFS_DIR/usr/bin/brcm_patchram_plus1
    sudo cp overlay-firmware/usr/bin/rk_wifi_init_32 $TARGET_ROOTFS_DIR/usr/bin/rk_wifi_init
elif [ "$ARCH" == "arm64"  ]; then
    sudo cp overlay-firmware/usr/bin/brcm_patchram_plus1_64 $TARGET_ROOTFS_DIR/usr/bin/brcm_patchram_plus1
    sudo cp overlay-firmware/usr/bin/rk_wifi_init_64 $TARGET_ROOTFS_DIR/usr/bin/rk_wifi_init
fi

# bt,wifi,audio firmware
sudo mkdir -p $TARGET_ROOTFS_DIR/system/lib/modules/
sudo find ../kernel/drivers/net/wireless/rockchip_wlan/*  -name "*.ko" | \
    xargs -n1 -i sudo cp {} $TARGET_ROOTFS_DIR/system/lib/modules/

sudo cp -rf overlay-firmware/etc $TARGET_ROOTFS_DIR/
sudo cp -rf overlay-firmware/lib $TARGET_ROOTFS_DIR/usr/
sudo cp -rf overlay-firmware/usr $TARGET_ROOTFS_DIR/

# adb
if [ "$ARCH" == "armhf" ]; then
	sudo cp -rf overlay-debug/usr/local/share/adb/adbd-32 $TARGET_ROOTFS_DIR/usr/local/bin/adbd
elif [ "$ARCH" == "arm64"  ]; then
	sudo cp -rf overlay-debug/usr/local/share/adb/adbd-64 $TARGET_ROOTFS_DIR/usr/local/bin/adbd
fi

# glmark2
sudo rm -rf $TARGET_ROOTFS_DIR/usr/local/share/glmark2
sudo mkdir -p $TARGET_ROOTFS_DIR/usr/local/share/glmark2
if [ "$ARCH" == "armhf" ]; then
	sudo cp -rf overlay-debug/usr/local/share/glmark2/armhf/share/* $TARGET_ROOTFS_DIR/usr/local/share/glmark2
	sudo cp overlay-debug/usr/local/share/glmark2/armhf/bin/glmark2-es2 $TARGET_ROOTFS_DIR/usr/local/bin/glmark2-es2
elif [ "$ARCH" == "arm64"  ]; then
	sudo cp -rf overlay-debug/usr/local/share/glmark2/aarch64/share/* $TARGET_ROOTFS_DIR/usr/local/share/glmark2
	sudo cp overlay-debug/usr/local/share/glmark2/aarch64/bin/glmark2-es2 $TARGET_ROOTFS_DIR/usr/local/bin/glmark2-es2
fi

if [ "$VERSION" == "debug" ] || [ "$VERSION" == "jenkins" ]; then
	# adb, video, camera  test file
	sudo cp -rf overlay-debug/etc $TARGET_ROOTFS_DIR/
	sudo cp -rf overlay-debug/lib $TARGET_ROOTFS_DIR/usr/
	sudo cp -rf overlay-debug/usr $TARGET_ROOTFS_DIR/
fi

if  [ "$VERSION" == "jenkins" ] ; then
	# network
	sudo cp -b /etc/resolv.conf  $TARGET_ROOTFS_DIR/etc/resolv.conf
fi

# rga
sudo mkdir -p $TARGET_ROOTFS_DIR/usr/include/rga
sudo cp packages/$ARCH/rga/include/*      $TARGET_ROOTFS_DIR/usr/include/rga/
sudo cp packages/$ARCH/rga/lib/librga.so  $TARGET_ROOTFS_DIR/usr/lib/

echo -e "\033[36m Change root.....................\033[0m"
if [ "$ARCH" == "armhf" ]; then
	sudo cp /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
elif [ "$ARCH" == "arm64"  ]; then
	sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
fi
sudo mount -o bind /dev $TARGET_ROOTFS_DIR/dev

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
apt-get update
apt-get install -y lxpolkit
apt-get install -y bash
apt-get install -y blueman
echo exit 101 > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
apt-get install -y blueman
rm -f /usr/sbin/policy-rc.d

apt-get install -y systemd-sysv vim

#---------------power management --------------
apt-get install -y busybox pm-utils triggerhappy
cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service

#---------------ForwardPort Linaro overlay --------------
apt-get install -y e2fsprogs
wget http://repo.linaro.org/ubuntu/linaro-overlay/pool/main/l/linaro-overlay/linaro-overlay-minimal_1112.10_all.deb
wget http://repo.linaro.org/ubuntu/linaro-overlay/pool/main/9/96boards-tools/96boards-tools-common_0.9_all.deb
dpkg -i *.deb
rm -rf *.deb
apt-get install -f -y

#---------------Others--------------
#---------Camera---------
apt-get install cheese -y
dpkg -i  /packages/others/camera/*.deb
if [ "$ARCH" == "armhf" ]; then
       cp /packages/others/camera/libv4l-mplane.so /usr/lib/arm-linux-gnueabihf/libv4l/plugins/
elif [ "$ARCH" == "arm64" ]; then
       cp /packages/others/camera/libv4l-mplane.so /usr/lib/aarch64-linux-gnu/libv4l/plugins/
fi

#apt-get remove -y libgl1-mesa-dri:$ARCH xserver-xorg-input-evdev:$ARCH
apt-get remove -y xserver-xorg-input-evdev:$ARCH
apt-get install -y libinput-bin:$ARCH libinput10:$ARCH libwacom2:$ARCH libunwind8:$ARCH xserver-xorg-input-libinput:$ARCH libxml2-dev:$ARCH libglib2.0-dev:$ARCH libpango1.0-dev:$ARCH libimlib2-dev:$ARCH librsvg2-dev:$ARCH libxcursor-dev:$ARCH g++ make libdmx-dev:$ARCH libxcb-xv0-dev:$ARCH libxfont-dev:$ARCH libxkbfile-dev:$ARCH libpciaccess-dev:$ARCH mesa-common-dev:$ARCH libpixman-1-dev:$ARCH x11proto-dev=2018.4-4 libxcb-xf86dri0-dev:$ARCH qtmultimedia5-examples:$ARCH

#Openbox
apt-get install -f -y debhelper gettext libstartup-notification0-dev libxrender-dev pkg-config libglib2.0-dev libxml2-dev perl libxt-dev libxinerama-dev libxrandr-dev libpango1.0-dev libx11-dev: autoconf automake libimlib2-dev libxcursor-dev autopoint librsvg2-dev libxi-dev

#---------FFmpeg---------
apt-get install -f -y ffmpeg
dpkg -i /packages/others/ffmpeg/*

#---------MPV---------
apt-get install -f -y mpv

#---------update chromium-----
apt-get install chromium -f -y
cp -f /packages/others/chromium/etc/chromium.d/default-flags /etc/chromium.d/

#---------------Xserver--------------
echo -e "\033[36m Setup Xserver.................... \033[0m"
dpkg -i  /packages/xserver/*
apt-get install -f -y

#---------------Openbox--------------
echo -e "\033[36m Install openbox.................... \033[0m"
dpkg -i  /packages/openbox/*.deb
apt-get install -f -y

#---------------Video--------------
echo -e "\033[36m Setup Video.................... \033[0m"
apt-get install -y gstreamer1.0-plugins-base gstreamer1.0-tools gstreamer1.0-alsa \
	gstreamer1.0-plugins-good  gstreamer1.0-plugins-bad alsa-utils

dpkg -i  /packages/video/mpp/*.deb
dpkg -i  /packages/video/gstreamer/*.deb
apt-get install -f -y

#---------------TODO: USE DEB-------------- 
#---------------Setup Graphics-------------- 
#apt-get install -y weston
#cd /usr/lib/arm-linux-gnueabihf
#wget https://github.com/rockchip-linux/libmali/blob/29mirror/lib/arm-linux-gnueabihf/libmali-bifrost-g31-rxp0-wayland-gbm.so
#ln -s libmali-bifrost-g31-rxp0-wayland-gbm.so libmali-bifrost-g31-rxp0-wayland-gbm.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libEGL.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libEGL.so.1
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libEGL.so.1.0.0
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libGLESv2.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libGLESv2.so.2
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libGLESv2.so.2.0.0
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libMaliOpenCL.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libOpenCL.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libgbm.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libgbm.so.1
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libgbm.so.1.0.0
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libwayland-egl.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libwayland-egl.so.1
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libwayland-egl.so.1.0.0
cd /


#---------------Custom Script-------------- 
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
rm /lib/systemd/system/wpa_supplicant@.service

#---------------Clean-------------- 
rm -rf /var/lib/apt/lists/*

EOF

sudo umount $TARGET_ROOTFS_DIR/dev
