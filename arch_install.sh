#!/bin/bash

# WARNING: this script will destroy data on the selected disk.

set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

REPO_URL="https://raw.githubusercontent.com/xNNism/x0C-r3po/master/"

LVM_VOLUME_PHISICAL="lvm"
LVM_VOLUME_GROUP="vg"
LVM_VOLUME_LOGICAL="root"
PARTITION_OPTIONS="defaults,noatime"

########################################################################
################## Get infomation from user ###
########################################################################
### hostname
########################################################################
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}
########################################################################
### username
########################################################################
user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}
########################################################################
### password
########################################################################
password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )
########################################################################
### device
########################################################################
DEVICELIST=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
DEVICE=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${DEVICELIST}) || exit 1
clear
########################################################################
### LVM
########################################################################
PARTITION_ROOT_ENCRYPTION_PASSWORD=$(dialog --stdout --passwordbox "Enter LVM password" 0 0) || exit 1
clear
: ${PARTITION_ROOT_ENCRYPTION_PASSWORD:?"password cannot be empty"}
PARTITION_ROOT_ENCRYPTION_PASSWORD2=$(dialog --stdout --passwordbox "Enter LVM password again" 0 0) || exit 1
clear
[[ "$PARTITION_ROOT_ENCRYPTION_PASSWORD" == "$PARTITION_ROOT_ENCRYPTION_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )



### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true
################################################################

    if [ -d /mnt/boot ]; then
        umount /mnt/boot
        umount /mnt
    fi
    if [ -e "/dev/mapper/$LVM_VOLUME_LOGICAL" ]; then
        if [ -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" ]; then
            cryptsetup close $LVM_VOLUME_LOGICAL
        fi
    fi
    if [ -e "/dev/mapper/$LVM_VOLUME_PHISICAL" ]; then
        lvremove --force "$LVM_VOLUME_GROUP-$LVM_VOLUME_LOGICAL"
        vgremove --force "/dev/mapper/$LVM_VOLUME_GROUP"
        pvremove "/dev/mapper/$LVM_VOLUME_PHISICAL"
        if [ -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" ]; then
            cryptsetup close $LVM_VOLUME_PHISICAL
        fi
    fi
    partprobe $DEVICE

sgdisk --zap-all $DEVICE
wipefs -a $DEVICE
PARTITION_BOOT="${DEVICE}1"
PARTITION_ROOT="${DEVICE}2"
DEVICE_ROOT="${DEVICE}2"
#
parted -s $DEVICE mklabel gpt mkpart primary fat32 1MiB 512MiB mkpart primary ext4 512MiB 100% set 1 boot on
sgdisk -t=1:ef00 $DEVICE
sgdisk -t=2:8e00 $DEVICE
#
echo -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" | cryptsetup --key-size=512 --key-file=- luksFormat --type luks2 $PARTITION_ROOT
echo -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" | cryptsetup --key-file=- open $PARTITION_ROOT $LVM_VOLUME_PHISICAL
#
pvcreate /dev/mapper/$LVM_VOLUME_PHISICAL
vgcreate $LVM_VOLUME_GROUP /dev/mapper/$LVM_VOLUME_PHISICAL
lvcreate -l 100%FREE -n $LVM_VOLUME_LOGICAL $LVM_VOLUME_GROUP
#
DEVICE_ROOT="/dev/mapper/$LVM_VOLUME_GROUP-$LVM_VOLUME_LOGICAL"
#
wipefs -a $PARTITION_BOOT
wipefs -a $DEVICE_ROOT
mkfs.fat -n ESP -F32 $PARTITION_BOOT
mkfs.ext4 -L root $DEVICE_ROOT
#
mount -o "$PARTITION_OPTIONS" "$DEVICE_ROOT" /mnt
mkdir /mnt/boot
mount -o "$PARTITION_OPTIONS" "$PARTITION_BOOT" /mnt/boot
#
BOOT_DIRECTORY=/boot
ESP_DIRECTORY=/boot
UUID_BOOT=$(blkid -s UUID -o value $PARTITION_BOOT)
UUID_ROOT=$(blkid -s UUID -o value $PARTITION_ROOT)
PARTUUID_BOOT=$(blkid -s PARTUUID -o value $PARTITION_BOOT)
PARTUUID_ROOT=$(blkid -s PARTUUID -o value $PARTITION_ROOT)

### Setup the disk and partitions ###
# swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
# swap_end=$(( $swap_size + 129 + 1 ))MiB

# parted --script "${device}" -- mklabel gpt \
#   mkpart ESP fat32 1Mib 129MiB \
#   set 1 boot on \
#   mkpart primary linux-swap 129MiB ${swap_end} \
#   mkpart primary ext4 ${swap_end} 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
#part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
#part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
#part_root="$(ls ${device}* | grep -E "^${device}p?3$")"
#
#wipefs "${part_boot}"
#wipefs "${part_swap}"
#wipefs "${part_root}"
#
#mkfs.vfat -F32 "${part_boot}"
#mkswap "${part_swap}"
#mkfs.f2fs -f "${part_root}"
#
#swapon "${part_swap}"
#mount "${part_root}" /mnt
#mkdir /mnt/boot
#mount "${part_boot}" /mnt/boot
#
### Install and configure the basic system ###
cat >>/etc/pacman.conf <<EOF
[x0C-r3po]
SigLevel = Optional TrustAll
Server = $REPO_URL
EOF

pacstrap /mnt x0C
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
echo "${hostname}" > /mnt/etc/hostname

cat >>/mnt/etc/pacman.conf <<EOF
[x0C-r3po]
SigLevel = Optional TrustAll
Server = $REPO_URL
EOF

arch-chroot /mnt bootctl install

cat <<EOF > /mnt/boot/loader/loader.conf
default arch
EOF

cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") rw
EOF

echo "LANG=en_GB.UTF-8" > /mnt/etc/locale.conf

arch-chroot /mnt useradd -mU -s /usr/bin/zsh -G wheel,uucp,video,audio,storage,games,input "$user"
arch-chroot /mnt chsh -s /usr/bin/zsh

echo "$user:$password" | chpasswd --root /mnt
echo "root:$password" | chpasswd --root /mnt
