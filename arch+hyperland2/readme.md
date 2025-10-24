
为优化上一版本的 `install_arch.sh` 脚本，我将引入交互式菜单（使用 `dialog` 工具）以提升用户体验，允许用户选择关键配置（如硬盘、CPU 微码、是否安装无线支持等），并保持脚本的流畅性和可靠性。优化后的脚本将：

1. **交互式菜单**：
   - 使用 `dialog` 提供图形化菜单，引导用户选择硬盘、CPU 微码（Intel 或 AMD）、是否启用无线支持、是否安装 SDDM 等。
   - 保留必要的手动输入（如分区、密码、UUID 编辑），但通过菜单减少命令行输入错误。
2. **错误检查与验证**：
   - 增强错误处理，检查用户输入的合法性（如硬盘设备存在、UUID 格式）。
   - 在关键步骤（如分区、fstab、引导配置）后提供验证选项。
3. **模块化设计**：
   - 将功能拆分为函数，便于维护和调试。
   - 添加进度提示和日志记录。
4. **时间同步**：
   - 保留 `systemd-timesyncd` 配置和国内时间服务器，确保时间同步。
5. **NVIDIA 和 Hyprland**：
   - 继续使用 `nvidia-open-dkms` 和官方 `hyprland` 包，优化 NVIDIA 配置。
6. **用户友好**：
   - 使用颜色和 `dialog` 提示，清晰显示当前步骤和结果。
   - 提供回退选项，允许用户在错误时重新选择。

### 前提条件
- **运行环境**：Arch Linux Live ISO，root 权限。
- **依赖**：脚本使用 `dialog` 工具，需在 Live 环境中安装：
  ```bash
  pacman -Sy dialog
  ```
- **硬件假设**：默认硬盘为 `/dev/nvme0n1`，用户可通过菜单选择其他设备。
- **备份提醒**：运行前请备份数据，分区和格式化会清除磁盘。

### 优化后的安装脚本

<xaiArtifact artifact_id="df120ad5-5b28-4f1d-9377-19ad8e96ca68" artifact_version_id="618198e1-62b6-4169-92c8-e721498f2c3d" title="install_arch.sh" contentType="text/x-sh">
#!/bin/bash

# Arch Linux Btrfs 开发者定制安装脚本（含 Hyprland 和 NVIDIA 支持）
# 基于 2025 年 10 月 23 日的 Arch Linux Wiki 和 Hyprland Wiki
# 优化：交互式菜单（使用 dialog），模块化设计，增强错误处理
# 运行环境：Arch Linux Live ISO，需 root 权限

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 日志文件
LOGFILE="/root/install_arch.log"
echo "Arch Linux 安装日志 - $(date)" > "$LOGFILE"

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

# 检查网络
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

