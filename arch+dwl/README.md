感谢您提供 TonyBTW 的 DWL 安装和配置教程，以及明确要求不使用 Display Manager（即手动启动 DWL）。结合您之前的请求（Btrfs 文件系统、NVIDIA 显卡、Snapper、Btrfs Assistant 等），我将提供两个优化后的脚本，将桌面环境从 Hyprland 替换为 DWL，并确保与您的需求一致：

- **install_base_arch.sh**：安装基础 Arch Linux 系统（Btrfs 子卷、Swapfile、NVIDIA 驱动、systemd-boot、静态 IPv4 等）。
- **install_dwl.sh**：安装 DWL 桌面环境，基于 TonyBTW 的教程，包含 `wlroots`, `foot`, `wmenu`, `slstatus`, `swaybg`, `grim`, `slurp`, 以及快照管理工具（Snapper 和 Btrfs Assistant），支持手动启动（无 SDDM）。

以下是详细的脚本和使用说明，确保模块化、日志记录、错误检查，并与 TonyBTW 的配置一致。

---

### 设计思路
1. **install_base_arch.sh**：
   - 与原脚本一致，安装基础系统，配置 Btrfs 子卷（`@`, `@home`, `@swap`, `@log`, `@cache`）、64GB Swapfile、NVIDIA 驱动（`nvidia-open-dkms`）、systemd-boot。
   - 支持静态 IPv4（交互式配置，Wi-Fi 或有线）。
   - 创建用户 `syaofox`，设置主机名 `dev`，启用时间同步（国内 NTP）。
2. **install_dwl.sh**：
   - 安装 DWL 及其依赖（`wayland`, `wlroots`, `foot`, `wmenu`, `wl-clipboard`, `grim`, `slurp`, `swaybg`, `ttf-jetbrains-mono-nerd`, `firefox`）。
   - 应用 bar 补丁，配置 `slstatus` 状态栏、壁纸脚本、截图脚本。
   - 配置快捷键（`Super + d` 启动 wmenu，`Super + Return` 启动 foot，`Super + q` 关闭窗口等）。
   - 集成 Snapper 和 Btrfs Assistant（GUI 快照管理）。
   - 配置 Fcitx5 输入法，安装 Brave 浏览器。
   - 不使用 SDDM，DWL 通过 `~/start_dwl.sh` 手动启动（`slstatus -s | dwl -s "sh -c 'swaybg -i ~/walls/wall1.png &'"`）。
3. **NVIDIA 优化**：
   - 使用 `nvidia-open-dkms`（R575+ 驱动，2025 年 Wayland 支持成熟）。
   - 设置 `nvidia-drm.modeset=1` 和环境变量（`LIBVA_DRIVER_NAME`, `__GLX_VENDOR_LIBRARY_NAME`, `NVD_BACKEND`）。
   - 解决潜在问题：多显示器刷新率、Electron 应用兼容性。
4. **日志与错误处理**：
   - 日志保存到 `/root/install_base_arch.log` 和 `/root/install_dwl.log`。
   - 使用 `dialog` 提供交互式界面。
5. **快照管理**：
   - Snapper 配置 `root` 和 `home`（`/.snapshots`, `/home/.snapshots`）。
   - Btrfs Assistant 提供 GUI 管理快照。

---

### 脚本 1：安装基础 Arch 系统

<xaiArtifact artifact_id="cab96f07-3da2-417f-83db-d29dfcfa084f" artifact_version_id="1de0f4e5-4e2e-489e-b51a-aa8a47c48811" title="install_base_arch.sh" contentType="text/x-sh">
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
echo "Arch Linux 基础系统安装日志 - $(date)" > "$LOGFILE"

