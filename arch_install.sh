#!/bin/bash

# WARNING: this script will destroy data on the selected disk.

set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

REPO_URL="https://raw.githubusercontent.com/xNNism/x0C-r3po/master/"
LVM_VOLUME_PHISICAL="lvm"
LVM_VOLUME_GROUP="vg"
LVM_VOLUME_LOGICAL="root"
PARTITION_OPTIONS="defaults,noatime"
PACMAN="pacman -S --needed --noconfirm"
#
#
#
### Get infomation from user

### HOSTNAME
HOSTNAME=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${HOSTNAME:?"hostname cannot be empty"}

### password
ROOT_PASSWORD=$(dialog --stdout --passwordbox "Enter root password" 0 0) || exit 1
clear
: ${ROOT_PASSWORD:?"password cannot be empty"}
ROOT_PASSWORD2=$(dialog --stdout --passwordbox "Enter root password again" 0 0) || exit 1
clear
[[ "$ROOT_PASSWORD" == "$ROOT_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )

### username
USER_NAME=$(dialog --stdout --inputbox "Enter username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

USER_PASSWORD=$(dialog --stdout --passwordbox "Enter user password" 0 0) || exit 1
clear
: ${USER_PASSWORD:?"password cannot be empty"}
USER_PASSWORD2=$(dialog --stdout --passwordbox "Enter user password again" 0 0) || exit 1
clear
[[ "$USER_PASSWORD" == "$USER_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )

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

cat >>/etc/pacman.conf <<EOF
x0C-r3po]
SigLevel = Optional TrustAll
Server = $REPO_URL
EOF

	pacman -Sy --needed --noconfirm reflector
	reflector -c DE -f 15 > /etc/pacman.d/mirrorlist

	pacstrap /mnt base base-devel

	cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
	arch-chroot /mnt systemctl enable fstrim.timer

#
	genfstab -U /mnt >> /mnt/etc/fstab
	sed -i 's/relatime/noatime/' /mnt/etc/fstab
	arch-chroot /mnt ln -s -f /usr/share/zoneinfo/Europe/Berlin /etc/localtime
	arch-chroot /mnt hwclock --systohc
#
	sed -i "s/#en_US.UTF-8/en_US.UTF-8/" /mnt/etc/locale.gen
	arch-chroot /mnt locale-gen
	echo -e "LANG=en_US.UTF-8" > /mnt/etc/vconsole.conf
#
	echo $HOSTNAME > /mnt/etc/hostname
	printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | arch-chroot /mnt passwd

#
# Kernels
#
	arch-chroot /mnt $PACMAN linux-headers linux-hardened linux-hardened-headers

#
# mkinitcpio
#
	arch-chroot /mnt sed -i 's/ block / block keyboard keymap /' /etc/mkinitcpio.conf
	arch-chroot /mnt sed -i 's/ filesystems keyboard / encrypt lvm2 filesystems /' /etc/mkinitcpio.conf
	arch-chroot /mnt mkinitcpio -P
#
# BOOTLOADER
#
	arch-chroot /mnt $PACMAN intel-ucode grub dosfstools efibootmgr os-prober mtools freetype2 fuse2 libisoburn
# CMDLINE_LINUX_ROOT="root=$DEVICE_ROOT"
# BOOTLOADER_ALLOW_DISCARDS=":allow-discards"
	CMDLINE_LINUX="cryptdevice=PARTUUID=$PARTUUID_ROOT:lvm:allow-discards"
# CMDLINE_LINUX="root=/dev/mapper/vg-root rw cryptdevice=PARTUUID=$PARTUUID_ROOT:lvm:allow-discards loglevel=3 quiet apparmor=1 security=apparmor ipv6.disable_ipv6=1"
#
    arch-chroot /mnt sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
    arch-chroot /mnt sed -i 's/#GRUB_SAVEDEFAULT="true"/GRUB_SAVEDEFAULT="true"/' /etc/default/grub
    arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet apparmor=1 security=apparmor ipv6.disable_ipv6=1"/' /etc/default/grub
    arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'$CMDLINE_LINUX'"/' /etc/default/grub
    echo "" >> /mnt/etc/default/grub
    echo "GRUB_DISABLE_SUBMENU=y" >> /mnt/etc/default/grub
	arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory=/boot --recheck
	arch-chroot /mnt os-prober
	arch-chroot /mnt grub-mkconfig -o "/boot/grub/grub.cfg"

#
# CREATE USER
#
	arch-chroot /mnt sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    arch-chroot /mnt useradd -m -G wheel,storage,optical,uucp,lock -s /bin/bash $USER_NAME
    printf "$USER_PASSWORD\n$USER_PASSWORD" | arch-chroot /mnt passwd $USER_NAME

# NetworkManager
	arch-chroot /mnt $PACMAN networkmanager networkmanager-openvpn libnm libnma nm-connection-editor network-manager-applet
	arch-chroot /mnt systemctl enable NetworkManager.service
	
# NETWORK
	arch-chroot /mnt $PACMAN git ufw gufw dialog
	arch-chroot /mnt $PACMAN openvpn-update-systemd-resolved protonvpn-cli-git
	arch-chroot /mnt systemctl enable ufw.service

# SYSTEM
	arch-chroot /mnt $PACMAN usbctl grub-customizer arch-silence-grub-theme trizen libgksu gksu apparmor tilix tilix-themes-git vte-tilix-common vte3-tilix gogh-git
	arch-chroot /mnt $PACMAN repoctl-git gparted htop gnome-disk-utility gnome-initial-setup gnome-logs usbview hardinfo qjournalctl
	groupadd -r audit
	gpasswd -a $USER_NAME audit
	arch-chroot /mnt systemctl enable deny-new-usb.service
	
# GPU Drivers
	arch-chroot /mnt $PACMAN xf86-video-nouveau xf86-video-amdgpu xf86-video-intel xf86-video-ati xf86-video-fbdev xf86-video-openchrome xf86-video-dummy xf86-video-qxl xf86-video-vesa xf86-video-vmware
	arch-chroot /mnt $PACMAN nvidia-390xx-dkms nvidia-390xx-utils libvdpau libxnvctrl nvidia-390xx-settings opencl-nvidia-390xx 
	arch-chroot /mnt nvidia-xconfig
	
# LIGHTDM
	arch-chroot /mnt $PACMAN lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
	arch-chroot /mnt systemctl enable lightdm.service

# DESKTOP
	arch-chroot /mnt $PACMAN mate mate-extra
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Downloads"
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Documents"
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Videos"
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Pictures"
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Public"
    # arch-chroot /mnt chmod -R 755 /home/$USER_NAME/
	# arch-chroot /mnt chown -R xnn:users /home/$USER_NAME/
	arch-chroot /mnt ln -s "/usr/lib/libmarco-private.so" "/usr/lib/libmarco-private.so.1"

# APPEARANCE
	arch-chroot /mnt $PACMAN adwaita-icon-theme deepin-gtk-theme adapta-gtk-theme materia-gtk-theme breeze-icons papirus-icon-theme arc-icon-theme deepin-icon-theme 
	arch-chroot /mnt $PACMAN bedstead-fonts tamzen-font-git terminus-font ttf-zekton-rg 

# PROGRAMMING
	arch-chroot /mnt $PACMAN geany geany-plugins geany-themes-git meld github-desktop-bin

# DEVELOP	
	arch-chroot /mnt $PACMAN cmake extra-cmake-modules gnome-common qt qt5 qtcreator python python-pip python2 python2-pip ghostwriter-git 

# INTERNET
	arch-chroot /mnt $PACMAN firefox firefox-dark-reader firefox-adblock-plus firefox-ublock-origin firefox-extension-video-download-helper firefox-extension-privacybadger
	arch-chroot /mnt $PACMAN chromium filezilla transmission-gtk gpg-crypter keepassxc  
	arch-chroot /mnt $PACMAN python-grpcio-tools opensnitch-git
	
# AUDIO
	arch-chroot /mnt $PACMAN pulseaudio pulseaudio-bluetooth pulseaudio-equalizer-ladspa pavucontrol pulseaudio-alsa libpulse libcanberra-pulse paprefs
	arch-chroot /mnt $PACMAN spotify spotify-adblock-git
	
# VIDEO
	arch-chroot /mnt $PACMAN vlc vlc-arc-dark-git smplayer smplayer-skins smplayer-themes 

# OFFICE
	arch-chroot /mnt $PACMAN libreoffice-fresh 


#
### todo:
# bashrc, icons, themes, makepkg...
#
#
#
##
#	arch-chroot /mnt sed -i 's/"log_group = root"'/"log_group = audit'"  /etc/audit/auditd.conf
#	 arch-chroot /mnt cat >>/home/$USER_NAME/.config/autostart/apparmor-notify.desktop <<EOF
# [Desktop Entry]
# Type=Application
# Name=AppArmor Notify
# Comment=Receive on screen notifications of AppArmor denials
# TryExec=/usr/bin/aa-notify
# Exec=/usr/bin/aa-notify -p -s 1 -w 60 -f /var/log/audit/audit.log
# StartupNotify=false
# NoDisplay=true
# EOF
