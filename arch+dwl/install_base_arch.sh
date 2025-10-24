#!/bin/bash

# Arch Linux 基础系统安装脚本（含 Btrfs、静态 IPv4、NVIDIA）
# 基于 2025 年 10 月 23 日的 Arch Linux Wiki
# 优化：交互式菜单（dialog），模块化设计，静态 IPv4 配置
# 运行环境：Arch Linux Live ISO，需 root 权限

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 日志文件
LOGFILE="/root/install_base_arch.log"
echo "Arch Linux Base System Installation Log - $(date)" > "$LOGFILE"

# 错误处理
set -e
trap 'echo -e "${RED}Error: Script failed at line $LINENO, please check $LOGFILE!${NC}"' ERR

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: Please run this script as root user!${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 安装 dialog
install_dialog() {
    echo "Installing dialog tool..." | tee -a "$LOGFILE"
    pacman -Sy --noconfirm dialog || {
        echo -e "${RED}Error: Failed to install dialog!${NC}" | tee -a "$LOGFILE"
        exit 1
    }
    echo -e "${GREEN}Dialog installation completed.${NC}" | tee -a "$LOGFILE"
}

# 检查 UEFI 模式
check_uefi() {
    echo "Checking UEFI mode..." | tee -a "$LOGFILE"
    if [[ ! -d /sys/firmware/efi ]]; then
        dialog --msgbox "UEFI mode not detected, please check BIOS settings and restart!" 8 40
        echo -e "${RED}Error: Non-UEFI mode${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    dialog --msgbox "UEFI mode confirmed." 6 30
    echo -e "${GREEN}UEFI mode confirmed.${NC}" | tee -a "$LOGFILE"
}

# 检查和配置网络（支持静态 IPv4）
check_network() {
    echo "Checking network connectivity..." | tee -a "$LOGFILE"
    if ping -c 1 archlinux.org &> /dev/null; then
        dialog --msgbox "Network connection is normal." 6 30
        echo -e "${GREEN}Network connection is normal.${NC}" | tee -a "$LOGFILE"
    else
        dialog --yesno "Network not connected! Configure wireless network?" 8 40
        if [[ $? -eq 0 ]]; then
            systemctl start iwd
            dialog --msgbox "Please run the following commands to configure wireless network:\nstation wlan0 scan\nstation wlan0 get-networks\nstation wlan0 connect 'Your-Wifi-SSID'\nClick OK when done." 10 50
            iwctl
            if ! ping -c 1 archlinux.org &> /dev/null; then
                dialog --msgbox "Network still not connected, please check and retry!" 8 40
                echo -e "${RED}Error: Network connection failed${NC}" | tee -a "$LOGFILE"
                exit 1
            fi
            dialog --msgbox "Wireless network connected successfully." 6 30
            echo -e "${GREEN}Wireless network connected successfully.${NC}" | tee -a "$LOGFILE"
        else
            dialog --msgbox "Network not connected, script cannot continue!" 8 40
            echo -e "${RED}Error: Network not connected${NC}" | tee -a "$LOGFILE"
            exit 1
        fi
    fi

    # 询问是否配置静态 IPv4
    dialog --yesno "Configure static IPv4 for the installed system?" 8 40
    if [[ $? -eq 0 ]]; then
        dialog --yesno "Configure static IPv4 for wireless network (Wi-Fi)? Otherwise configure for wired network." 8 40
        IS_WIFI=$([[ $? -eq 0 ]] && echo "yes" || echo "no")
        IP_ADDR=$(dialog --inputbox "Enter static IPv4 address (e.g. 192.168.1.100)" 8 40 2>&1 >/dev/tty)
        SUBNET_MASK=$(dialog --inputbox "Enter subnet mask (e.g. 255.255.255.0 or /24)" 8 40 2>&1 >/dev/tty)
        GATEWAY=$(dialog --inputbox "Enter default gateway (e.g. 192.168.1.1)" 8 40 2>&1 >/dev/tty)
        DNS_SERVERS=$(dialog --inputbox "Enter DNS servers (comma separated, e.g. 8.8.8.8,8.8.4.4)" 8 40 2>&1 >/dev/tty)
        if [[ -z "$IP_ADDR" || -z "$SUBNET_MASK" || -z "$GATEWAY" || -z "$DNS_SERVERS" ]]; then
            dialog --msgbox "Incomplete static IPv4 configuration provided, will use DHCP!" 8 40
            echo -e "${RED}Warning: Incomplete static IPv4 configuration, using DHCP${NC}" | tee -a "$LOGFILE"
            IS_STATIC="no"
        else
            IS_STATIC="yes"
            if [[ "$SUBNET_MASK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                SUBNET_MASK=$(echo "$SUBNET_MASK" | awk -F. '{print ($1*256^3 + $2*256^2 + $3*256 + $4)}' | bc | awk '{for(i=0; $1>0; i++) $1/=2; print i}')
            fi
            if [[ "$IS_WIFI" == "yes" ]]; then
                WIFI_SSID=$(dialog --inputbox "Enter Wi-Fi SSID" 8 40 2>&1 >/dev/tty)
                if [[ -z "$WIFI_SSID" ]]; then
                    dialog --msgbox "No Wi-Fi SSID provided, will use DHCP!" 8 40
                    echo -e "${RED}Warning: No Wi-Fi SSID provided, using DHCP${NC}" | tee -a "$LOGFILE"
                    IS_STATIC="no"
                fi
            fi
            echo -e "${GREEN}Static IPv4 configuration: IP=$IP_ADDR/$SUBNET_MASK, Gateway=$GATEWAY, DNS=$DNS_SERVERS${NC}" | tee -a "$LOGFILE"
            if [[ "$IS_WIFI" == "yes" ]]; then
                echo "Wi-Fi SSID: $WIFI_SSID" | tee -a "$LOGFILE"
            fi
        fi
    else
        IS_STATIC="no"
        echo -e "${GREEN}Will use DHCP for network configuration.${NC}" | tee -a "$LOGFILE"
    fi
}

# 检查时间同步
check_timesync() {
    echo "Checking Live environment time synchronization..." | tee -a "$LOGFILE"
    if timedatectl status | grep -q "NTP service: active"; then
        dialog --msgbox "Time synchronization is normal." 6 30
        echo -e "${GREEN}Time synchronization is normal.${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "NTP service not enabled, please check Live environment!" 8 40
        echo -e "${RED}Error: NTP service not enabled${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 选择硬盘
select_disk() {
    echo "Scanning available disks..." | tee -a "$LOGFILE"
    DISKS=($(lsblk -d -n -o NAME | grep -E '^(sd|nvme)'))
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        dialog --msgbox "No available disks found! Please check hardware." 8 40
        echo -e "${RED}Error: No disks found${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    MENU=()
    for disk in "${DISKS[@]}"; do
        MENU+=("/dev/$disk" "$(lsblk -d -n -o SIZE,MODEL /dev/$disk)")
    done
    DISK=$(dialog --menu "Select main hard disk (WARNING: Data will be erased!)" 15 60 5 "${MENU[@]}" 2>&1 >/dev/tty)
    if [[ -z "$DISK" ]]; then
        dialog --msgbox "No disk selected, script exiting!" 8 40
        echo -e "${RED}Error: No disk selected${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    dialog --msgbox "Selected disk: $DISK" 6 30
    echo -e "${GREEN}Using disk: $DISK${NC}" | tee -a "$LOGFILE"
}

# 分区磁盘
partition_disk() {
    dialog --msgbox "About to start fdisk partitioning $DISK.\nRecommendations:\n1. Create 1G EFI partition (${DISK}p1), type: EFI System (1)\n2. Create remaining space Btrfs partition (${DISK}p2), type: Linux filesystem (20)\nSave and exit when done (w).\nClick OK to start fdisk..." 12 50
    fdisk "$DISK"
    if [[ ! -b "${DISK}p1" || ! -b "${DISK}p2" ]]; then
        dialog --msgbox "Partitioning failed, ${DISK}p1 or ${DISK}p2 not found!" 8 40
        echo -e "${RED}Error: Partitioning failed${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    dialog --msgbox "Partitioning completed." 6 30
    echo -e "${GREEN}Partitioning completed.${NC}" | tee -a "$LOGFILE"
}

# 格式化分区
format_partitions() {
    echo "Formatting partitions..." | tee -a "$LOGFILE"
    mkfs.fat -F 32 "${DISK}p1"
    mkfs.btrfs -f -O ssd "${DISK}p2"
    dialog --msgbox "Partition formatting completed." 6 30
    echo -e "${GREEN}Partition formatting completed.${NC}" | tee -a "$LOGFILE"
}

# 创建并挂载 Btrfs 子卷
setup_btrfs() {
    echo "Creating and mounting Btrfs subvolumes..." | tee -a "$LOGFILE"
    mount "${DISK}p2" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@swap
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@cache
    umount /mnt
    mkdir -p /mnt/{home,var/log,var/cache,swap,boot}
    mount -o subvol=@,compress=zstd,noatime "${DISK}p2" /mnt
    mount -o subvol=@home,compress=zstd,noatime "${DISK}p2" /mnt/home
    mount -o subvol=@log,compress=zstd,noatime "${DISK}p2" /mnt/var/log
    mount -o subvol=@cache,compress=zstd,noatime "${DISK}p2" /mnt/var/cache
    mount -o subvol=@swap "${DISK}p2" /mnt/swap
    mount "${DISK}p1" /mnt/boot
    if mount | grep -q "/mnt"; then
        dialog --msgbox "Btrfs subvolumes mounted successfully." 6 30
        echo -e "${GREEN}Btrfs subvolumes mounting completed.${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "Mount failed, please check!" 8 40
        echo -e "${RED}Error: Mount failed${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 创建 Swapfile
create_swapfile() {
    echo "Creating 64GB Swapfile..." | tee -a "$LOGFILE"
    chattr +C /mnt/swap
    btrfs filesystem mkswapfile --size 64g --uuid clear /mnt/swap/swapfile
    chmod 600 /mnt/swap/swapfile
    mkswap /mnt/swap/swapfile
    swapon /mnt/swap/swapfile
    if swapon -s | grep -q "/mnt/swap/swapfile"; then
        swapoff /mnt/swap/swapfile
        dialog --msgbox "Swapfile created successfully." 6 30
        echo -e "${GREEN}Swapfile creation completed.${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "Swapfile creation failed!" 8 40
        echo -e "${RED}Error: Swapfile creation failed${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 安装基础系统
install_system() {
    dialog --yesno "Enable wireless support (install iwd)?" 8 40
    IWD=$([[ $? -eq 0 ]] && echo "iwd" || echo "")
    echo "Installing base system and packages..." | tee -a "$LOGFILE"
    pacstrap /mnt base linux linux-headers systemd vim networkmanager \
        btrfs-progs base-devel git \
        nvidia-open-dkms nvidia-settings nvidia-utils lib32-nvidia-utils libva-nvidia-driver egl-wayland
    dialog --msgbox "Base packages installation completed." 6 30
    echo -e "${GREEN}Base packages installation completed.${NC}" | tee -a "$LOGFILE"
}

# 配置 fstab
configure_fstab() {
    echo "Generating fstab file..." | tee -a "$LOGFILE"
    genfstab -U /mnt >> /mnt/etc/fstab
    echo "/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
    dialog --msgbox "Please check /mnt/etc/fstab, ensure Btrfs subvolumes and Swapfile are configured correctly.\nClick OK to open nano..." 10 50
    nano /mnt/etc/fstab
    dialog --msgbox "fstab configuration completed." 6 30
    echo -e "${GREEN}fstab configuration completed.${NC}" | tee -a "$LOGFILE"
}

# 配置系统（chroot）
configure_system() {
    echo "Entering chroot environment and configuring system..." | tee -a "$LOGFILE"
    arch-chroot /mnt /bin/bash << EOF
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
LOGFILE="/root/install_base_arch.log"

# 时区与时间同步
echo "Setting timezone and time synchronization..." | tee -a "\$LOGFILE"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
systemctl enable --now systemd-timesyncd
cat << EOT > /etc/systemd/timesyncd.conf
[Time]
NTP=cn.pool.ntp.org time.google.com
FallbackNTP=pool.ntp.org
EOT
systemctl restart systemd-timesyncd
if timedatectl status | grep -q "System clock synchronized: yes"; then
    echo -e "\${GREEN}Time synchronization enabled successfully.\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${RED}Error: Time synchronization failed\${NC}" | tee -a "\$LOGFILE"
    exit 1
fi

# 本地化
echo "Configuring localization..." | tee -a "\$LOGFILE"
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# 主机名和 hosts
echo "Setting hostname and hosts..." | tee -a "\$LOGFILE"
echo "dev" > /etc/hostname
cat << EOT > /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.1.1	dev.localdomain	dev
EOT
if ping -c 1 localhost &> /dev/null && ping -c 1 dev &> /dev/null; then
    echo -e "\${GREEN}hosts configuration verification passed.\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${RED}Error: hosts configuration failed\${NC}" | tee -a "\$LOGFILE"
    exit 1
fi

# 网络服务
echo "Enabling network services..." | tee -a "\$LOGFILE"
systemctl enable NetworkManager
if [[ -f /usr/bin/iwd ]]; then
    systemctl enable iwd
fi

# 配置静态 IPv4
if [[ "$IS_STATIC" == "yes" ]]; then
    echo "Configuring static IPv4..." | tee -a "\$LOGFILE"
    mkdir -p /etc/NetworkManager/system-connections
    if [[ "$IS_WIFI" == "yes" ]]; then
        cat << EOT > /etc/NetworkManager/system-connections/static-wifi.nmconnection
[connection]
id=static-wifi
type=wifi
interface-name=wlan0
autoconnect=true

[wifi]
ssid=$WIFI_SSID
mode=infrastructure

[ipv4]
method=manual
address1=$IP_ADDR/$SUBNET_MASK
gateway=$GATEWAY
dns=$DNS_SERVERS

[ipv6]
method=ignore
EOT
        chmod 600 /etc/NetworkManager/system-connections/static-wifi.nmconnection
    else
        cat << EOT > /etc/NetworkManager/system-connections/static-eth.nmconnection
[connection]
id=static-eth
type=ethernet
interface-name=enp0s3
autoconnect=true

[ipv4]
method=manual
address1=$IP_ADDR/$SUBNET_MASK
gateway=$GATEWAY
dns=$DNS_SERVERS

[ipv6]
method=ignore
EOT
        chmod 600 /etc/NetworkManager/system-connections/static-eth.nmconnection
    fi
    echo -e "\${GREEN}Static IPv4 configuration written successfully.\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${GREEN}Using DHCP for network configuration.\${NC}" | tee -a "\$LOGFILE"
fi

# 设置密码
echo "Setting root password..." | tee -a "\$LOGFILE"
passwd
echo "Creating user syaofox..." | tee -a "\$LOGFILE"
useradd -m -g users -G wheel,video syaofox
echo "Setting syaofox password..." | tee -a "\$LOGFILE"
passwd syaofox
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# 配置 NVIDIA
echo "Configuring NVIDIA drivers..." | tee -a "\$LOGFILE"
cat << EOT > /etc/modprobe.d/nvidia.conf
options nvidia_drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOT
sed -i 's/MODULES=()/MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
mkdir -p /etc/pacman.d/hooks
cat << EOT > /etc/pacman.d/hooks/nvidia.hook
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia-open-dkms
Target=linux

[Action]
Description=Updating NVIDIA module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOT
mkinitcpio -P
if [[ \$(cat /sys/module/nvidia_drm/parameters/modeset) == "Y" ]]; then
    echo -e "\${GREEN}NVIDIA DRM configured successfully.\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${RED}Warning: NVIDIA DRM not enabled, may affect desktop environment performance!\${NC}" | tee -a "\$LOGFILE"
fi

# 配置 systemd-boot
echo "Selecting CPU microcode..." | tee -a "\$LOGFILE"
if lscpu | grep -q "Vendor ID.*Intel"; then
    UCODE="intel-ucode"
    UCODE_IMG="/intel-ucode.img"
else
    UCODE="amd-ucode"
    UCODE_IMG="/amd-ucode.img"
fi
echo "Installing systemd-boot and \$UCODE..." | tee -a "\$LOGFILE"
bootctl install
pacman -S --noconfirm "\$UCODE"
mkinitcpio -P
echo "Please get Btrfs root partition UUID (/dev/nvme0n1p2) and edit /boot/loader/entries/arch.conf" | tee -a "\$LOGFILE"
blkid /dev/nvme0n1p2
nano /boot/loader/entries/arch.conf
cat << EOT > /boot/loader/loader.conf
default arch.conf
timeout 4
editor no
EOT
if bootctl status &> /dev/null; then
    echo -e "\${GREEN}systemd-boot configured successfully.\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${RED}Error: systemd-boot installation failed\${NC}" | tee -a "\$LOGFILE"
    exit 1
fi

# 启用 NVIDIA 电源管理
echo "Enabling NVIDIA power management..." | tee -a "\$LOGFILE"
systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
mkinitcpio -P

exit
EOF
    dialog --msgbox "Base system configuration completed." 6 30
    echo -e "${GREEN}Base system configuration completed.${NC}" | tee -a "$LOGFILE"
}

# 最终检查
final_check() {
    dialog --msgbox "Performing final check...\nPlease confirm the following file contents:\n1. /mnt/etc/fstab\n2. /mnt/boot/loader/entries/arch.conf\n3. /mnt/etc/NetworkManager/system-connections/ (if static IPv4 configured)\nClick OK to view..." 12 60
    arch-chroot /mnt cat /etc/fstab
    dialog --msgbox "Please confirm fstab is correct, press OK to continue..." 6 30
    arch-chroot /mnt cat /boot/loader/entries/arch.conf
    dialog --msgbox "Please confirm arch.conf is correct, press OK to continue..." 6 30
    if [[ "$IS_STATIC" == "yes" ]]; then
        if [[ "$IS_WIFI" == "yes" ]]; then
            arch-chroot /mnt cat /etc/NetworkManager/system-connections/static-wifi.nmconnection
        else
            arch-chroot /mnt cat /etc/NetworkManager/system-connections/static-eth.nmconnection
        fi
        dialog --msgbox "Please confirm static IPv4 configuration file is correct, press OK to continue..." 6 30
    fi
    echo -e "${GREEN}Final check completed.${NC}" | tee -a "$LOGFILE"
}

# 主函数
main() {
    check_root
    install_dialog
    check_uefi
    check_network
    check_timesync
    select_disk
    partition_disk
    format_partitions
    setup_btrfs
    create_swapfile
    install_system
    configure_fstab
    configure_system
    final_check
    dialog --msgbox "Base Arch Linux installation completed! Please remove USB boot drive and click OK to reboot.\nYou can run install_dwl.sh to install DWL desktop environment." 10 50
    umount -R /mnt
    reboot
}

main