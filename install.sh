#!/bin/bash

pacman -Sy --needed --noconfirm git curl
curl https://github.com/xnnism/arch-install/install.sh
./install.sh