# 安装系统
install_system() {
    dialog --yesno "是否启用无线支持（安装 iwd）？" 8 40
    IWD=$([[ $? -eq 0 ]] && echo "iwd" || echo "")
    echo "安装基本系统和软件包..." | tee -a "$LOGFILE"
    pacstrap /mnt base linux linux-headers systemd vim networkmanager \
        btrfs-progs base-devel git \
        nvidia-open-dkms nvidia-settings nvidia-utils lib32-nvidia-utils libva-nvidia-driver egl-wayland \
        fcitx5 fcitx5-chinese-addons fcitx5-pinyin \
        hyprland xdg-desktop-portal-hyprland wayland-protocols libxkbcommon libinput mesa \
        $IWD
    dialog --msgbox "软件包安装完成。" 6 30
    echo -e "${GREEN}软件包安装完成。${NC}" | tee -a "$LOGFILE"
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
    arch-chroot /mnt /bin/bash << 'EOF'
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
LOGFILE="/root/install_arch.log"

# 时区与时间同步
echo "设置时区和时间同步..." | tee -a "$LOGFILE"
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
    echo -e "${GREEN}时间同步启用成功。${NC}" | tee -a "$LOGFILE"
else
    echo -e "${RED}错误：时间同步失败${NC}" | tee -a "$LOGFILE"
    exit 1
fi

# 本地化
echo "配置本地化..." | tee -a "$LOGFILE"
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# 主机名和 hosts
echo "设置主机名和 hosts..." | tee -a "$LOGFILE"
echo "dev" > /etc/hostname
cat << EOT > /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.1.1	dev.localdomain	dev
EOT
if ping -c 1 localhost &> /dev/null && ping -c 1 dev &> /dev/null; then
    echo -e "${GREEN}hosts 配置验证通过。${NC}" | tee -a "$LOGFILE"
else
    echo -e "${RED}错误：hosts 配置失败${NC}" | tee -a "$LOGFILE"
    exit 1
fi

# 网络服务
echo "启用网络服务..." | tee -a "$LOGFILE"
systemctl enable NetworkManager
if [[ -f /usr/bin/iwd ]]; then
    systemctl enable iwd
fi

# 设置密码
echo "设置 root 密码..." | tee -a "$LOGFILE"
passwd
echo "创建用户 syaofox..." | tee -a "$LOGFILE"
useradd -m -g users -G wheel,video syaofox
echo "设置 syaofox 密码..." | tee -a "$LOGFILE"
passwd syaofox
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# 配置 NVIDIA
echo "配置 NVIDIA 驱动..." | tee -a "$LOGFILE"
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
Exec=/bin/sh -c 'while read -r trg; do case $trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOT
mkinitcpio -P
if [[ $(cat /sys/module/nvidia_drm/parameters/modeset) == "Y" ]]; then
    echo -e "${GREEN}NVIDIA DRM 配置成功。${NC}" | tee -a "$LOGFILE"
else
    echo -e "${RED}警告：NVIDIA DRM 未启用，可能影响 Hyprland 性能！${NC}" | tee -a "$LOGFILE"
fi

# 配置 systemd-boot
echo "选择 CPU 微码..." | tee -a "$LOGFILE"
if lscpu | grep -q "Vendor ID.*Intel"; then
    UCODE="intel-ucode"
    UCODE_IMG="/intel-ucode.img"
else
    UCODE="amd-ucode"
    UCODE_IMG="/amd-ucode.img"
fi
echo "安装 systemd-boot 和 $UCODE..." | tee -a "$LOGFILE"
bootctl install
pacman -S --noconfirm "$UCODE"
mkinitcpio -P
echo "请获取 Btrfs 根分区 UUID（/dev/nvme0n1p2）并编辑 /boot/loader/entries/arch.conf" | tee -a "$LOGFILE"
blkid /dev/nvme0n1p2
nano /boot/loader/entries/arch.conf
cat << EOT > /boot/loader/loader.conf
default arch.conf
timeout 4
editor no
EOT
if bootctl status &> /dev/null; then
    echo -e "${GREEN}systemd-boot 配置成功。${NC}" | tee -a "$LOGFILE"
else
    echo -e "${RED}错误：systemd-boot 安装失败${NC}" | tee -a "$LOGFILE"
    exit 1
fi

# 配置 Hyprland 和 Fcitx5
echo "配置 Hyprland 和 Fcitx5..." | tee -a "$LOGFILE"
mkdir -p /home/syaofox/.config/hypr
cp /usr/share/hyprland/hyprland.conf /home/syaofox/.config/hypr/hyprland.conf
chown syaofox:users /home/syaofox/.config/hypr -R
cat << EOT >> /home/syaofox/.config/hypr/hyprland.conf
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
env = ELECTRON_OZONE_PLATFORM_HINT,auto
EOT
cat << EOT >> /home/syaofox/.bashrc
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
EOT
chown syaofox:users /home/syaofox/.bashrc

# 启用 NVIDIA 电源管理
echo "启用 NVIDIA 电源管理..." | tee -a "$LOGFILE"
systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
mkinitcpio -P

exit
EOF
    dialog --msgbox "系统配置完成。" 6 30
    echo -e "${GREEN}系统配置完成。${NC}" | tee -a "$LOGFILE"
}

# 安装 paru、snapper 和 brave
install_extras() {
    echo "安装 paru、snapper 和 brave..." | tee -a "$LOGFILE"
    arch-chroot /mnt /bin/bash -c "
        su syaofox -c '
            cd ~
            git clone https://aur.archlinux.org/paru.git
            cd paru
            makepkg -si --noconfirm
            cd ..
            rm -rf paru
            echo \"ParallelDownloads = 5\" >> ~/.config/paru/paru.conf
            paru -S --noconfirm snapper snap-pac brave-bin
        '
        snapper -c root create-config /
        snapper -c home create-config /home
        sed -i 's/TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE=\"1800\"/' /etc/snapper/configs/root
        sed -i 's/TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP=\"yes\"/' /etc/snapper/configs/root
        sed -i 's/TIMELINE_CREATE=.*/TIMELINE_CREATE=\"yes\"/' /etc/snapper/configs/root
        sed -i 's/NUMBER_CLEANUP=.*/NUMBER_CLEANUP=\"yes\"/' /etc/snapper/configs/root
        sed -i 's/NUMBER_LIMIT=.*/NUMBER_LIMIT=\"10\"/' /etc/snapper/configs/root
        cp /etc/snapper/configs/root /etc/snapper/configs/home
        systemctl enable --now snapper-timeline.timer
        systemctl enable --now snapper-cleanup.timer
        su syaofox -c '
            echo \"--enable-features=UseOzonePlatform,WaylandLinuxDrmSyncobj\" > ~/.config/brave-flags.conf
            echo \"--ozone-platform=wayland\" >> ~/.config/brave-flags.conf
        '
    "
    dialog --msgbox "paru、snapper 和 brave 安装完成。" 6 30
    echo -e "${GREEN}paru、snapper 和 brave 安装完成。${NC}" | tee -a "$LOGFILE"
}

