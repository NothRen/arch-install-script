#!/bin/bash

# Regex
regex_number='^[0-9]+$'
regex_yes='^(yes|y|Yes|Y|o|oui|O|Oui)$'

# Formatting utilities 
BOLD='\e[1m'
ITALIC='\e[3m'
RED='\e[31m'
BLUE='\e[34m'
RESET='\e[0m'
#echo -e '\e[3mitalic\e[23m'
# Needed packages
package_list=("base" "KERNEL" "linux-firmware" "KERNEL HEADERS" "base-devel" "nano" "git" "cmake" "meson" "networkmanager" "ufw" "sudo" "btrfs-progs" "bash-completion" "pkgfile" "fwupd" "smartmontools" "man-db" "man-pages" "grub" "efibootmgr" "linux-headers" "dkms" "reflector" "chrony")
hyprland_package=("wayland" "hyprland" "hyprland-protocols" "xdg-desktop-portal-hyprland")

# System 
lang="fr_FR.UTF-8"
keyboard_lang="fr-latin1"

# Print functions

info_print(){
	 echo -e "${BOLD}${BLUE}[INFO]${RESET} ${BOLD}$1${RESET}"
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
	
	echo "Use a swap partition ? [y/N]"
	read use_swap
	if [[ "$use_swap" =~ $regex_yes ]]; then
		echo "Swap partition size ? (In Gib, integer only)"
		read swap_size
		if ! [[ $swap_size =~ $regex_number ]]; then
			error_print "Please enter a valid number"
			return 1
		fi
	fi


	echo "Main partition size ? (In Gib, integer only)"
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

	cat << EOF
Which kernel do you want ? (Default 1)
1 - Normal kernel
2 - Hardened kernel
3 - LTS kernel
4 - Zen kernel
EOF

	read kernel_answer
		
	case "$kernel_answer" in
		1 ) kernel="linux";;
		2 ) kernel="linux-hardened";;
		3 ) kernel="linux-lts";;
		4 ) kernel="linux-zen";;
		* ) error_print "Veuillez répondre oui ou non";return 1 ;;
	esac
	
	package_list[1]=$kernel
	package_list[3]="$kernel-headers"
	
	return 0

}

hostname_selector(){
	
	echo "What hostname do you want ?"
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

info_print "Script start"

# Check if bios is supported
check_bios_mode

# Load keyboard layout
loadkeys $keyboard_lang

check_internet

# Select a microcode
microcode_selector

# Select a kernel
until kernel_selector; do : ; done
 
exit # TODO

# Partition disk
until partition_disk; do : ; done

# Mount the partitions
mount $main_partition /mnt
mount --mkdir $efi_partition /mnt/boot

# Init the swap
if [ -n "$swap_partition" ]; then
	swapon $swap_partition
fi


until hostname_selector; do : ; done



# Inintialize pacman
print_info "Installing base packages"
pacstrap -K /mnt ${package_list[*]}

# Generate fstab file
genfstab -U /mnt >> /mnt/etc/fstab


exit 1 # TODO

arch-chroot /mnt /bin/bash -e <<EOF
	
	# Set timezone to Paris
	ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
	
	# Set up clock
	hwclock --systohc
	
	# Set language and keymaps
	echo "$lang" >> /etc/locale.gen
	locale-gen &> /dev/null
	echo "LANG=$lang" > /etc/locale.conf
	echo "KEYMAP=$keyboard_lang" > /etc/vconsole.conf
	
	
	# Generate initramfs
	mkinitcpio -P
	
	# Install grub
	grub-install --target=x86_64-efi --efi-directory=esp --bootloader-id=arch
	
	grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Configuring all services installed by pacstrap




