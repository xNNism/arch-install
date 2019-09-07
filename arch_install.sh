#!/bin/bash

################################################################
#															   #
# WARNING: this script will destroy data on the selected disk. #
#															   #
################################################################

######################################################
#########    Colorize and add text parameters       ##
######################################################

blk=$(tput setaf 0) # black
red=$(tput setaf 1) # red
grn=$(tput setaf 2) # green
ylw=$(tput setaf 3) # yellow
blu=$(tput setaf 4) # blue
mga=$(tput setaf 5) # magenta
cya=$(tput setaf 6) # cyan
wht=$(tput setaf 7) # white
#
txtbld=$(tput bold) # Bold
bldblk=${txtbld}$(tput setaf 0) # black
bldred=${txtbld}$(tput setaf 1) # red
bldgrn=${txtbld}$(tput setaf 2) # green
bldylw=${txtbld}$(tput setaf 3) # yellow
bldblu=${txtbld}$(tput setaf 4) # blue
bldmga=${txtbld}$(tput setaf 5) # magenta
bldcya=${txtbld}$(tput setaf 6) # cyan
bldwht=${txtbld}$(tput setaf 7) # white
txtrst=$(tput sgr0) # Reset

##################################
#########    START SCRIPT       ##
##################################

set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

REPO_URL="https://raw.githubusercontent.com/xNNism/x0C-r3po/master/"
LVM_VOLUME_PHISICAL="lvm"
LVM_VOLUME_GROUP="vg"
LVM_VOLUME_LOGICAL="root"
PARTITION_OPTIONS="defaults,noatime"

##########################################
#########    SET USER & PASSWORDS       ##
##########################################
#
### HOSTNAME:
HOSTNAME=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${HOSTNAME:?"hostname cannot be empty"}