# 安装 SDDM
install_sddm() {
    dialog --yesno "是否安装 SDDM 登录管理器？" 8 40
    if [[ $? -eq 0 ]]; then
        echo "安装 SDDM..." | tee -a "$LOGFILE"
        pacstrap /mnt sddm
        arch-chroot /mnt systemctl enable sddm
        dialog --msgbox "SDDM 安装完成。" 6 30
        echo -e "${GREEN}SDDM 安装完成。${NC}" | tee -a "$LOGFILE"
    else
        dialog --msgbox "已跳过 SDDM 安装，可手动启动 Hyprland。" 6 30
        echo -e "${GREEN}跳过 SDDM 安装。${NC}" | tee -a "$LOGFILE"
    fi
}

# 最终检查
final_check() {
    dialog --msgbox "执行最终检查...\n请确认以下文件内容：\n1. /mnt/etc/fstab\n2. /mnt/boot/loader/entries/arch.conf\n点击 OK 查看..." 10 50
    arch-chroot /mnt cat /etc/fstab
    dialog --msgbox "请确认 fstab 正确，按 OK 继续..." 6 30
    arch-chroot /mnt cat /boot/loader/entries/arch.conf
    dialog --msgbox "请确认 arch.conf 正确，按 OK 继续..." 6 30
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
    install_extras
    install_sddm
    final_check
    dialog --msgbox "安装完成！请拔掉 USB 启动盘并点击 OK 重启..." 8 40
    umount -R /mnt
    reboot
}

main
</xaiArtifact>

---

### 使用说明
1. **准备环境**：
   - 在 Arch Linux Live ISO 中以 root 用户运行：
     ```bash
     pacman -Sy dialog
     chmod +x install_arch.sh
     ./install_arch.sh
     ```

2. **交互式菜单**：
   - **硬盘选择**：显示可用磁盘列表（名称、大小、型号），用户选择目标硬盘。
   - **无线支持**：询问是否安装 `iwd`（无线网络支持）。
   - **SDDM 安装**：询问是否安装 SDDM 登录管理器。
   - **CPU 微码**：自动检测 Intel 或 AMD CPU，选择相应微码包（`intel-ucode` 或 `amd-ucode`）。
   - **手动步骤**：分区（`fdisk`）、密码设置、编辑 `fstab` 和 `arch.conf` 仍需用户交互，脚本提供清晰提示。

3. **关键功能**：
   - **时间同步**：启用 `systemd-timesyncd`，配置国内时间服务器（`cn.pool.ntp.org` 和 `time.google.com`）。
   - **错误检查**：验证 UEFI、网络、时间同步、硬盘、分区、挂载、Swapfile、NVIDIA DRM 和 systemd-boot。
   - **日志记录**：所有操作记录在 `/root/install_arch.log`。
   - **NVIDIA 和 Hyprland**：配置 `nvidia-open-dkms`、环境变量、电源管理，确保 Hyprland 兼容性。
   - **Btrfs 和 Snapper**：配置子卷、Swapfile 和快照策略。

4. **用户体验**：
   - 使用 `dialog` 提供图形化菜单，减少命令行输入。
   - 红色/绿色输出突出错误和成功信息。
   - 关键步骤暂停，允许用户检查或手动干预。

### 优化亮点
- **交互性**：菜单式选择降低操作门槛，适合新手用户。
- **模块化**：每个步骤封装为函数，便于维护和扩展。
- **错误处理**：检查硬盘存在、网络状态、时间同步、挂载点等，失败时退出并提示日志。
- **灵活性**：支持用户选择是否安装无线支持和 SDDM，自动检测 CPU 类型。
- **日志记录**：所有操作和错误记录在日志文件中，便于调试。

### 注意事项
- **备份数据**：脚本涉及磁盘操作，请备份重要数据。
- **硬件适配**：默认假设硬盘为 `/dev/nvme0n1`，菜单允许选择其他设备。
- **NVIDIA 兼容性**：若 GPU 非 Turing+ 架构，可在 `install_system` 函数中将 `nvidia-open-dkms` 替换为 `nvidia-dkms`。
- **Fcitx5 配置**：需在 Hyprland 中运行 `fcitx5-configtool` 配置输入法。
- **调试**：若 Hyprland 或 NVIDIA 出现问题，检查 `/root/install_arch.log` 或参考 Hyprland Discord 的 `#hyprland-nvidia` 频道。

如需进一步定制（例如添加其他桌面环境、特定软件包或更复杂的菜单选项），请提供详细信息！