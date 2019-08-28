#!/bin/bash

# WARNING: this script will destroy data on the selected disk.

set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

REPO_URL="https://raw.githubusercontent.com/xNNism/x0C-r3po/master/"
LVM_VOLUME_PHISICAL="lvm"
LVM_VOLUME_GROUP="vg"
LVM_VOLUME_LOGICAL="root"
PARTITION_OPTIONS="defaults,noatime"

#
#
#
### Get infomation from user

### HOSTNAME
HOSTNAME=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${HOSTNAME:?"hostname cannot be empty"}

### username
user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

### password
ROOT_PASSWORD=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${ROOT_PASSWORD:?"password cannot be empty"}
ROOT_PASSWORD2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$ROOT_PASSWORD" == "$ROOT_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )

### device
DEVICELIST=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
DEVICE=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${DEVICELIST}) || exit 1
clear

### LVM
PARTITION_ROOT_ENCRYPTION_PASSWORD=$(dialog --stdout --passwordbox "Enter LVM password" 0 0) || exit 1
clear
: ${PARTITION_ROOT_ENCRYPTION_PASSWORD:?"password cannot be empty"}
PARTITION_ROOT_ENCRYPTION_PASSWORD2=$(dialog --stdout --passwordbox "Enter LVM password again" 0 0) || exit 1
clear
[[ "$PARTITION_ROOT_ENCRYPTION_PASSWORD" == "$PARTITION_ROOT_ENCRYPTION_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )
### end

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true

########################################################################
### START PARTITIONING  
########################################################################
#
### undo previous install attempt
if [ -d /mnt/boot ]; then
umount /mnt/boot
umount /mnt
fi

if [ -e "/dev/mapper/$LVM_VOLUME_PHISICAL" ]; then
lvremove --force "$LVM_VOLUME_GROUP"
pvremove --force --force "/dev/mapper/$LVM_VOLUME_PHISICAL"
cryptsetup close $LVM_VOLUME_PHISICAL
fi

### START PARTITIONING
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


########################################################################
### Install and configure the basic system 
########################################################################

pacman -Sy reflector
reflector -c DE -f 15 > /etc/pacman.d/mirrorlist
sleep 1
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

cat >>/etc/pacman.conf <<EOF
[x0C-r3po]
SigLevel = Optional TrustAll
Server = $REPO_URL
EOF

pacstrap /mnt base base-devel
arch-chroot /mnt systemctl enable fstrim.timer

pacman_install linux-headers linux-hardened linux-hardened-headers linux-zen linux-zen-headers 

genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/relatime/noatime/' /mnt/etc/fstab
arch-chroot /mnt ln -s -f /usr/share/zoneinfo/Europe/Berlin /etc/localtime
arch-chroot /mnt hwclock --systohc
sed -i "s/#en_US.UTF-8 UTF-8/" /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo -e "LANG=en_US.UTF-8" > /mnt/etc/vconsole.conf
echo $HOSTNAME > /mnt/etc/hostname
printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | arch-chroot /mnt passwd

#cat >>/etc/pacman.conf <<EOF
#[x0C-r3po]
#SigLevel = Optional TrustAll
#Server = $REPO_URL
#EOF
#
#pacman -Sy reflector
#reflector -c DE -f 15 > /etc/pacman.d/mirrorlist
#sleep 1
#cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

#pacstrap /mnt base base-devel
#genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
#echo "${hostname}" > /mnt/etc/hostname

#cat >>/mnt/etc/pacman.conf <<EOF
#[x0C-r3po]
#SigLevel = Optional TrustAll
#Server = $REPO_URL
#EOF
#
#arch-chroot /mnt bootctl install
#
#cat <<EOF > /mnt/boot/loader/loader.conf
#default arch
#EOF
#
#cat <<EOF > /mnt/boot/loader/entries/arch.conf
#title    Arch Linux
#linux    /vmlinuz-linux
#initrd   /initramfs-linux.img
#options  root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") rw
#EOF
#
#echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
#
#arch-chroot /mnt useradd -mU -s /usr/bin/bash -G wheel,uucp,lock,video,audio,storage,games,input "$user"
#arch-chroot /mnt chsh -s /usr/bin/bash
#
#echo "$user:$password" | chpasswd --root /mnt
#echo "root:$password" | chpasswd --root /mnt