### ROOT PASSWORD:
ROOT_PASSWORD=$(dialog --stdout --passwordbox "Enter password for root" 0 0) || exit 1
clear
: ${ROOT_PASSWORD:?"password cannot be empty"}
ROOT_PASSWORD2=$(dialog --stdout --passwordbox "Enter root password again" 0 0) || exit 1
clear
[[ "$ROOT_PASSWORD" == "$ROOT_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )

### USERNAME:
USER_NAME=$(dialog --stdout --inputbox "Enter name of new user" 0 0) || exit 1
clear
: ${$USER_NAME:?"user cannot be empty"}

### USER PASSWORD:
USER_PASSWORD=$(dialog --stdout --passwordbox "Enter password for new user" 0 0) || exit 1
clear
: ${USER_PASSWORD:?"password cannot be empty"}
USER_PASSWORD2=$(dialog --stdout --passwordbox "Enter user password again" 0 0) || exit 1
clear
[[ "$USER_PASSWORD" == "$USER_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )

### INSTALL DEVICE:
DEVICELIST=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
DEVICE=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${DEVICELIST}) || exit 1
clear

### LVM:
PARTITION_ROOT_ENCRYPTION_PASSWORD=$(dialog --stdout --passwordbox "Enter password for LVM" 0 0) || exit 1
clear
: ${PARTITION_ROOT_ENCRYPTION_PASSWORD:?"password cannot be empty"}
PARTITION_ROOT_ENCRYPTION_PASSWORD2=$(dialog --stdout --passwordbox "Enter LVM password again" 0 0) || exit 1
clear
[[ "$PARTITION_ROOT_ENCRYPTION_PASSWORD" == "$PARTITION_ROOT_ENCRYPTION_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )
### END OF USER INPUT

### SET UP LOGS
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

### SET UP NTP
timedatectl set-ntp true

###################################################
#########    UNDO PREVIOUS INSTALL ATTEMPT       ##
###################################################
 
if [ -d /mnt/boot ]; then
umount /mnt/boot
umount /mnt
fi

if [ -e "/dev/mapper/$LVM_VOLUME_PHISICAL" ]; then
lvremove --force "$LVM_VOLUME_GROUP"
pvremove --force --force "/dev/mapper/$LVM_VOLUME_PHISICAL"
cryptsetup close $LVM_VOLUME_PHISICAL
fi

######################################
#########    SETUP PARTITIONS       ##
######################################

if [ -n "$(echo $DEVICE | grep "^sda")" ]; then
		DEVICE_SATA1="${DEVICE}p1"
		DEVICE_SATA2="${DEVICE}p2"
        PARTITION_BOOT="${DEVICE_SATA1}"
        PARTITION_ROOT="${DEVICE_SATA2}"
        
    elif [ -n "$(echo $DEVICE | grep "^nvme")" ]; then
		DEVICE_NVME1="${DEVICE}p1"
		DEVICE_NVME2="${DEVICE}p2"
        PARTITION_BOOT="${DEVICE_NVME1}"
        PARTITION_ROOT="${DEVICE_NVME2}"
        
    elif [ -n "$(echo $DEVICE | grep "^mmc")" ]; then
		DEVICE_MMC1="${DEVICE}p1"
		DEVICE_MMC2="${DEVICE}p2"
        PARTITION_BOOT="${DEVICE_MMC1}"
        PARTITION_ROOT="${DEVICE_MMC2}"
    fi

sgdisk --zap-all $DEVICE
wipefs -a $DEVICE
#PARTITION_BOOT="${DEVICE}1"
#PARTITION_ROOT="${DEVICE}2"
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

#########################################
#########    INSTALL BASE SYSTEM       ##
#########################################

	curl -o /etc/pacman.conf https://raw.githubusercontent.com/xNNism/arch-install/master/config/pacman.conf
		#
	pacman -Syyy --needed --noconfirm reflector
	reflector -c DE -f 15 > /etc/pacman.d/mirrorlist
	#
	pacstrap /mnt base base-devel
	#
	cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
	#
	arch-chroot /mnt systemctl enable fstrim.timer
	#
	genfstab -U /mnt >> /mnt/etc/fstab
	sed -i 's/relatime/noatime/' /mnt/etc/fstab
	arch-chroot /mnt ln -s -f /usr/share/zoneinfo/Europe/Berlin /etc/localtime
	arch-chroot /mnt hwclock --systohc
	#
	sed -i "s/#en_US.UTF-8/en_US.UTF-8/" /mnt/etc/locale.gen
	arch-chroot /mnt locale-gen
	echo -e "KEYMAP=de" > /mnt/etc/vconsole.conf
	# echo -e "LANG=en_US.UTF-8" > /mnt/etc/vconsole.conf
	#
	echo $HOSTNAME > /mnt/etc/hostname
	printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | arch-chroot /mnt passwd

#####################################
#########    INSTALL KERNELS       ##
#####################################

	arch-chroot /mnt pacman -S --needed --noconfirm linux-headers linux-hardened linux-hardened-headers

######################################
#########    SETUP BOOTLOADER       ##
######################################

	arch-chroot /mnt sed -i 's/ block / block keyboard keymap /' /etc/mkinitcpio.conf
	arch-chroot /mnt sed -i 's/ filesystems keyboard / encrypt lvm2 filesystems /' /etc/mkinitcpio.conf
	arch-chroot /mnt mkinitcpio -P
	
################################
#########    SETUP GRUB       ##
################################

	arch-chroot /mnt pacman -S --needed --noconfirm intel-ucode grub dosfstools efibootmgr os-prober mtools freetype2 fuse2 libisoburn
	CMDLINE_LINUX="cryptdevice=PARTUUID=$PARTUUID_ROOT:lvm:allow-discards"
    arch-chroot /mnt sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
    arch-chroot /mnt sed -i 's/#GRUB_SAVEDEFAULT="true"/GRUB_SAVEDEFAULT="true"/' /etc/default/grub
    arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet apparmor=1 security=apparmor ipv6.disable_ipv6=1 intel_iommu=on"/' /etc/default/grub
    arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'$CMDLINE_LINUX'"/' /etc/default/grub
    echo "" >> /mnt/etc/default/grub
    echo "GRUB_DISABLE_SUBMENU=y" >> /mnt/etc/default/grub
	arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory=/boot --recheck
	arch-chroot /mnt os-prober
	arch-chroot /mnt grub-mkconfig -o "/boot/grub/grub.cfg"

#################################
#########    CREATE USER       ##
#################################

	arch-chroot /mnt sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    arch-chroot /mnt useradd -m -G wheel,storage,optical,uucp,lock -s /bin/bash $USER_NAME
    printf "$USER_PASSWORD\n$USER_PASSWORD" | arch-chroot /mnt passwd $USER_NAME

####################################
#########    INSTALL SYSTEM       ##
####################################

	arch-chroot /mnt pacman-key --init
	arch-chroot /mnt pacman-key --populate archlinux
	cp -r /etc/pacman.conf /mnt/etc/pacman.conf
	arch-chroot /mnt pacman -Syyy && arch-chroot /mnt pacman -Syyyuuu
	
# NetworkManager
	arch-chroot /mnt pacman -S --needed --noconfirm networkmanager networkmanager-openvpn libnm libnma nm-connection-editor network-manager-applet
	arch-chroot /mnt systemctl enable NetworkManager.service
	
# NETWORK
	arch-chroot /mnt pacman -S --needed --noconfirm git ufw gufw dialog
	arch-chroot /mnt systemctl enable ufw.service
	arch-chroot /mnt ufw enable

# SYSTEM
	arch-chroot /mnt pacman -S --needed --noconfirm usbctl grub-customizer trizen libgksu gksu apparmor audit lynis auditbeat arch-audit tilix tilix-themes-git vte-tilix-common vte3-tilix gogh-git
	arch-chroot /mnt pacman -S --needed --noconfirm pamac-classic repoctl-git gparted htop gnome-disk-utility gnome-initial-setup gnome-logs usbview hardinfo qjournalctl
	arch-chroot /mnt groupadd -r audit
	arch-chroot /mnt gpasswd -a $USER_NAME audit
	arch-chroot /mnt systemctl enable deny-new-usb.service
	
# GPU Drivers
	arch-chroot /mnt pacman -S --needed --noconfirm xf86-video-nouveau xf86-video-amdgpu xf86-video-intel xf86-video-ati xf86-video-fbdev xf86-video-openchrome xf86-video-dummy xf86-video-qxl xf86-video-vesa xf86-video-vmware
	arch-chroot /mnt pacman -S --needed --noconfirm nvidia-390xx-dkms nvidia-390xx-utils libvdpau libxnvctrl nvidia-390xx-settings opencl-nvidia-390xx 
	arch-chroot /mnt nvidia-xconfig
	
# LIGHTDM
	arch-chroot /mnt pacman -S --needed --noconfirm lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
	arch-chroot /mnt systemctl enable lightdm.service

# DESKTOP
	arch-chroot /mnt pacman -S --needed --noconfirm mate mate-extra
    arch-chroot /mnt mkdir "/home/$USER_NAME/Downloads"
    arch-chroot /mnt mkdir "/home/$USER_NAME/Documents"
    arch-chroot /mnt mkdir "/home/$USER_NAME/Videos"
    arch-chroot /mnt mkdir "/home/$USER_NAME/Pictures"
    arch-chroot /mnt mkdir "/home/$USER_NAME/Public"
    arch-chroot /mnt chmod -R 755 /home/$USER_NAME/
	arch-chroot /mnt chown -R $USER_NAME:users /home/$USER_NAME/
	arch-chroot /mnt ln -s "/usr/lib/libmarco-private.so" "/usr/lib/libmarco-private.so.1"

# APPEARANCE
	arch-chroot /mnt pacman -S --needed --noconfirm adwaita-icon-theme deepin-gtk-theme adapta-gtk-theme materia-gtk-theme breeze-icons papirus-icon-theme arc-icon-theme deepin-icon-theme 
	arch-chroot /mnt pacman -S --needed --noconfirm bedstead-fonts tamzen-font-git terminus-font ttf-zekton-rg

# DEVELOP	
	arch-chroot /mnt pacman -S --needed --noconfirm cmake extra-cmake-modules gnome-common qt qt5 qtcreator python python-pip python2 python2-pip python-setuptools python2-setuptools

# INTERNET
	arch-chroot /mnt pacman -S --needed --noconfirm firefox firefox-dark-reader firefox-adblock-plus firefox-ublock-origin firefox-extension-video-download-helper firefox-extension-privacybadger
	arch-chroot /mnt pacman -S --needed --noconfirm chromium filezilla transmission-gtk gpg-crypter keepassxc  
	
# PROGRAMMING
	arch-chroot /mnt pacman -S --needed --noconfirm geany geany-plugins geany-themes-git meld github-desktop-bin ghostwriter-git
	
# AUDIO
	arch-chroot /mnt pacman -S --needed --noconfirm pulseaudio pulseaudio-bluetooth pulseaudio-equalizer-ladspa pavucontrol pulseaudio-alsa libpulse libcanberra-pulse paprefs
	arch-chroot /mnt pacman -S --needed --noconfirm spotify spotify-adblock-git
	
# VIDEO
	arch-chroot /mnt pacman -S --needed --noconfirm vlc vlc-arc-dark-git smplayer smplayer-skins smplayer-themes 

# SECURITY 
	arch-chroot /mnt pacman -S --needed --noconfirm gnome-nettool kismet wireshark-cli wireshark-qt ettercap-gtk etherape dsniff nmap aircrack-ng-git bettercap-git bettercap-caplets-git bettercap-ui netactview python-grpcio-tools opensnitch-git wifite2-git
	arch-chroot /mnt systemctl enable opensnitchd.service
	arch-chroot /mnt gpasswd -a $USER_NAME wireshark
	arch-chroot /mnt gpasswd -a $USER_NAME kismet
	
# OFFICE
	arch-chroot /mnt pacman -S --needed --noconfirm libreoffice-fresh 
	
# VPN
	arch-chroot /mnt pacman -S --needed --noconfirm openvpn-update-systemd-resolved protonvpn-cli-git 
	
# INSTALL CONFIGS
	arch-chroot /mnt curl -o /etc/makepkg.conf https://raw.githubusercontent.com/xNNism/arch-install/master/config/makepkg.conf
	arch-chroot /mnt curl -o /etc/makepkg.conf https://raw.githubusercontent.com/xNNism/arch-install/master/config/sshd_config
	arch-chroot /mnt curl -o /etc/makepkg.conf https://raw.githubusercontent.com/xNNism/arch-install/master/config/lightdm.conf

###################################
#########     END OF SETUP       ##
###################################
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
