#!/bin/bash

main() {
	ColorOff=$'\e[0m';
	Green=$'\e[0;32m';
	Yellow=$'\e[0;33m';
	Red=$'\e[0;31m';
	inet_dev=$(echo -e "${Yellow}IP Configuration: \n${Green}$(ip addr | grep -w inet | sed "s/inet/${Red}> ${Green}inet/")")
	trap ctrl_c INT	

	if [ -f /tmp/wget.log ]; then
		rm /tmp/wget.log
	fi

	if (ip addr | grep "wlp") then
		wifi=true
	else
		wifi=false
	fi

	echo -e " $inet_dev \n ${Yellow}Connection check: \n    1.${Red}) ${Green}Connection Test \n    ${Yellow}2.${Red}) ${Green}Connection Speed Test \n    ${Yellow}3.${Red}) ${Green}Connect To Wifi Network"
	echo -n " ${Yellow}Select an option ${Green}[1,2,3]: "
	read input

	case "$input" in
		1)	echo " ${Yellow}Please wait while testing internet connection..."
			if ! (ping google.com -W 4 -c 4 &> /dev/null) then
				echo " ${Red}Fail: ${Yellow}No active internet connection detected"
			else
				echo " ${Green}Pass: ${Yellow}Active internet connection detected"
			fi
		;;
		2)	if [ -t 0 ] && [ -t 1 ]; then
			  old_settings=$(stty -g) || exit
			  stty -icanon -echo min 0 time 3 || exit
			  printf '\033[6n'
			  pos=$(dd count=1 2> /dev/null)
			  pos=${pos%R*}
			  pos=${pos##*\[}
			  x=${pos##*;} y=${pos%%;*}
			  stty "$old_settings"
			fi
	
			(wget --no-check-certificate --append-output=/tmp/wget.log -O /dev/null "http://download.thinkbroadband.com/5MB.zip" ; echo $? > /tmp/ex_status) &
			pid=$!
			tput civis

			until ! (ps | grep "$pid" &> /dev/null)
			  do
				tput cup $y 1 ; echo -e "${Yellow}Please wait while testing download speed..."
				tput cup $((y+1)) 2 ; echo -e "  ${Red}> ${Yellow}Percentage: ${Green}$(tail -n 2 /tmp/wget.log | grep -o "...%\|..%\|.%")"
				tput cup $((y+2)) 2 ; echo -e "  ${Red}> ${Yellow}Speed: ${Green}$(tail -n 4 /tmp/wget.log | awk 'NR==1 {print $8"/s"}')"
				sleep 1
			done
		
			tput cnorm

			if [ "$(</tmp/ex_status)" -gt "0" ]; then
				echo " ${Red}Error: ${Yellow}No active internet connection found"
			else
				sed -i 's/\,/\./' /tmp/wget.log &> /dev/null
				### Define network connection speed variables from data in wget.log
				connection_speed=$(tail /tmp/wget.log | grep -oP '(?<=\().*(?=\))' | awk '{print $1}')
				connection_rate=$(tail /tmp/wget.log | grep -oP '(?<=\().*(?=\))' | awk '{print $2}')
				echo -e " ${Yellow} Download Connection Speed: ${Green}$connection_speed $connection_rate"
			fi
			rm /tmp/wget.log &> /dev/null
			rm /tmp/ex_status &> /dev/null
		;;
		3)	if "$wifi" ; then
				wifi-menu
			else
				echo " ${Red}Error: ${Yellow}No wifi interface detected"
			fi
		;;
	esac
}

ctrl_c() {
	tput cnorm

	if [ -f /tmp/wget.log ]; then
		rm /tmp/wget.log &> /dev/null
	fi

	if [ -f /tmp/ex_status ]; then
		rm /tmp/ex_status &> /dev/null
	fi

	if (ps | grep "$pid" &> /dev/null) then
		kill "$pid" &> /dev/null
	fi
	
	echo " ${Red}Exit."
	exit 1
}

main
