#!/bin/bash
#
# DO NOT USE .... UNDER DEV
#
set -ex

# assume rescue system is based on debian

# Varibles
REL=3.5
MIRROR=http://dl-cdn.alpinelinux.org/alpine
REPO=$MIRROR/v$REL/main
APKV=2.6.8-r1
DEV=/dev/vda

# Main Program
#update the package list and install gdisk
apt-get update && apt-get install -y gdisk

PATH=/bin:/sbin:/usr/bin:/usr/sbin
KEYMAP="us us"
HOST=alpine
USER=anon
ROOT_FS=ext4
BOOT_FS=ext4
FEATURES="ata base ide scsi usb virtio $ROOT_FS"
MODULES="sd-mod,usb-storage,$ROOT_FS"
ROOT_DEV=${DEV}2
BOOT_DEV=${DEV}1
ROOT=/mnt
BOOT=/mnt/boot
ARCH=$(uname -m)

umount -f $DEV

sgdisk -Z $DEV
sgdisk -n 1:0:+512M $DEV
sgdisk -t 1:8300 $DEV
sgdisk -c 1:boot $DEV
sgdisk -N2 $DEV
sgdisk -t 2:8300 $DEV
sgdisk -c 2:root $DEV
sgdisk -A 1:set:2 $DEV

mkfs.$BOOT_FS -m 0 -q -L boot $BOOT_DEV
mkfs.$ROOT_FS -q -L root $ROOT_DEV
mount $ROOT_DEV $ROOT
mkdir $BOOT
mount $BOOT_DEV $BOOT

curl -s $MIRROR/v$REL/main/$ARCH/apk-tools-static-${APKV}.apk | tar xz
./sbin/apk.static --repository $REPO --update-cache --allow-untrusted --root $ROOT --initdb add alpine-base syslinux dhcpcd

cat << EOF > $ROOT/etc/fstab
$ROOT_DEV / $ROOT_FS defaults,noatime 0 0
$BOOT_DEV /boot $BOOT_FS defaults 0 2
EOF
echo $REPO > $ROOT/etc/apk/repositories

cat /etc/resolv.conf > $ROOT/etc/resolv.conf
cat << EOF > $ROOT/etc/update-extlinux.conf
overwrite=1
vesa_menu=0
default_kernel_opts="quiet"
modules=$MODULES
root=$ROOT_DEV
verbose=0
hidden=1
timeout=1
default=grsec
serial_port=
serial_baud=115200
xen_opts=dom0_mem=256M
password=''
EOF

cat << EOF > $ROOT/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
  hostname $HOST
EOF

mount --bind /proc $ROOT/proc
mount --bind /dev $ROOT/dev
mount --bind /sys $ROOT/sys

chroot $ROOT /bin/sh -x << CHROOT
apk update
apk add openssh

setup-hostname -n $HOST

rc-update -q add acpid      default
rc-update -q add cron       default
rc-update -q add devfs      sysinit
rc-update -q add dhcpcd     boot
rc-update -q add dmesg      sysinit
rc-update -q add hwdrivers  sysinit
rc-update -q add mdev       sysinit
rc-update -q add modules    boot
rc-update -q add networking boot
rc-update -q add urandom    boot
rc-update -q add sshd       default

echo features=\""$FEATURES"\" > /etc/mkinitfs/mkinitfs.conf

apk add linux-grsec
extlinux -i /boot
dd bs=440 conv=notrunc count=1 if=/usr/share/syslinux/gptmbr.bin of=$DEV
CHROOT

chroot $ROOT passwd
chroot $ROOT adduser -s /bin/ash -D $USER
chroot $ROOT passwd $USER

umount $ROOT/proc
umount $ROOT/dev
umount $ROOT/sys
umount $BOOT
umount $ROOT
