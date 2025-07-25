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
package_list=("base" "KERNEL" "linux-firmware" "KERNEL HEADERS" "base-devel" "nano" "git" "cmake" "meson" "networkmanager" "ufw" "sudo" "btrfs-progs" "bash-completion" "pkgfile" "fwupd" "smartmontools" "man-db" "man-pages" "grub" "efibootmgr" "dkms" "reflector" "ntfs-3g" "lynis" "7zip" "xdg-user-dirs" "pacman-contrib" "util-linux")
# service
services=(NetworkManager.service reflector.timer ufw.service pkgfile-update.timer fwupd.service fwupd-refresh.timer pacman-filesdb-refresh.timer)

# System 
system_lang="fr_FR.UTF-8 UTF-8"
keyboard_lang="fr-latin1"
graphical_env="hyprland"
# Print functions

separator_print(){
	echo "---------------------------"
}

info_print(){
	 echo -e "${BOLD}${BLUE}[INFO]${RESET} ${BOLD}$1${RESET}"
}

user_interaction_print(){
	 echo -e "${BOLD}${GREEN}[USER]${RESET} $1"
}

error_print(){
	 echo -e "${BOLD}${RED}[ERROR]${RESET} ${BOLD}$1${RESET}"
}

# Helper functions

# install given packages. To call the function : install_packages "${array[@]}"
install_packages() {
	packages_to_install=("$@")
	pacstrap -G /mnt ${packages_to_install[*]}
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
	# Not working
	user_interaction_print "What keyboard layout do you want ? Leave empty for french, else enter your 2 letters country code (CH for switzerland, IT for italia ...) to search in existing layout. Then enter your choosen layout (leave empty to select fr-latin1)"
	read layout
	
	case "$layout" in
		"") keyboard_lang="fr-latin1";;
		* )
			if ! $(localectl list-keymaps | grep -Fxq "$layout"); then
				info_print "Corresponding keymaps :"
				localectl list-keymaps | grep -ie "$layout"
				return 1
			else
				#info_print "Existing layout : "
				keyboard_lang=$layout
			fi
	esac
	info_print "${keyboard_lang} selected"
	loadkeys $keyboard_lang
	return 0
}

# Choose system language
system_language_selector(){
	user_interaction_print "What is your system language ? Leave empty for french, else enter your 2 letters country code to search in existing language. Then enter your choosen language (leave empty to select fr_FR.UTF-8 UTF-8)"
	read lang
	
	case "$lang" in
		"") system_lang="fr_FR.UTF-8 UTF-8";;
		* )
			if ! cat /etc/locale.gen  | grep -Fxq "#$lang"; then
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

# Choose which microcode is needed
microcode_selector(){
	CPU=$(grep vendor_id /proc/cpuinfo)

	if [[ "$CPU" == *"AuthenticAMD"* ]]; then
		package_list+=("amd-ucode")
	else
		package_list+=("intel-ucode")
	fi
}

# Choose root password 
root_pwd_selector(){
	# Select the root password
	user_interaction_print "Type the root password : "
	read -r -s rootpwd

	if [ -z "$rootpwd" ]; then
		error_print "Please enter a non empty password"
		return 1
	fi

	user_interaction_print "Type the root password again : "
	read -r -s rootpwd_check
	
	if [ "$rootpwd" != "$rootpwd_check" ]; then
		error_print "Passwords don't match, please try again"
		return 1
	fi
	
	return 0
}
# Choose to add an user or not
user_pwd_selector(){
	user_interaction_print "Do you want to create another user ? [y/N]"
	read create_user
	
	if ! [[ $create_user =~ $regex_yes ]]; then
		
		info_print "Not creating a user"
		return 0
		
	fi
	
	user_interaction_print "Enter the username of your new user : "
	read username
	
	if [ -z "$username" ]; then
		error_print "Please enter a non empty username"
		return 1
	fi
	
	user_interaction_print "Should your user use the same password as root ? [y/N]"
	read user_same_pwd
	if [[ $user_same_pwd =~ $regex_yes ]]; then
		
		info_print "Same password used"
		$userpwd=$rootpwd
		return 0
		
	fi
	
	user_interaction_print "Type the password for ${username} : "
	read -r -s userpwd

	if [ -z "$userpwd" ]; then
		error_print "Please enter a non empty password"
		return 1
	fi

	user_interaction_print "Type the password for ${username} again : "
	read -r -s userpwd_check
	
	if [ "$userpwd" != "$userpwd_check" ]; then
		error_print "Passwords don't match, please try again"
		return 1
	fi
	
	return 0
}

