#!/bin/bash

pacman -Sy --noconfirm git
git clone https://github.com/xnnism/arch-install
cd arch-install
./arch-install.sh
