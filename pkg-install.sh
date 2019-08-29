#!/bin/bash

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
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Downloads"
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Documents"
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Videos"
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Pictures"
    # arch-chroot /mnt mkdir "/home/$USER_NAME/Public"
    # arch-chroot /mnt chmod -R 755 /home/$USER_NAME/
	# arch-chroot /mnt chown -R xnn:users /home/$USER_NAME/
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