# 错误处理
set -e
trap 'echo -e "${RED}错误：脚本在行 $LINENO 失败，请检查 $LOGFILE！${NC}"' ERR

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请以 root 用户运行此脚本！${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 安装 dialog
install_dialog() {
    echo "安装 dialog 工具..." | tee -a "$LOGFILE"
    pacman -Sy --noconfirm dialog || {
        echo -e "${RED}错误：无法安装 dialog！${NC}" | tee -a "$LOGFILE"
        exit 1
    }
    echo -e "${GREEN}dialog 安装完成。${NC}" | tee -a "$LOGFILE"
}

# 检查 UEFI 模式
check_uefi() {
    echo "检查 UEFI 模式..." | tee -a "$LOGFILE"
    if [[ ! -d /sys/firmware/efi ]]; then
        dialog --msgbox "未检测到 UEFI 模式，请检查 BIOS 设置并重启！" 8 40
        echo -e "${RED}错误：非 UEFI 模式${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    dialog --msgbox "UEFI 模式已确认。" 6 30
    echo -e "${GREEN}UEFI 模式已确认。${NC}" | tee -a "$LOGFILE"
}

# 检查和配置网络（支持静态 IPv4）
check_network() {
    echo "检查网络连通性..." | tee -a "$LOGFILE"
    if ping -c 1 archlinux.org &> /dev/null; then
        dialog --msgbox "网络连接正常。" 6 30
        echo -e "${GREEN}网络连接正常。${NC}" | tee -a "$LOGFILE"
    else
        dialog --yesno "网络未连接！是否配置无线网络？" 8 40
        if [[ $? -eq 0 ]]; then
            systemctl start iwd
            dialog --msgbox "请运行以下命令配置无线网络：\nstation wlan0 scan\nstation wlan0 get-networks\nstation wlan0 connect 'Your-Wifi-SSID'\n完成后点击 OK。" 10 50
            iwctl
            if ! ping -c 1 archlinux.org &> /dev/null; then
                dialog --msgbox "网络仍未连接，请检查后重试！" 8 40
                echo -e "${RED}错误：网络连接失败${NC}" | tee -a "$LOGFILE"
                exit 1
            fi
            dialog --msgbox "无线网络连接成功。" 6 30
            echo -e "${GREEN}无线网络连接成功。${NC}" | tee -a "$LOGFILE"
        else
            dialog --msgbox "网络未连接，脚本无法继续！" 8 40
            echo -e "${RED}错误：网络未连接${NC}" | tee -a "$LOGFILE"
            exit 1
        fi
    fi

    # 询问是否配置静态 IPv4
    dialog --yesno "是否为安装后的系统配置静态 IPv4？" 8 40
    if [[ $? -eq 0 ]]; then
        dialog --yesno "是否为无线网络（Wi-Fi）配置静态 IPv4？否则将配置有线网络。" 8 40
        IS_WIFI=$([[ $? -eq 0 ]] && echo "yes" || echo "no")
        IP_ADDR=$(dialog --inputbox "请输入静态 IPv4 地址（例如 192.168.1.100）" 8 40 2>&1 >/dev/tty)
        SUBNET_MASK=$(dialog --inputbox "请输入子网掩码（例如 255.255.255.0 或 /24）" 8 40 2>&1 >/dev/tty)
        GATEWAY=$(dialog --inputbox "请输入默认网关（例如 192.168.1.1）" 8 40 2>&1 >/dev/tty)
        DNS_SERVERS=$(dialog --inputbox "请输入 DNS 服务器（逗号分隔，例如 8.8.8.8,8.8.4.4）" 8 40 2>&1 >/dev/tty)
        if [[ -z "$IP_ADDR" || -z "$SUBNET_MASK" || -z "$GATEWAY" || -z "$DNS_SERVERS" ]]; then
            dialog --msgbox "未提供完整的静态 IPv4 配置，将使用 DHCP！" 8 40
            echo -e "${RED}警告：静态 IPv4 配置不完整，使用 DHCP${NC}" | tee -a "$LOGFILE"
            IS_STATIC="no"
        else
            IS_STATIC="yes"
            if [[ "$SUBNET_MASK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                SUBNET_MASK=$(echo "$SUBNET_MASK" | awk -F. '{print ($1*256^3 + $2*256^2 + $3*256 + $4)}' | bc | awk '{for(i=0; $1>0; i++) $1/=2; print i}')
            fi
            if [[ "$IS_WIFI" == "yes" ]]; then
                WIFI_SSID=$(dialog --inputbox "请输入 Wi-Fi SSID" 8 40 2>&1 >/dev/tty)
                if [[ -z "$WIFI_SSID" ]]; then
                    dialog --msgbox "未提供 Wi-Fi SSID，将使用 DHCP！" 8 40
                    echo -e "${RED}警告：未提供 Wi-Fi SSID，使用 DHCP${NC}" | tee -a "$LOGFILE"
                    IS_STATIC="no"
                fi
            fi
            echo -e "${GREEN}静态 IPv4 配置：IP=$IP_ADDR/$SUBNET_MASK, 网关=$GATEWAY, DNS=$DNS_SERVERS${NC}" | tee -a "$LOGFILE"
            if [[ "$IS_WIFI" == "yes" ]]; then
                echo "Wi-Fi SSID: $WIFI_SSID" | tee -a "$LOGFILE"
            fi
        fi
    else
        IS_STATIC="no"
        echo -e "${GREEN}将使用 DHCP 配置网络。${NC}" | tee -a "$LOGFILE"
    fi
}

# 检查时间同步
check_timesync() {
    echo "检查 Live 环境时间同步..." | tee -a "$LOGFILE"
    if timedatectl status | grep -q "NTP service: active"; then
        dialog --msgbox "时间同步正常。" 6 30
        echo -e "${GREEN}时间同步正常。${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "NTP 服务未启用，请检查 Live 环境！" 8 40
        echo -e "${RED}错误：NTP 服务未启用${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 选择硬盘
select_disk() {
    echo "扫描可用磁盘..." | tee -a "$LOGFILE"
    DISKS=($(lsblk -d -n -o NAME | grep -E '^(sd|nvme)'))
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        dialog --msgbox "未找到可用磁盘！请检查硬件。" 8 40
        echo -e "${RED}错误：未找到磁盘${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    MENU=()
    for disk in "${DISKS[@]}"; do
        MENU+=("/dev/$disk" "$(lsblk -d -n -o SIZE,MODEL /dev/$disk)")
    done
    DISK=$(dialog --menu "选择主硬盘（警告：将清除数据！）" 15 60 5 "${MENU[@]}" 2>&1 >/dev/tty)
    if [[ -z "$DISK" ]]; then
        dialog --msgbox "未选择硬盘，脚本退出！" 8 40
        echo -e "${RED}错误：未选择硬盘${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    dialog --msgbox "已选择硬盘：$DISK" 6 30
    echo -e "${GREEN}使用硬盘：$DISK${NC}" | tee -a "$LOGFILE"
}

# 分区磁盘
partition_disk() {
    dialog --msgbox "即将启动 fdisk 分区 $DISK。\n建议：\n1. 创建 1G EFI 分区 (${DISK}p1)，类型：EFI System (1)\n2. 创建剩余空间的 Btrfs 分区 (${DISK}p2)，类型：Linux filesystem (20)\n完成后保存并退出（w）。\n点击 OK 启动 fdisk..." 12 50
    fdisk "$DISK"
    if [[ ! -b "${DISK}p1" || ! -b "${DISK}p2" ]]; then
        dialog --msgbox "分区失败，未找到 ${DISK}p1 或 ${DISK}p2！" 8 40
        echo -e "${RED}错误：分区失败${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
    dialog --msgbox "分区完成。" 6 30
    echo -e "${GREEN}分区完成。${NC}" | tee -a "$LOGFILE"
}

# 格式化分区
format_partitions() {
    echo "格式化分区..." | tee -a "$LOGFILE"
    mkfs.fat -F 32 "${DISK}p1"
    mkfs.btrfs -f -O ssd "${DISK}p2"
    dialog --msgbox "分区格式化完成。" 6 30
    echo -e "${GREEN}分区格式化完成。${NC}" | tee -a "$LOGFILE"
}

# 创建并挂载 Btrfs 子卷
setup_btrfs() {
    echo "创建并挂载 Btrfs 子卷..." | tee -a "$LOGFILE"
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
        dialog --msgbox "Btrfs 子卷挂载成功。" 6 30
        echo -e "${GREEN}Btrfs 子卷挂载完成。${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "挂载失败，请检查！" 8 40
        echo -e "${RED}错误：挂载失败${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 创建 Swapfile
create_swapfile() {
    echo "创建 64GB Swapfile..." | tee -a "$LOGFILE"
    chattr +C /mnt/swap
    btrfs filesystem mkswapfile --size 64g --uuid clear /mnt/swap/swapfile
    chmod 600 /mnt/swap/swapfile
    mkswap /mnt/swap/swapfile
    swapon /mnt/swap/swapfile
    if swapon -s | grep -q "/mnt/swap/swapfile"; then
        swapoff /mnt/swap/swapfile
        dialog --msgbox "Swapfile 创建成功。" 6 30
        echo -e "${GREEN}Swapfile 创建完成。${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "Swapfile 创建失败！" 8 40
        echo -e "${RED}错误：Swapfile 创建失败${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 安装基础系统
install_system() {
    dialog --yesno "是否启用无线支持（安装 iwd）？" 8 40
    IWD=$([[ $? -eq 0 ]] && echo "iwd" || echo "")
    echo "安装基础系统和软件包..." | tee -a "$LOGFILE"
    pacstrap /mnt base linux linux-headers systemd vim networkmanager \
        btrfs-progs base-devel git \
        nvidia-open-dkms nvidia-settings nvidia-utils lib32-nvidia-utils libva-nvidia-driver egl-wayland
    dialog --msgbox "基础软件包安装完成。" 6 30
    echo -e "${GREEN}基础软件包安装完成。${NC}" | tee -a "$LOGFILE"
}

# 配置 fstab
configure_fstab() {
    echo "生成 fstab 文件..." | tee -a "$LOGFILE"
    genfstab -U /mnt >> /mnt/etc/fstab
    echo "/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
    dialog --msgbox "请检查 /mnt/etc/fstab，确保 Btrfs 子卷和 Swapfile 配置正确。\n点击 OK 打开 nano..." 10 50
    nano /mnt/etc/fstab
    dialog --msgbox "fstab 配置完成。" 6 30
    echo -e "${GREEN}fstab 配置完成。${NC}" | tee -a "$LOGFILE"
}

# 配置系统（chroot）
configure_system() {
    echo "进入 chroot 环境并配置系统..." | tee -a "$LOGFILE"
    arch-chroot /mnt /bin/bash << EOF
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
LOGFILE="/root/install_base_arch.log"

# 时区与时间同步
echo "设置时区和时间同步..." | tee -a "\$LOGFILE"
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
    echo -e "\${GREEN}时间同步启用成功。\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${RED}错误：时间同步失败\${NC}" | tee -a "\$LOGFILE"
    exit 1
fi

# 本地化
echo "配置本地化..." | tee -a "\$LOGFILE"
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# 主机名和 hosts
echo "设置主机名和 hosts..." | tee -a "\$LOGFILE"
echo "dev" > /etc/hostname
cat << EOT > /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.1.1	dev.localdomain	dev
EOT
if ping -c 1 localhost &> /dev/null && ping -c 1 dev &> /dev/null; then
    echo -e "\${GREEN}hosts 配置验证通过。\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${RED}错误：hosts 配置失败\${NC}" | tee -a "\$LOGFILE"
    exit 1
fi

# 网络服务
echo "启用网络服务..." | tee -a "\$LOGFILE"
systemctl enable NetworkManager
if [[ -f /usr/bin/iwd ]]; then
    systemctl enable iwd
fi

# 配置静态 IPv4
if [[ "$IS_STATIC" == "yes" ]]; then
    echo "配置静态 IPv4..." | tee -a "\$LOGFILE"
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
    echo -e "\${GREEN}静态 IPv4 配置写入完成。\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${GREEN}使用 DHCP 配置网络。\${NC}" | tee -a "\$LOGFILE"
fi

# 设置密码
echo "设置 root 密码..." | tee -a "\$LOGFILE"
passwd
echo "创建用户 syaofox..." | tee -a "\$LOGFILE"
useradd -m -g users -G wheel,video syaofox
echo "设置 syaofox 密码..." | tee -a "\$LOGFILE"
passwd syaofox
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# 配置 NVIDIA
echo "配置 NVIDIA 驱动..." | tee -a "\$LOGFILE"
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
    echo -e "\${GREEN}NVIDIA DRM 配置成功。\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${RED}警告：NVIDIA DRM 未启用，可能影响桌面环境性能！\${NC}" | tee -a "\$LOGFILE"
fi

# 配置 systemd-boot
echo "选择 CPU 微码..." | tee -a "\$LOGFILE"
if lscpu | grep -q "Vendor ID.*Intel"; then
    UCODE="intel-ucode"
    UCODE_IMG="/intel-ucode.img"
else
    UCODE="amd-ucode"
    UCODE_IMG="/amd-ucode.img"
fi
echo "安装 systemd-boot 和 \$UCODE..." | tee -a "\$LOGFILE"
bootctl install
pacman -S --noconfirm "\$UCODE"
mkinitcpio -P
echo "请获取 Btrfs 根分区 UUID（/dev/nvme0n1p2）并编辑 /boot/loader/entries/arch.conf" | tee -a "\$LOGFILE"
blkid /dev/nvme0n1p2
nano /boot/loader/entries/arch.conf
cat << EOT > /boot/loader/loader.conf
default arch.conf
timeout 4
editor no
EOT
if bootctl status &> /dev/null; then
    echo -e "\${GREEN}systemd-boot 配置成功。\${NC}" | tee -a "\$LOGFILE"
else
    echo -e "\${RED}错误：systemd-boot 安装失败\${NC}" | tee -a "\$LOGFILE"
    exit 1
fi

# 启用 NVIDIA 电源管理
echo "启用 NVIDIA 电源管理..." | tee -a "\$LOGFILE"
systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
mkinitcpio -P

exit
EOF
    dialog --msgbox "基础系统配置完成。" 6 30
    echo -e "${GREEN}基础系统配置完成。${NC}" | tee -a "$LOGFILE"
}

# 最终检查
final_check() {
    dialog --msgbox "执行最终检查...\n请确认以下文件内容：\n1. /mnt/etc/fstab\n2. /mnt/boot/loader/entries/arch.conf\n3. /mnt/etc/NetworkManager/system-connections/ (如果配置了静态 IPv4)\n点击 OK 查看..." 12 60
    arch-chroot /mnt cat /etc/fstab
    dialog --msgbox "请确认 fstab 正确，按 OK 继续..." 6 30
    arch-chroot /mnt cat /boot/loader/entries/arch.conf
    dialog --msgbox "请确认 arch.conf 正确，按 OK 继续..." 6 30
    if [[ "$IS_STATIC" == "yes" ]]; then
        if [[ "$IS_WIFI" == "yes" ]]; then
            arch-chroot /mnt cat /etc/NetworkManager/system-connections/static-wifi.nmconnection
        else
            arch-chroot /mnt cat /etc/NetworkManager/system-connections/static-eth.nmconnection
        fi
        dialog --msgbox "请确认静态 IPv4 配置文件正确，按 OK 继续..." 6 30
    fi
    echo -e "${GREEN}最终检查完成。${NC}" | tee -a "$LOGFILE"
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
    dialog --msgbox "基础 Arch Linux 安装完成！请拔掉 USB 启动盘并点击 OK 重启。\n可运行 install_dwl.sh 安装 DWL 桌面环境。" 10 50
    umount -R /mnt
    reboot
}

main
</xaiArtifact>

---

### 脚本 2：安装 DWL 桌面环境

<xaiArtifact artifact_id="3aa001fd-a035-4ca7-b8ba-00f45e6e5bba" artifact_version_id="fe85f8f6-35b0-4b51-b0e1-e66dd1f1ad8d" title="install_dwl.sh" contentType="text/x-sh">
#!/bin/bash

# Arch Linux DWL 桌面环境安装脚本（手动启动，无 Display Manager）
# 基于 2025 年 10 月 23 日的 Arch Linux Wiki 和 TonyBTW DWL 教程
# 优化：交互式菜单（dialog），安装 DWL、foot、wmenu、slstatus、桌面工具
# 运行环境：已安装基础 Arch Linux 系统，需 root 权限

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 日志文件
LOGFILE="/root/install_dwl.log"
echo "DWL 桌面环境安装日志 - $(date)" > "$LOGFILE"

# 错误处理
set -e
trap 'echo -e "${RED}错误：脚本在行 $LINENO 失败，请检查 $LOGFILE！${NC}"' ERR

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请以 root 用户运行此脚本！${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 安装 dialog
install_dialog() {
    echo "安装 dialog 工具..." | tee -a "$LOGFILE"
    pacman -Sy --noconfirm dialog || {
        echo -e "${RED}错误：无法安装 dialog！${NC}" | tee -a "$LOGFILE"
        exit 1
    }
    echo -e "${GREEN}dialog 安装完成。${NC}" | tee -a "$LOGFILE"
}

# 检查网络
check_network() {
    echo "检查网络连通性..." | tee -a "$LOGFILE"
    if ping -c 1 archlinux.org &> /dev/null; then
        dialog --msgbox "网络连接正常。" 6 30
        echo -e "${GREEN}网络连接正常。${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "网络未连接，请配置网络后重试！" 8 40
        echo -e "${RED}错误：网络未连接${NC}" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 安装 DWL 和相关软件
install_dwl() {
    dialog --yesno "是否安装桌面管理工具（截图：grim+slurp，壁纸：swaybg）？" 8 50
    DESKTOP_TOOLS=$([[ $? -eq 0 ]] && echo "grim slurp swaybg" || echo "")
    dialog --yesno "是否安装 foot 终端（Super+Return 快捷键）？" 8 40
    FOOT=$([[ $? -eq 0 ]] && echo "foot" || echo "")
    dialog --yesno "是否安装 wmenu 应用启动器（Super+d 快捷键）？" 8 40
    WMENU=$([[ $? -eq 0 ]] && echo "wmenu" || echo "")
    dialog --yesno "是否安装 Btrfs Assistant（Snapper 的 GUI 工具）？" 8 40
    BTRFS_ASSISTANT=$([[ $? -eq 0 ]] && echo "btrfs-assistant-bin" || echo "")
    echo "安装 DWL 依赖和相关软件包..." | tee -a "$LOGFILE"
    pacman -S --noconfirm wayland wayland-protocols wlroots wl-clipboard \
        fcitx5 fcitx5-chinese-addons fcitx5-pinyin firefox ttf-jetbrains-mono-nerd \
        $DESKTOP_TOOLS $FOOT $WMENU
    dialog --msgbox "DWL 依赖及相关软件包安装完成。" 6 30
    echo -e "${GREEN}DWL 依赖及相关软件包安装完成。${NC}" | tee -a "$LOGFILE"
}

# 编译和配置 DWL
configure_dwl() {
    echo "配置 DWL 和相关工具..." | tee -a "$LOGFILE"
    su syaofox -c '
        cd ~
        git clone https://codeberg.org/dwl/dwl.git
        cd dwl
        wget https://codeberg.org/dwl/community/raw/branch/master/bar.diff -O patches/bar.diff
        patch -i patches/bar.diff
        cat << EOT > config.def.h
/* See LICENSE file for copyright and license details. */
#include <X11/XF86keysym.h>

/* appearance */
static const int sloppyfocus               = 1;  /* focus follows mouse */
static const int bypass_surface_visibility = 0;  /* 1 means idle inhibitors will disable idle tracking even for visible windows */
static const unsigned int borderpx         = 1;  /* border pixel of windows */
static const float bordercolor[]          = {0.5, 0.5, 0.5, 1.0};
static const float focuscolor[]            = {1.0, 0.0, 0.0, 1.0};
static const float urgentcolor[]           = {0.0, 1.0, 0.0, 1.0};
static const char *fonts[]                 = {"JetBrainsMono Nerd Font Mono:style=Bold:size=16"};
static const char *barfont                = "JetBrainsMono Nerd Font Mono:style=Bold:size=16";
/* tagging - tagcount must be no greater than 31 */
static const int tagcount = 9;

/* logging */
static const int log_level = WLR_DEBUG;

/* startup */
static const char *const autostart[] = {
    NULL /* terminate */
};

/* commands */
static const char *termcmd[]  = { "foot", NULL };
static const char *wmenucmd[] = { "wmenu-run", "-f", "JetBrainsMono Nerd Font 16", "-l", "10", NULL };

static const Key keys[] = {
    /* Note that Shift changes certain key codes: c -> C, 2 -> at, etc. */
    /* modifier                  key                 function        argument */
    { MODKEY,                    XKB_KEY_d,          spawn,          {.v = wmenucmd} },
    { MODKEY,                    XKB_KEY_Return,     spawn,          {.v = termcmd} },
    { MODKEY,                    XKB_KEY_q,          killclient,     {0} },
    { MODKEY,                    XKB_KEY_j,          focusstack,     {.i = +1} },
    { MODKEY,                    XKB_KEY_k,          focusstack,     {.i = -1} },
    { MODKEY,                    XKB_KEY_h,          setmfact,       {.f = -0.05} },
    { MODKEY,                    XKB_KEY_l,          setmfact,       {.f = +0.05} },
    { MODKEY,                    XKB_KEY_i,          incnmaster,     {.i = +1} },
    { MODKEY,                    XKB_KEY_p,          incnmaster,     {.i = -1} },
    { MODKEY,                    XKB_KEY_e,          togglefullscreen, {0} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_space,      togglefloating, {0} },
    { MODKEY,                    XKB_KEY_t,          setlayout,      {.v = &layouts[0]} }, /* tile */
    { MODKEY,                    XKB_KEY_f,          setlayout,      {.v = &layouts[1]} }, /* floating */
    { MODKEY,                    XKB_KEY_m,          setlayout,      {.v = &layouts[2]} }, /* monocle */
    { MODKEY,                    XKB_KEY_space,      setlayout,      {0} },
    { MODKEY,                    XKB_KEY_b,          togglebar,      {0} },
    { MODKEY,                    XKB_KEY_Tab,        view,           {0} },
    { MODKEY,                    XKB_KEY_1,          view,           {.ui = 1 << 0} },
    { MODKEY,                    XKB_KEY_2,          view,           {.ui = 1 << 1} },
    { MODKEY,                    XKB_KEY_3,          view,           {.ui = 1 << 2} },
    { MODKEY,                    XKB_KEY_4,          view,           {.ui = 1 << 3} },
    { MODKEY,                    XKB_KEY_5,          view,           {.ui = 1 << 4} },
    { MODKEY,                    XKB_KEY_6,          view,           {.ui = 1 << 5} },
    { MODKEY,                    XKB_KEY_7,          view,           {.ui = 1 << 6} },
    { MODKEY,                    XKB_KEY_8,          view,           {.ui = 1 << 7} },
    { MODKEY,                    XKB_KEY_9,          view,           {.ui = 1 << 8} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_1,          tag,            {.ui = 1 << 0} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_2,          tag,            {.ui = 1 << 1} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_3,          tag,            {.ui = 1 << 2} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_4,          tag,            {.ui = 1 << 3} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_5,          tag,            {.ui = 1 << 4} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_6,          tag,            {.ui = 1 << 5} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_7,          tag,            {.ui = 1 << 6} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_8,          tag,            {.ui = 1 << 7} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_9,          tag,            {.ui = 1 << 8} },
    { MODKEY,                    XKB_KEY_0,          view,           {.ui = ~0} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_parenright, tag,            {.ui = ~0} },
    { MODKEY,                    XKB_KEY_comma,      focusmon,       {.i = -1} },
    { MODKEY,                    XKB_KEY_period,     focusmon,       {.i = +1} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_less,       tagmon,         {.i = -1} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_greater,    tagmon,         {.i = +1} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Q,          quit,           {0} },
    { WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT, XKB_KEY_BackSpace, quit, {1} },
};

static const Button buttons[] = {
    { MODKEY, BTN_LEFT,   movemouse,  {0} },
    { MODKEY, BTN_RIGHT,  resizemouse, {0} },
};

static const MonitorRule monrules[] = {
    /* name       mfact  nmaster scale layout       rotate/reflect                x    y */
    { "eDP-1",    0.55,  1,      1,    &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,   -1,  -1 },
};

static const int repeat_rate = 35;
static const int repeat_delay = 200;

/* layout(s) */
static const Layout layouts[] = {
    /* symbol     arrange function */
    { "[]=",      tile },
    { "><>",      NULL },    /* no layout function means floating behavior */
    { "[M]",      monocle },
};

/* monitors */
static const MonitorRule monrules[] = {
    /* name       mfact nmaster scale layout       rotate/reflect                x    y  */
    { NULL,       0.55, 1,      1,    &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,   -1, -1 },
};

/* keyboard */
static const struct xkb_rule_names xkb_rules = {
    /* can specify fields: rules, model, layout, variant, options */
    /* example:
    .options = "ctrl:nocaps",
    */
    .options = NULL,
};

static const int repeat_rate = 25;
static const int repeat_delay = 600;

/* Trackpad */
static const int tap_to_click = 1;
static const int tap_and_drag = 1;
static const int drag_lock = 1;
static const int natural_scrolling = 0;
static const int disable_while_typing = 1;
static const int left_handed = 0;
static const int middle_button_emulation = 0;
/* You can choose between:
LIBINPUT_CONFIG_SCROLL_NO_SCROLL
LIBINPUT_CONFIG_SCROLL_2FG
LIBINPUT_CONFIG_SCROLL_EDGE
LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN
*/
static const enum libinput_config_scroll_method scroll_method = LIBINPUT_CONFIG_SCROLL_2FG;

/* You can choose between:
LIBINPUT_CONFIG_CLICK_METHOD_NONE
LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS
LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER
*/
static const enum libinput_config_click_method click_method = LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS;

/* You can choose between:
LIBINPUT_CONFIG_SEND_DEFAULT
LIBINPUT_CONFIG_SEND_VERTICAL
LIBINPUT_CONFIG_SEND_HORIZONTAL
*/
static const enum libinput_config_send_events_mode events_mode = LIBINPUT_CONFIG_SEND_DEFAULT;

/* You can choose between:
LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT
LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE
*/
static const enum libinput_config_accel_profile accel_profile = LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
static const double accel_speed = 0.0;

/* You can choose between:
LIBINPUT_CONFIG_TAP_MAP_LRM -- left, right, middle
LIBINPUT_CONFIG_TAP_MAP_LMR -- left, middle, right
*/
static const enum libinput_config_tap_button_map button_map = LIBINPUT_CONFIG_TAP_MAP_LRM;

/* If you want to use the windows key for MODKEY, use: */
#define MODKEY WLR_MODIFIER_LOGO
EOT
        rm -f config.h
        sudo make clean install
    '
    dialog --msgbox "DWL 编译和配置完成。" 6 30
    echo -e "${GREEN}DWL 编译和配置完成。${NC}" | tee -a "$LOGFILE"
}

# 配置 slstatus、壁纸和截图脚本
configure_extras() {
    echo "配置 slstatus、壁纸和截图脚本..." | tee -a "$LOGFILE"
    su syaofox -c '
        cd ~
        git clone https://git.suckless.org/slstatus
        cd slstatus
        sudo make clean install
        mkdir -p ~/walls
        # 假设用户提供壁纸，替换为实际 URL 或留空
        # wget -O ~/walls/wall1.png https://wallhaven.cc/w/example
        cat << EOT > ~/start_dwl.sh
#!/bin/sh
slstatus -s | dwl -s "sh -c 'swaybg -i ~/walls/wall1.png &'"
EOT
        chmod +x ~/start_dwl.sh
        cat << EOT > ~/screenshot.sh
#!/bin/sh
timeout 10 slurp > /tmp/selection.txt 2>/dev/null
if [ \$? -eq 0 ] && [ -s /tmp/selection.txt ]; then
    grim -g "\$(cat /tmp/selection.txt)" - | wl-copy
else
    grim - | wl-copy
fi
rm -f /tmp/selection.txt
EOT
        chmod +x ~/screenshot.sh
    '
    # 添加截图快捷键到 DWL 配置
    su syaofox -c '
        cd ~/dwl
        sed -i "/{ MODKEY, *XKB_KEY_q, *killclient, *{0} }/a \
        \    { MODKEY,                    XKB_KEY_s,          spawn,          {.v = (const char *[]){\"~/screenshot.sh\", NULL}} }," config.def.h
        rm -f config.h
        sudo make clean install
    '
    # 配置 Fcitx5
    cat << EOT >> /home/syaofox/.bashrc
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
echo "输入 './start_dwl.sh' 启动 DWL 桌面环境"
EOT
    chown syaofox:users /home/syaofox/.bashrc
    dialog --msgbox "slstatus、壁纸、截图脚本和 Fcitx5 配置完成。\n登录后输入 './start_dwl.sh' 启动 DWL。\nSuper + Return: 打开 foot\nSuper + d: 打开 wmenu\nSuper + s: 截图" 10 50
    echo -e "${GREEN}slstatus、壁纸、截图脚本和 Fcitx5 配置完成。${NC}" | tee -a "$LOGFILE"
}

# 安装 paru、snapper、brave 和 btrfs-assistant
install_extras() {
    echo "安装 paru、snapper、brave 和 btrfs-assistant..." | tee -a "$LOGFILE"
    su syaofox -c '
        cd ~
        git clone https://aur.archlinux.org/paru.git
        cd paru
        makepkg -si --noconfirm
        cd ..
        rm -rf paru
        echo "ParallelDownloads = 5" >> ~/.config/paru/paru.conf
        paru -S --noconfirm snapper snap-pac brave-bin '"$BTRFS_ASSISTANT"'
    '
    snapper -c root create-config /
    snapper -c home create-config /home
    sed -i 's/TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE="1800"/' /etc/snapper/configs/root
    sed -i 's/TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/root
    sed -i 's/TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' /etc/snapper/configs/root
    sed -i 's/NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/' /etc/snapper/configs/root
    sed -i 's/NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' /etc/snapper/configs/root
    cp /etc/snapper/configs/root /etc/snapper/configs/home
    systemctl enable --now snapper-timeline.timer
    systemctl enable --now snapper-cleanup.timer
    su syaofox -c '
        echo "--enable-features=UseOzonePlatform,WaylandLinuxDrmSyncobj" > ~/.config/brave-flags.conf
        echo "--ozone-platform=wayland" >> ~/.config/brave-flags.conf
    '
    dialog --msgbox "paru、snapper、brave 和 btrfs-assistant 安装完成。" 6 30
    echo -e "${GREEN}paru、snapper、brave 和 btrfs-assistant 安装完成。${NC}" | tee -a "$LOGFILE"
}

# 主函数
main() {
    check_root
    install_dialog
    check_network
    install_dwl
    configure_dwl
    configure_extras
    install_extras
    dialog --msgbox "DWL 桌面环境安装完成！请重启系统。\n登录后输入 './start_dwl.sh' 启动 DWL。\nSuper + Return: 打开 foot\nSuper + d: 打开 wmenu\nSuper + s: 截图\n运行 'btrfs-assistant' 管理快照" 12 60
}

main
</xaiArtifact>

---

### 使用说明

#### 1. 运行基础 Arch 安装脚本
在 Arch Linux Live ISO 环境中：
```bash
pacman -Sy dialog
chmod +x install_base_arch.sh
./install_base_arch.sh
```
- **步骤**：
  - **网络配置**：交互式选择静态 IPv4（输入 IP、子网掩码、网关、DNS、Wi-Fi SSID）或 DHCP。
  - **硬盘选择**：交互式选择磁盘，分区（1G EFI + Btrfs），格式化，挂载子卷（`@`, `@home`, `@swap`, `@log`, `@cache`）。
  - **Swapfile**：创建 64GB Swapfile。
  - **系统安装**：安装 `base`, `linux`, `systemd`, `networkmanager`, `nvidia-open-dkms`, `egl-wayland`。
  - **配置**：时间同步（国内 NTP）、本地化（`en_US.UTF-8`, `zh_CN.UTF-8`）、主机名（`dev`）、用户（`syaofox`）、NVIDIA 驱动、systemd-boot。
  - **最终检查**：验证 `fstab` 和 `arch.conf`。
- **网络（Live ISO）**：
  - **静态 IPv4（有线）**：
    ```bash
    nmcli con add type ethernet ifname enp0s3 con-name "static-eth" \
          ipv4.method manual \
          ipv4.addresses 192.168.1.100/24 \
          ipv4.gateway 192.168.1.1 \
          ipv4.dns "8.8.8.8,8.8.4.4"
    nmcli con up static-eth
    ```
  - **Wi-Fi**：
    ```bash
    systemctl start iwd
    iwctl
    # station wlan0 scan
    # station wlan0 connect "Your-Wifi-SSID"
    ```
    静态 IPv4：
    ```bash
    nmcli con add type wifi ifname wlan0 con-name "static-wifi" ssid "Your-Wifi-SSID" \
          ipv4.method manual \
          ipv4.addresses 192.168.1.100/24 \
          ipv4.gateway 192.168.1.1 \
          ipv4.dns "8.8.8.8,8.8.4.4"
    nmcli con up static-wifi
    ```
- **完成**：重启，登录 `syaofox` 或 `root`。

#### 2. 运行 DWL 安装脚本
在基础 Arch 系统（或 chroot）中：
```bash
sudo pacman -Sy dialog
chmod +x install_dwl.sh
sudo ./install_dwl.sh
```
- **步骤**：
  - **网络检查**：确保网络可用（静态 IPv4 或 DHCP）。
  - **软件安装**：
    - DWL 依赖：`wayland`, `wayland-protocols`, `wlroots`, `wl-clipboard`, `ttf-jetbrains-mono-nerd`, `firefox`。
    - 可选：`foot`（`Super + Return`）、`wmenu`（`Super + d`）、`grim`, `slurp`, `swaybg`（截图和壁纸）。
    - 可选：`btrfs-assistant-bin`（快照 GUI）。
  - **DWL 配置**：
    - 克隆 DWL，应用 bar 补丁（https://codeberg.org/dwl/community）。
    - 配置 `config.def.h`：字体、快捷键（`Super + d`, `Super + Return`, `Super + q` 等）、wmenu 参数。
    - 编译：`sudo make clean install`。
  - **额外配置**：
    - **slstatus**：编译并配置状态栏（默认模块：CPU、内存、时间）。
    - **壁纸**：创建 `~/start_dwl.sh`，使用 `swaybg` 设置壁纸（需手动下载 `~/walls/wall1.png`）。
    - **截图**：创建 `~/screenshot.sh`，绑定 `Super + s`。
    - **Fcitx5**：设置输入法环境变量。
    - **Snapper**：配置 `root` 和 `home` 快照，启用时间线和清理。
    - **Brave**：安装并配置 Wayland 支持。
  - **启动**：登录后运行 `./start_dwl.sh`。

#### 3. 使用 DWL
- **启动**：
  ```bash
  ./start_dwl.sh
  ```
  - 或：`slstatus -s | dwl -s "sh -c 'swaybg -i ~/walls/wall1.png &'"`
- **快捷键**（基于 TonyBTW 和脚本）：
  - `Super + d`：wmenu（应用启动器）。
  - `Super + Return`：foot 终端。
  - `Super + q`：关闭窗口。
  - `Super + s`：截图（区域或全屏，复制到剪贴板）。
  - `Super + j/k`：焦点切换。
  - `Super + h/l`：调整 master 大小。
  - `Super + t/f/m`：切换平铺/浮动/单窗口布局。
  - `Super + b`：切换状态栏。
  - `Super + Shift + q`：退出 DWL。
  - 完整快捷键：参考 TonyBTW 教程表格。
- **输入法**：运行 `fcitx5-configtool` 配置拼音。
- **快照管理**：
  - GUI：`btrfs-assistant`（通过 wmenu 启动：`Super + d` 输入 `btrfs-assistant`）。
  - CLI：`sudo snapper -c root list/create/rollback`。
- **壁纸**：
  - 下载：`wget -O ~/walls/wall1.png <URL>`（如 wallhaven.cc）。
  - 更新：编辑 `~/start_dwl.sh` 替换壁纸路径。
- **网络**：
  - 检查：`nmcli con show --active`。
  - Wi-Fi 密码（若静态 IPv4）：`sudo nmcli con modify static-wifi wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Your-Password"`.

#### 4. 自定义
- **DWL 配置**：编辑 `~/dwl/config.def.h`：
  - 添加快捷键（如 `Super + s` 截图）。
  - 调整字体：`static const char *fonts[] = {"JetBrainsMono Nerd Font Mono:style=Bold:size=14"};`。
  - 重新编译：`cd ~/dwl; rm config.h; sudo make clean install`。
- **slstatus**：编辑 `~/slstatus/config.h` 添加模块（电池、音量等），重新编译：`sudo make clean install`。
- **wmenu**：编辑 `config.def.h` 调整字体或行数：
  ```c
  static const char *wmenucmd[] = { "wmenu-run", "-f", "JetBrainsMono Nerd Font 14", "-l", "15", NULL };
  ```
- **壁纸**：替换 `~/walls/wall1.png` 或修改 `start_dwl.sh`。
- **快照**：
  - 创建：`sudo snapper -c root create --description "Before update"`.
  - 恢复：`sudo snapper -c root rollback 1; nano /boot/loader/entries/arch.conf`（更新 `rootflags=subvol=/.snapshots/1/snapshot`）。
  - GUI：`btrfs-assistant`。

---

### 注意事项
- **备份**：运行 `install_base_arch.sh` 前备份数据（清除磁盘）。
- **NVIDIA**：
  - 若非 Turing+ GPU（2018+），替换 `nvidia-open-dkms` 为 `nvidia-dkms` 或 `nvidia-535xx-dkms`：
    ```bash
    sudo pacman -S nvidia-dkms
    ```
  - 验证：`cat /sys/module/nvidia_drm/parameters/modeset`（应为 Y）。
  - Wayland 问题：若 Electron 应用（如 Brave）闪烁，检查 `~/.config/brave-flags.conf`。
- **Wi-Fi 密码**：若使用静态 IPv4 Wi-Fi，安装后设置：
  ```bash
  sudo nmcli con modify static-wifi wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Your-Password"
  ```
- **DWL 补丁**：
  - Bar 补丁：https://codeberg.org/dwl/community/raw/branch/master/bar.diff。
  - 更多补丁：浏览 https://codeberg.org/dwl/community。
- **快照恢复**：
  - 恢复 `root` 快照需更新 `/boot/loader/entries/arch.conf`：
    ```bash
    blkid /dev/nvme0n1p2  # 获取 UUID
    sudo nano /boot/loader/entries/arch.conf
    ```
    示例：`options root=UUID=<UUID> rw rootflags=subvol=/.snapshots/1/snapshot nvidia-drm.modeset=1`.
- **调试**：
  - 日志：`/root/install_base_arch.log`, `/root/install_dwl.log`。
  - DWL 问题：参考 https://codeberg.org/dwl/dwl/wiki 或 DWL Discord。
  - NVIDIA Wayland：参考 Arch Wiki 或 NVIDIA 论坛。
- **壁纸**：需手动下载壁纸到 `~/walls/wall1.png`（脚本未包含 wget URL）。

---

### 示例操作
1. **启动 DWL**：
   ```bash
   ./start_dwl.sh
   ```
2. **创建快照**：
   ```bash
   sudo snapper -c root create --description "Before DWL config"
   ```
3. **恢复快照**：
   ```bash
   sudo snapper -c root rollback 1
   sudo nano /boot/loader/entries/arch.conf  # 更新 rootflags
   reboot
   ```
4. **截图**：
   - `Super + s`：区域或全屏截图，复制到剪贴板。
5. **启动 Btrfs Assistant**：
   ```bash
   btrfs-assistant
   ```
   或通过 wmenu（`Super + d`）。

---

### 高级定制
- **slstatus 模块**：编辑 `~/slstatus/config.h` 添加 CPU、内存、电池、网络等。
- **DWL 补丁**：如需移除工作区指示框，编辑 `~/dwl/dwl.c`（参考 TonyBTW 自定义版本）。
- **多显示器**：编辑 `config.def.h` 的 `monrules` 调整显示器布局。
- **Fcitx5**：若输入法不生效，检查环境变量或运行 `fcitx5-diagnose`。

如果您需要进一步定制（如特定 DWL 补丁、slstatus 配置、或多显示器支持），请提供详细信息！
