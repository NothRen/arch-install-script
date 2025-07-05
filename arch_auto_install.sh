#!/bin/bash

# Regex
regex_number='^[0-9]+$'
regex_yes='^(yes|y|Yes|Y|o|oui|O|Oui)$'

# Formatting utilities 
BOLD='\e[1m'
ITALIC='\e[3m'
RED='\e[31m'
GREEN='\e[32m'
BLUE='\e[34m'
RESET='\e[0m'

# Needed packages
package_list=("base" "KERNEL" "linux-firmware" "KERNEL HEADERS" "base-devel" "nano" "git" "cmake" "meson" "networkmanager" "ufw" "sudo" "btrfs-progs" "bash-completion" "pkgfile" "fwupd" "smartmontools" "man-db" "man-pages" "grub" "efibootmgr" "linux-headers" "dkms" "reflector" "chrony")
# Graphical packages
hyprland_package=("wayland" "hyprland" "hyprland-protocols" "xdg-desktop-portal-hyprland")
gnome_package=("gnome" "gnome-extra")
gnome_package_complete=("gnome" "gnome-extra")
kde_package=("plasma-desktop")
kde_package_complete=("plasma-meta" "kde-applications-meta")

# System 
system_lang="fr_FR.UTF-8 UTF-8"
keyboard_lang="fr-latin1"
graphical_env="hyprland"
# Print functions

info_print(){
	 echo -e "${BOLD}${BLUE}[INFO]${RESET} ${BOLD}$1${RESET}"
}

user_interaction_print(){
	 echo -e "${BOLD}${GREEN}[USER]${RESET} $1"
}

error_print(){
	 echo -e "${BOLD}${RED}[ERROR]${RESET} ${BOLD}$1${RESET}"
}

# Other functions

# Check if bios is supported
check_bios_mode(){

	platform=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)

	if [ $? -ne 0 ] || [ $platform  -ne 64 ]; then
		error_print "This script only support UEFI in 64 bits"
		exit 1
	fi

}

# Choose keyboard layout
keyboard_layout_selector(){
	# TODO test this function
	user_interaction_print "What keyboard layout do you want ? Leave empty for french, else enter your 2 letters country code (CH for switzerland, IT for italia ...) to search in existing layout. Then enter your choosen layout"
	read layout
	
	case "$layout" in
		"") keyboard_lang="fr-latin1";;
		* )
			if ! localectl list-keymaps | grep -Fxq "$layout"; then
				localectl list-keymaps | grep -ie "$layout"
				return 1
			else
				info_print "Existing layout : "
				keyboard_lang=$layout
			fi
	esac
	info_print "${keyboard_lang} selected"
	loadkeys $keyboard_lang
	return 0
}

# Choose system language
system_language_selector(){
	user_interaction_print "What is your system language ? Leave empty for french, else enter your 2 letters country code to search in existing language. Then enter your choosen language"
	read lang
	
	case "$lang" in
		"") system_lang="fr_FR.UTF-8 UTF-8";;
		* )
			if ! cat /etc/locale.gen  | grep -Fxq "# $lang"; then
				info_print "Existing language : "
				cat /etc/locale.gen | grep -ie "$lang"
				return 1
			else
				system_lang=$lang
			fi
	esac
	info_print "${system_lang} selected"
	return 0
}

# Choose wich microcode is needed
microcode_selector(){
	CPU=$(grep vendor_id /proc/cpuinfo)

	if [[ "$CPU" == *"AuthenticAMD"* ]]; then
		package_list+=("amd-ucode")
	else
		package_list+=("intel-ucode")
	fi
}

# Partition and format the disk
partition_disk(){
	
	root_partition=""
	efi_partition=""
	swap_partition=""
	
	user_interaction_print "Use a swap partition ? [y/N]"
	read use_swap
	if [[ "$use_swap" =~ $regex_yes ]]; then
		user_interaction_print "Swap partition size ? (In Gib, integer only)"
		read swap_size
		if ! [[ $swap_size =~ $regex_number ]]; then
			error_print "Please enter a valid number"
			return 1
		fi
	fi


	user_interaction_print "Main partition size ? (In Gib, integer only)"
	read root_size
	if ! [[ $root_size =~ $regex_number ]]; then
		error_print "Please enter a valid number"
		return 1
	fi


	# create 1Gib efi partition TODO
	
	# create XGiB main partition TODO
	
	# create XGiB swap partition if use_swap TODO
	
	#  Format the partitions
	mkfs.fat -F 32 $efi_partition
	
	mkfs.btrfs $root_partition
	
	mkswap $swap_partition


	return 0
}

