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

# 收集用户信息
collect_user_info() {
    echo "Collecting user information..." | tee -a "$LOGFILE"
    
    # 主机名
    HOSTNAME=$(dialog --inputbox "Enter hostname (default: dev)" 8 40 "dev" 2>&1 >/dev/tty)
    if [[ -z "$HOSTNAME" ]]; then
        HOSTNAME="dev"
    fi
    
    # 用户名
    USERNAME=$(dialog --inputbox "Enter username (default: syaofox)" 8 40 "syaofox" 2>&1 >/dev/tty)
    if [[ -z "$USERNAME" ]]; then
        USERNAME="syaofox"
    fi
    
    # Root 密码
    ROOT_PASSWORD=$(dialog --passwordbox "Enter root password" 8 40 2>&1 >/dev/tty)
    if [[ -z "$ROOT_PASSWORD" ]]; then
        dialog --msgbox "Root password is required!" 8 40
        echo -e "${RED}Error: Root password is required${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    
    # 用户密码
    USER_PASSWORD=$(dialog --passwordbox "Enter user password for $USERNAME" 8 40 2>&1 >/dev/tty)
    if [[ -z "$USER_PASSWORD" ]]; then
        dialog --msgbox "User password is required!" 8 40
        echo -e "${RED}Error: User password is required${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    
    dialog --msgbox "User information collected:\nHostname: $HOSTNAME\nUsername: $USERNAME" 8 40
    echo -e "${GREEN}User information collected: Hostname=$HOSTNAME, Username=$USERNAME${NC}" | tee -a "$LOGFILE"
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
    if ping -c 1 qq.com &> /dev/null; then
        dialog --msgbox "Network connection is normal. Will use DHCP by default." 6 30
        echo -e "${GREEN}Network connection is normal, using DHCP.${NC}" | tee -a "$LOGFILE"
        NETWORK_MODE="dhcp-wired"
        IS_STATIC="no"
        return
    fi
    
    # 网络未连接，提供选择菜单
    NETWORK_CHOICE=$(dialog --menu "Network not connected! Select network configuration:" 12 50 4 \
        "1" "Wired network (DHCP) - Recommended" \
        "2" "Wireless network (DHCP)" \
        "3" "Wired network (Static IP)" \
        "4" "Wireless network (Static IP)" \
        2>&1 >/dev/tty)
    
    case $NETWORK_CHOICE in
        "1")
            NETWORK_MODE="dhcp-wired"
            IS_STATIC="no"
            dialog --msgbox "Please connect Ethernet cable and ensure DHCP is available." 8 40
            ;;
        "2")
            NETWORK_MODE="dhcp-wireless"
            IS_STATIC="no"
            systemctl start iwd
            dialog --msgbox "Please run the following commands to configure wireless network:\nstation wlan0 scan\nstation wlan0 get-networks\nstation wlan0 connect 'Your-Wifi-SSID'\nClick OK when done." 10 50
            iwctl
            ;;
        "3")
            NETWORK_MODE="static-wired"
            IS_STATIC="yes"
            IS_WIFI="no"
            configure_static_ip
            ;;
        "4")
            NETWORK_MODE="static-wireless"
            IS_STATIC="yes"
            IS_WIFI="yes"
            configure_static_ip
            systemctl start iwd
            dialog --msgbox "Please run the following commands to configure wireless network:\nstation wlan0 scan\nstation wlan0 get-networks\nstation wlan0 connect 'Your-Wifi-SSID'\nClick OK when done." 10 50
            iwctl
            ;;
        *)
            dialog --msgbox "No network configuration selected, using DHCP wired as default." 8 40
            NETWORK_MODE="dhcp-wired"
            IS_STATIC="no"
            ;;
    esac
    
    # 验证网络连接
    if ! ping -c 1 qq.com &> /dev/null; then
        dialog --msgbox "Network still not connected, please check and retry!" 8 40
        echo -e "${RED}Error: Network connection failed${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    
    dialog --msgbox "Network connected successfully." 6 30
    echo -e "${GREEN}Network connected successfully using $NETWORK_MODE.${NC}" | tee -a "$LOGFILE"
}