# Partition and format the disk
partition_disk(){
	
	disk=""
	disk_total_space=""
	root_partition=""
	efi_partition=""
	swap_partition=""

	# Ask the user on which disk arch should be installed 	
	user_interaction_print "On which disk arch should be installed (ex : sda, nvme0n1) ? It will remove all existing partition on the disk"
	
	# Show all disks
	lsblk
	
	# Read the answer and verify if the disk exist
	read selected_disk
	if [ -z ${selected_disk} ] || ! (lsblk | grep "${selected_disk}.*disk"&> /dev/null) || ! (ls /dev/${selected_disk}&> /dev/null); then
		error_print "This disk doesn't exist"
		return 1
	fi
	
	info_print "${selected_disk} is selected"
	
	# Get the path to the disk
	disk_path="/dev/${selected_disk}"

	# Get the disk total space
	disk_total_space=$(($(lsblk -bo NAME,SIZE | grep "$selected_disk" | head -n1 | grep -oE "[0-9,]{10,}")/1024/1024/1024))
	cmd_res=$?
	
	# Check if the disk is more than 30Gib
	if [ $cmd_res -eq 1 ] || [ $disk_total_space -lt 30 ] ; then 
		error_print "Your disk must be at least 30Gib"
		exit 1
	fi

	# Ask the user the size of swap partition
	user_interaction_print "Swap partition size ? (In Gib, integer only) Left empty to not use swap "
	read swap_size
	if [ -z "$swap_size" ] || [ $swap_size -eq 0 ]; then
		info_print "Not using swap"
		swap_size=0
	else
		if ! [[ $swap_size =~ $regex_number ]] ; then
			error_print "Please enter a valid number"
			return 1
		fi
		info_print "Using a ${swap_size}Gib swap partition"
	fi
	
	# Ask the user the size of root partition
	user_interaction_print "Main partition size ? (In Gib, integer only)"
	read root_size
	if  [[ ! $root_size =~ $regex_number ]] && [ ! -z "$root_size" ] ; then
		error_print "Please enter a valid number or an empty input"
		return 1
	fi
	
	if [[ -z ${root_size} ]]; then
		info_print "Creating main partition using all available space"
	else
		info_print "Creating a ${root_size}Gib main partition"
	fi
	
	
	# Ask the user for confirmation before writing to disk
	user_interaction_print "On ${disk_path} it will create :"
	echo "A 1Gib efi partition"
	
	if [ ! -z "$swap_size" ] && [ ! $swap_size -eq 0 ]; then
		echo "A ${swap_size}Gib swap partition"
	fi
	
	if  [ ! -z "$root_size" ]; then
		echo "A ${root_size}Gib root partition"
	else
	 	echo "A $(($disk_total_space-$swap_size-1))Gib root partition"
	fi
	
	user_interaction_print "Is it OK ? All existing partition on ${disk_path} will be removed [y/n]"
	read disk_answer
	if ! [[ $disk_answer =~ $regex_yes ]] ; then
		error_print "Return to the start of the disk partitionning"
		return 1
	fi
	
	# If root size is not empty add + and G for fdisk below
	if [ ! -z "$root_size" ];then
		root_size="+${root_size}G"
	fi
	
	if [ $is_arch -eq 0 ];then
		info_print "Skipping partitionning because the script does not run on arch."
		return 0
	fi

	# Remove all partition from disk
	blkdiscard -f $disk_path

	info_print "Creating the partition"
	# Create the partition with with fdisk
	if [ ! -z "$swap_size" ] && [ ! $swap_size == 0 ]; then
		(echo "n"; echo "p"; echo ""; echo ""; echo "+1G"; echo "t"; echo "uefi"; \
		echo "n"; echo "p"; echo ""; echo ""; echo "+${swap_size}G"; echo "t"; echo ""; echo "swap"; \
		echo "n"; echo "p"; echo ""; echo ""; echo "${root_size}"; echo "w") | fdisk $disk_path
	else
		(echo "n"; echo "p"; echo ""; echo ""; echo "+1G"; echo "t"; echo "uefi"; \
		echo "n"; echo "p"; echo ""; echo ""; echo "${root_size}"; echo "w") | fdisk $disk_path
	fi
	
	partitions=( $(lsblk "$disk_path" | grep -oE "$selected_disk[^ ]*\w") )

	efi_partition=${partitions[0]}

	if [ ! -z "$swap_size" ] && [ ! $swap_size == 0 ]; then
		swap_partition=${partitions[1]}
		root_partition=${partitions[2]}
	else 
		root_partition=${partitions[1]}
	fi

	info_print "Formatting the partition"
	#  Format the partitions 
	mkfs.fat -F 32 "/dev/${efi_partition}"
	
	mkfs.btrfs "/dev/${root_partition}"
	
	if ! [ -z $swap_partition ];then
		mkswap "/dev/${swap_partition}"
	fi

	
	# Check if installed disk is a ssd, if yes enable weekly trim
	if [ $(cat /sys/block/${selected_disk}/queue/rotational) -eq 0 ];then
		services+=(fstrim.timer)
	fi

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

# Ask for hostname 
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

# Timezone selector
# TODO ?

# Check internet connection
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
	
	info_print "Internet connection found"
	return 0
}