# Ask for kernel
kernel_selector(){

	user_interaction_print "Which kernel do you want ? (Default 1)"
	echo "
1 - Normal kernel
2 - Hardened kernel
3 - LTS kernel
4 - Zen kernel"

	read kernel_answer
		
	case "$kernel_answer" in
		1|"" ) kernel="linux";;
		2 ) kernel="linux-hardened";;
		3 ) kernel="linux-lts";;
		4 ) kernel="linux-zen";;
		* ) error_print "Enter a number between 1 and 4";return 1 ;;
	esac
	
	package_list[1]=$kernel
	package_list[3]="$kernel-headers"
	info_print "$kernel selected"
	
	return 0

}

hostname_selector(){
	
	user_interaction_print "What hostname do you want ?"
	read hostname
	if [[ -z "$hostname" ]]; then
		print_error "Hostname is needed"
		return 1
	fi
	
	echo "$hostname" > /mnt/etc/hostname
	
	return 0
	
}

check_internet(){
	info_print "Checking internet connection ..."
	
	ping -c 2 archlinux.org &> /dev/null
	if [ $? -ne 0 ]; then
		error_print "Please connect your computer to internet.
For wifi you can use ${ITALIC}iwctl${RESET}${BOLD} : 
[iwd]# device list
[iwd]# station ${ITALIC}name${RESET}${BOLD} scan
[iwd]# station ${ITALIC}name${RESET}${BOLD} get-networks
[iwd]# station ${ITALIC}name${RESET}${BOLD} connect ${ITALIC}SSID${RESET}"
		exit 1
	fi
	
	info_print "Internet connection working !"
	return 0
}

graphical_environment_selector(){
	user_interaction_print "Which graphical environment do you want :"
	echo "
	1) None (Default)
	2) Hyprland
	3) Gnome
	4) Kde plasma"
	
	read graphical_selected
	
	case $graphical_selected in
		1|"")graphical_env="none";;
		2)graphical_env="hyprland";;
		3)graphical_env="gnome";;
		4)graphical_env="kde";;
		*) 
			error_print "Please enter a number between 1 and 4"
			return 1;;
	esac
	info_print "$graphical_env is selected"
	return 0;
}

graphical_environment_setup(){
	case "$graphical_env" in
		"none") return 0;;
		"hyprland") until hyprland_setup; do : ; done;;
		"gnome") until gnome_setup; do : ; done;;
		"kde") until kde_setup; do : ; done;;
	esac
}

hyprland_setup(){
	# TODO install & setup hyprland
	echo ""
}

gnome_setup(){
	# TODO install & setup gnome
	echo ""
}

kde_setup(){
	# TODO install & setup kde plasma
	echo ""
}

info_print "Script start"

# TODO move this
until graphical_environment_selector; do : ; done

until graphical_environment_setup; do : ; done

# Check if bios is supported
check_bios_mode

# Check if internet is connected
check_internet

# Wait until the keyboard layout selection is successfull
until keyboard_layout_selector; do : ; done

# Wait until the system language selection is successfull
until system_language_selector; do : ; done

# Select a microcode
microcode_selector

# Select a kernel
until kernel_selector; do : ; done
 
exit # TODO remove

# Partition disk
until partition_disk; do : ; done

# Mount the partitions
mount $main_partition /mnt
mount --mkdir $efi_partition /mnt/boot

# Init the swap
if [ -n "$swap_partition" ]; then
	swapon $swap_partition
fi

# Select the hostname
until hostname_selector; do : ; done


# Inintialize pacman
print_info "Installing base packages"
pacstrap -K /mnt ${package_list[*]}

# Generate fstab file
genfstab -U /mnt >> /mnt/etc/fstab


exit 1 # TODO remove

# TODO check if the following work
arch-chroot /mnt /bin/bash -e <<EOF
	
	# Set timezone to Paris
	ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
	
	# Set up clock
	hwclock --systohc
	
	# Set language and keymaps
	echo "$system_lang" >> /etc/locale.gen
	locale-gen &> /dev/null
	echo "LANG=$system_lang" > /etc/locale.conf
	echo "KEYMAP=$keyboard_lang" > /etc/vconsole.conf
	
	
	# Generate initramfs
	mkinitcpio -P
	
	# Install grub
	grub-install --target=x86_64-efi --efi-directory=esp --bootloader-id=arch
	
	grub-mkconfig -o /boot/grub/grub.cfg

EOF

# TODO Configuring all services installed by pacstrap

# TODO set users

# TODO install nvida/amd drivers