# 配置静态IP
configure_static_ip() {
    IP_ADDR=$(dialog --inputbox "Enter static IPv4 address (e.g. 192.168.1.100)" 8 40 "192.168.1.100" 2>&1 >/dev/tty)
    if [[ -z "$IP_ADDR" ]]; then
        IP_ADDR="192.168.1.100"
    fi
    
    SUBNET_MASK=$(dialog --inputbox "Enter subnet mask (e.g. 255.255.255.0 or /24)" 8 40 "/24" 2>&1 >/dev/tty)
    if [[ -z "$SUBNET_MASK" ]]; then
        SUBNET_MASK="/24"
    fi
    
    GATEWAY=$(dialog --inputbox "Enter default gateway (e.g. 192.168.1.1)" 8 40 "192.168.1.1" 2>&1 >/dev/tty)
    if [[ -z "$GATEWAY" ]]; then
        GATEWAY="192.168.1.1"
    fi
    
    DNS_SERVERS=$(dialog --inputbox "Enter DNS servers (comma separated, e.g. 8.8.8.8,8.8.4.4)" 8 40 "8.8.8.8,8.8.4.4" 2>&1 >/dev/tty)
    if [[ -z "$DNS_SERVERS" ]]; then
        DNS_SERVERS="8.8.8.8,8.8.4.4"
    fi
    
    if [[ "$IS_WIFI" == "yes" ]]; then
        WIFI_SSID=$(dialog --inputbox "Enter Wi-Fi SSID" 8 40 2>&1 >/dev/tty)
        if [[ -z "$WIFI_SSID" ]]; then
            dialog --msgbox "No Wi-Fi SSID provided, switching to DHCP!" 8 40
            echo -e "${RED}Warning: No Wi-Fi SSID provided, using DHCP${NC}" | tee -a "$LOGFILE"
            IS_STATIC="no"
            NETWORK_MODE="dhcp-wireless"
            return
        fi
    fi
    
    # 转换子网掩码格式
    if [[ "$SUBNET_MASK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        SUBNET_MASK=$(echo "$SUBNET_MASK" | awk -F. '{print ($1*256^3 + $2*256^2 + $3*256 + $4)}' | bc | awk '{for(i=0; $1>0; i++) $1/=2; print i}')
    fi
    
    echo -e "${GREEN}Static IPv4 configuration: IP=$IP_ADDR/$SUBNET_MASK, Gateway=$GATEWAY, DNS=$DNS_SERVERS${NC}" | tee -a "$LOGFILE"
    if [[ "$IS_WIFI" == "yes" ]]; then
        echo "Wi-Fi SSID: $WIFI_SSID" | tee -a "$LOGFILE"
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
    DISKS=($(lsblk -d -n -o NAME | grep -E '^(sd|vd|nvme)'))
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        dialog --msgbox "No available disks found! Please check hardware." 8 40
        echo -e "${RED}Error: No disks found${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    
    # 如果只有一个硬盘，直接使用
    if [[ ${#DISKS[@]} -eq 1 ]]; then
        DISK="/dev/${DISKS[0]}"
        dialog --msgbox "Only one disk found: $DISK\nWill use this disk automatically." 8 40
        echo -e "${GREEN}Using single disk: $DISK${NC}" | tee -a "$LOGFILE"
        return
    fi
    
    MENU=()
    for disk in "${DISKS[@]}"; do
        MENU+=("/dev/$disk" "$(lsblk -d -n -o SIZE,MODEL /dev/$disk)")
    done
    DISK=$(dialog --menu "Select main hard disk (WARNING: Data will be erased!)" 15 60 5 "${MENU[@]}" 2>&1 >/dev/tty)
    if [[ -z "$DISK" ]]; then
        # 用户取消选择，使用第一个硬盘作为默认
        DISK="/dev/${DISKS[0]}"
        dialog --msgbox "No disk selected, using first disk as default: $DISK" 8 40
        echo -e "${GREEN}Using default disk: $DISK${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "Selected disk: $DISK" 6 30
        echo -e "${GREEN}Using disk: $DISK${NC}" | tee -a "$LOGFILE"
    fi
}

# 分区磁盘
partition_disk() {
    PARTITION_CHOICE=$(dialog --menu "Select partitioning method for $DISK:" 10 50 2 \
        "1" "Automatic partitioning (Recommended)" \
        "2" "Manual partitioning with fdisk" \
        2>&1 >/dev/tty)
    
    case $PARTITION_CHOICE in
        "1")
            dialog --msgbox "Starting automatic partitioning...\nWill create:\n- 1GB EFI partition\n- Remaining space Btrfs partition" 10 50
            echo "Starting automatic partitioning..." | tee -a "$LOGFILE"
            
            # 清除分区表
            wipefs -a "$DISK"
            
            # 创建分区表
            parted "$DISK" mklabel gpt
            
            # 创建 EFI 分区 (1GB)
            parted "$DISK" mkpart ESP fat32 1MiB 1GiB
            parted "$DISK" set 1 esp on
            
            # 创建 Btrfs 分区 (剩余空间)
            parted "$DISK" mkpart primary btrfs 1GiB 100%
            
            dialog --msgbox "Automatic partitioning completed." 6 30
            echo -e "${GREEN}Automatic partitioning completed.${NC}" | tee -a "$LOGFILE"
            ;;
        "2")
            dialog --msgbox "About to start fdisk partitioning $DISK.\nRecommendations:\n1. Create 1G EFI partition, type: EFI System (1)\n2. Create remaining space Btrfs partition, type: Linux filesystem (20)\nSave and exit when done (w).\nClick OK to start fdisk..." 12 50
            fdisk "$DISK"
            ;;
        *)
            dialog --msgbox "No partitioning method selected, using automatic partitioning as default." 8 40
            echo "Using automatic partitioning as default..." | tee -a "$LOGFILE"
            
            # 清除分区表
            wipefs -a "$DISK"
            
            # 创建分区表
            parted "$DISK" mklabel gpt
            
            # 创建 EFI 分区 (1GB)
            parted "$DISK" mkpart ESP fat32 1MiB 1GiB
            parted "$DISK" set 1 esp on
            
            # 创建 Btrfs 分区 (剩余空间)
            parted "$DISK" mkpart primary btrfs 1GiB 100%
            
            dialog --msgbox "Automatic partitioning completed." 6 30
            echo -e "${GREEN}Automatic partitioning completed.${NC}" | tee -a "$LOGFILE"
            ;;
    esac
    
    # 动态检测分区名称
    sleep 2  # 等待分区设备文件创建
    PARTITIONS=($(lsblk -n -o NAME "$DISK" | grep -E '^[^[:space:]]+[0-9]+$'))
    if [[ ${#PARTITIONS[@]} -lt 2 ]]; then
        dialog --msgbox "Partitioning failed, not enough partitions found!" 8 40
        echo -e "${RED}Error: Partitioning failed - found ${#PARTITIONS[@]} partitions${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    
    # 设置分区变量
    EFI_PARTITION="/dev/${PARTITIONS[0]}"
    BTRFS_PARTITION="/dev/${PARTITIONS[1]}"
    
    dialog --msgbox "Partitions detected:\nEFI: $EFI_PARTITION\nBtrfs: $BTRFS_PARTITION" 8 40
    echo -e "${GREEN}Partitions detected: EFI=$EFI_PARTITION, Btrfs=$BTRFS_PARTITION${NC}" | tee -a "$LOGFILE"
}

# 格式化分区
format_partitions() {
    echo "Formatting partitions..." | tee -a "$LOGFILE"
    mkfs.fat -F 32 "$EFI_PARTITION"
    mkfs.btrfs -f -O ssd "$BTRFS_PARTITION"
    dialog --msgbox "Partition formatting completed." 6 30
    echo -e "${GREEN}Partition formatting completed.${NC}" | tee -a "$LOGFILE"
}

# 创建并挂载 Btrfs 子卷
setup_btrfs() {
    echo "Creating and mounting Btrfs subvolumes..." | tee -a "$LOGFILE"
    mount "$BTRFS_PARTITION" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@swap
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@cache
    umount /mnt
    mkdir -p /mnt/{home,var/log,var/cache,swap,boot}
    mount -o subvol=@,compress=zstd,noatime "$BTRFS_PARTITION" /mnt
    mount -o subvol=@home,compress=zstd,noatime "$BTRFS_PARTITION" /mnt/home
    mount -o subvol=@log,compress=zstd,noatime "$BTRFS_PARTITION" /mnt/var/log
    mount -o subvol=@cache,compress=zstd,noatime "$BTRFS_PARTITION" /mnt/var/cache
    mount -o subvol=@swap "$BTRFS_PARTITION" /mnt/swap
    mount "$EFI_PARTITION" /mnt/boot
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
    
    dialog --msgbox "fstab file has been generated. Please review the contents:" 8 40
    arch-chroot /mnt cat /etc/fstab
    dialog --yesno "Is the fstab configuration correct?" 8 40
    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Please check the fstab file manually after installation!" 8 40
        echo -e "${RED}Warning: fstab configuration needs manual review${NC}" | tee -a "$LOGFILE"
    fi
    
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
echo "$HOSTNAME" > /etc/hostname
cat << EOT > /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.1.1	$HOSTNAME.localdomain	$HOSTNAME
EOT
if ping -c 1 localhost &> /dev/null && ping -c 1 $HOSTNAME &> /dev/null; then
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
echo "root:$ROOT_PASSWORD" | chpasswd
echo "Creating user $USERNAME..." | tee -a "\$LOGFILE"
useradd -m -g users -G wheel,video $USERNAME
echo "Setting $USERNAME password..." | tee -a "\$LOGFILE"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
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

# 自动获取 Btrfs 根分区 UUID
BTRFS_UUID=\$(blkid -s UUID -o value $BTRFS_PARTITION)
echo "Btrfs root partition UUID: \$BTRFS_UUID" | tee -a "\$LOGFILE"

# 自动生成 arch.conf
cat << EOT > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  \$UCODE_IMG
initrd  /initramfs-linux.img
options root=UUID=\$BTRFS_UUID rw rootflags=subvol=@ quiet splash
EOT

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
    collect_user_info
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