# Ask for the graphical environment
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

# Installed the asked graphical environment
graphical_environment_setup(){

	# Graphical packages
	global_graphical_packages=("wayland" "xorg-xwayland" "xdg-desktop-portal" "qt6-wayland" "qt5-wayland" "gtk3" "gtk4" "wl-clip-persist" "pipewire" "pipewire-audio" "pipewire-alsa" "pipewire-pulse" "alsa-utils")
	
	graphical_package_app=("firefox" "gnome-disk-utility" "udisks2-btrfs" "code")
	
	if [ "$graphical_env" != "none" ]; then
		info_print "Installing global graphical packages"
		# install global graphical packages
		install_packages ${global_graphical_packages[@]}
		
		install_packages ${graphical_package_app[@]} 
		
		services+=(pipewire-pulse.service)
		
		gpu_driver_setup
	fi

	case "$graphical_env" in
		"none") return 0;;
		"hyprland") until hyprland_setup; do : ; done;;
		"gnome") until gnome_setup; do : ; done;;
		"kde") until kde_setup; do : ; done;;
	esac
	
}

# Setup the gpu driver
gpu_driver_setup(){

	info_print "Setup gpu driver"
	# Check which gpu is here
	gpus=$(lspci | grep VGA)
	nvidia=$(echo $gpus | grep -i nvidia)
	intel=$(echo $gpus | grep -i intel)
	amd=$(echo $gpus | grep -i amd)
	
	if ! [ -z $nvidia ];then
		nvidia_card_number=$(lspci | grep VGA | grep -i nvidia | grep -E "(RTX|GTX) ([0-9]{4})" | grep -oE "([0-9]{4})")
		if [ $nvidia_card_number -lt 1650 ];then
			error_print "This script only support nvidia gpu newer than GeForce GTX 1650."
			return 1
		fi
		nvidia_gpu_driver_setup
	fi
	
	if ! [ -z $amd ];then
		# TODO
		# amd_gpu_driver_setup
	fi
	
	if ! [ -z $intel ];then
		# TODO
		# intel_gpu_driver_setup
	fi
	
	return 0
}

# Install nvidia gpu drivers
nvidia_gpu_driver_setup(){
	# TODO Test if this is working
	nvidia_driver_packages=("nvidia-open-dkms" "nvidia-utils" "lib32-nvidia-utils" "vulkan-icd-loader" "lib32-vulkan-icd-loader" "nvidia-settings")
	
	install_packages ${nvidia_driver_packages[@]}
	services+=(nvidia-suspend.service)
	services+=(nvidia-hibernate.service)
	services+=(nvidia-resume.service)
	cat >> /etc/environment << EOF
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia	
EOF

	# NVreg_DynamicPowerManagement=0x02 and NVreg_DynamicPowerManagementVideoMemoryThreshold=100 can be useful for laptop

	# Enable parameters for the nvidia kernel modules (https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks#Preserve_video_memory_after_suspend)
	echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp NVreg_UsePageAttributeTable=1 NVreg_DynamicPowerManagement=0x02" >> /mnt/etc/modprobe.d/nvidia.conf
		echo "options nvidia_drm modeset=1 fbdev=1" >> /mnt/etc/modprobe.d/nvidia.conf

	# Load nvidia, nvidia_modeset, nvidia_uvm  and nvidia_drm kernel modules
	sed -i "s/MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /" /mnt/etc/mkinitcpio.conf
	
	sed -i "s/FILES=(/FILES=(/etc/modprobe.d/nvidia.conf /" /etc/mkinitcpio.conf

	# Regenerate initramfs
	arch-chroot /mnt mkinitcpio -P
	
	return 0
}

# Setup hyprland
hyprland_setup(){
	# TODO test if this is working
	info_print "Installing hyprland packages"

	hyprland_package=("uwsm" "hyprland" "hyprland-protocols" "xdg-desktop-portal-hyprland" "hyprpaper" "kitty" "sddm" "playerctl" "qt6-svg" "qt6-virtualkeyboard" "qt6-multimedia-ffmpeg")
	
	install_packages ${hyprland_package[@]}
	services+=(sddm.service)
	
	mkdir /mnt/etc/sddm.conf.d
	cat > /mnt/etc/sddm.conf.d/sddm.conf << EOF

    [General]
    Numlock=on
    DisplayServer=wayland
    InputMethod=qtvirtualkeyboard
    GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard

    [Theme]
    Current=silent
    
    [Wayland]
    CompositorCommand=Hyprland
	
EOF
	
	# Ask to install my config file
	
	# Install silent theme for sddm https://github.com/uiriansan/SilentSDDM
	curl https://github.com/uiriansan/SilentSDDM/archive/refs/tags/v1.2.1.tar.gz > silent.tar.gz
	mkdir -p /mnt/usr/share/sddm/themes/silent
	tar -xf silent.tar.gz -C /mnt/usr/share/sddm/themes/silent/
	cp /mnt/usr/share/sddm/themes/silent/fonts/* /usr/share/fonts
	
	info_print "Hyprland installation succeed"
	return 0
}

# Setup gnome
gnome_setup(){
	info_print "Installing gnome packages"
	gnome_package=("gnome" "xdg-desktop-portal-gnome" "gnome-tweaks")
	gnome_package_complete=("gnome-extra")

	install_packages ${gnome_package[@]}
	services+=(gdm.service)
	
	user_interaction_print "Do you want to add additional gnome applications [y/N]"
	read $install_gnome_app
	
	if [[ $install_gnome_app =~ $regex_yes ]];then
		install_packages ${gnome_package_complete[@]}
	fi
	
	info_print "Gnome installation succeed"
	return 0
}

# Setup kde plasma
kde_setup(){
	info_print "Installing kde packages"
	
	kde_package=( "plasma-desktop" "xdg-desktop-portal-kde" "plasma-meta" "sddm" "konsole" "dolphin")
	kde_package_complete=("kde-applications-meta")
	
	install_packages ${kde_package[@]}
	services+=(sddm.service)
	
	user_interaction_print "Do you want to add additional kde applications [y/N]"
	read $install_kde_app
	
	if [[ $install_kde_app =~ $regex_yes ]];then
		install_packages ${kde_package_complete[@]}
	fi
	
	
	
	info_print "Kde installation succeed"
	return 0
}

info_print "Script start"

# Check if the distrib is arch, if it is not print an error

if ! cat /etc/lsb-release | grep "Arch"&>/dev/null ;then
	is_arch=0
	if [ -z ${check_arch+x} ];then
		error_print "This script work only on arch live iso. If you want to run it anyway add ${ITALIC}check_arch=0${RESET}${BOLD} before running the script (ex : $ ${ITALIC}check_arch=0 ./arch_auto_install.sh ${RESET})"
	exit 1
	fi
else
	is_arch=1
fi

# Check if bios is supported
check_bios_mode

# Check if internet is connected
check_internet;separator_print

# Wait until the keyboard layout selection is successfull
until keyboard_layout_selector; do : ; done
separator_print

# Wait until the system language selection is successfull
until system_language_selector; do : ; done
separator_print

# Select a microcode
microcode_selector

# Select a kernel
until kernel_selector; do : ; done
separator_print

# Select the graphical environment
until graphical_environment_selector; do : ; done
separator_print

# Select the root password and if a user must be created
until root_pwd_selector; do : ; done
separator_print

until user_pwd_selector; do : ; done
separator_print

# Partition disk
until partition_disk; do : ; done
separator_print

# Mount the partitions
mount "/dev/${root_partition}" /mnt
mount --mkdir "/dev/${efi_partition}" /mnt/boot

# Init the swap
if [ -n "$swap_partition" ]; then
	swapon $swap_partition
fi

# Inintialize pacman
info_print "Installing base packages"
pacstrap -K /mnt ${package_list[*]}
separator_print

# Select the hostname
until hostname_selector; do : ; done
separator_print

# Create the hosts file
cat > /mnt/etc/hosts <<EOF
127.0.0.1	localhost
::1			localhost
127.0.0.1	$hostname
EOF

# Generate fstab file
info_print "Generating fstab file"
genfstab -U /mnt >> /mnt/etc/fstab


# TODO add an option to choose the timezone OR use (http://ip-api.com/line?fields=timezone)
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
	
	# Create users directory using xdg-user-dirs
	xdg-user-dirs-update
	
	# Syncing pkgfile
	pkgfile -u
	
	# Enable automatique pkgfile refresh
	cp /usr/lib/systemd/system/pkgfile-update.timer /etc/systemd/system/pkgfile-update.timer
	sed -i 's/OnCalendar=daily/OnCalendar=weekly/' /etc/systemd/system/pkgfile-update.timer
	
	# Add command not found script from pkgfile to the global bashrc
	echo "source /usr/share/doc/pkgfile/command-not-found.bash" >> /etc/skel/.bashrc
	
	# Add .bash* file to root directory
	cp /etc/skel/.bash* ~
	
	# Disable passim (used in fwupd) 
	echo "P2pPolicy=nothing" >> /etc/fwupd/fwupd.conf
	systemctl mask passim.service
	
	# Generate initramfs
	mkinitcpio -P
	
	# Install grub
	grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=arch
	
	grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Set root password
separator_print
info_print "Setting up root password"
echo "root:$rootpwd" | arch-chroot /mnt chpasswd

# Add user
if [[ $create_user =~ $regex_yes ]]; then
	info_print "Setting up a user : $username"
	
	# Add user and set its password
	arch-chroot /mnt useradd -m -G wheel -s /bin/bash $username
	echo "${username}:${userpwd}" | arch-chroot /mnt chpasswd
	
	# Create user directory with xdg-user-dirs-update
	arch-chroot /mnt sudo -H -u $username bash -c 'xdg-user-dirs-update'
	# Give wheel group administrator rights and set the timeout for password to 10min
	echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/groups
	echo "Defaults timestamp_timeout=10" >> /mnt/etc/sudoers.d/groups
	
	cat > /mnt/home/${username}/.profile << EOF
xdg-user-dirs-update
EOF

	# Make ~/.bashrc to execute ~/.profile
	echo ". \$HOME/.profile" >> /mnt/home/${username}/.bashrc
	
fi

# Install a graphical environment
separator_print
until graphical_environment_setup; do : ; done

# Packages setup
separator_print
info_print "Set up installed packages"

# Disable iptables.service beacause it is not compatible with ufw
systemctl disable iptables.service --root=/mnt

# Enable systemd service from pacman packages
for service in "${services[@]}"; do
	systemctl enable "$service" --root=/mnt
done

# Disable remote ping
sed -i 's/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/' /mnt/etc/ufw/before.rules

# Set reflector config
cat > /mnt/etc/xdg/reflector/reflector.conf << EOF
--save /etc/pacman.d/mirrorlist
--country France,Germany
--protocol https
--latest 10
EOF

# Change pacman config
sed -i 's/#Color/Color\nILoveCandy/g' /mnt/etc/pacman.conf

# 
cat >> /mnt/etc/pacman.conf << EOF
[multilib]
Include = /etc/pacman.d/mirrorlist
EOF


separator_print
# Ask the user if the script should stop the computer
info_print "Installation finished"
user_interaction_print "Shutdown the computer now ? y/N"
read restart_answer
if [[ $restart_answer =~ $regex_yes ]];then
	info_print "Shutdown"
	umount -R /mnt
	shutdown now
fi

info_print "Script has finished, you can now restart your computer."
exit 0

