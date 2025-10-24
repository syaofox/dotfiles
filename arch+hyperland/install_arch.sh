#!/bin/bash

# Arch Linux Btrfs 开发者定制安装脚本（含 Hyprland 和 NVIDIA 支持）
# 基于 2025 年 10 月 23 日的 Arch Linux Wiki 和 Hyprland Wiki
# 运行环境：Arch Linux Live ISO，需 root 权限
# 定制：Btrfs 文件系统，systemd-boot，Hyprland，NVIDIA，Fcitx5，paru，snapper

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 错误处理
set -e
trap 'echo -e "${RED}错误：脚本在行 $LINENO 失败，请检查！${NC}"' ERR

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请以 root 用户运行此脚本！${NC}"
    exit 1
fi

# 检查 UEFI 模式
echo "检查 UEFI 模式..."
if [[ ! -d /sys/firmware/efi ]]; then
    echo -e "${RED}错误：未检测到 UEFI 模式，请检查 BIOS 设置并重启！${NC}"
    exit 1
fi
echo -e "${GREEN}UEFI 模式已确认。${NC}"

# 检查网络连通性
echo "检查网络连通性..."
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo -e "${RED}警告：网络未连接！${NC}"
    echo "尝试配置无线网络（如果适用）..."
    systemctl start iwd
    echo "运行 'iwctl' 配置无线网络："
    echo "  station wlan0 scan"
    echo "  station wlan0 get-networks"
    echo "  station wlan0 connect 'Your-Wifi-SSID'"
    echo "完成后按 Enter 继续..."
    read
    if ! ping -c 1 archlinux.org &> /dev/null; then
        echo -e "${RED}错误：网络仍未连接，请检查后重试！${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}网络连接正常。${NC}"

# 检查时间同步
echo "检查 Live 环境时间同步..."
if ! timedatectl status | grep -q "NTP service: active"; then
    echo -e "${RED}错误：NTP 服务未启用，请检查 Live 环境！${NC}"
    exit 1
fi
echo -e "${GREEN}时间同步正常。${NC}"

# 用户输入：确认主硬盘
echo "请输入主硬盘设备（默认 /dev/nvme0n1，输入 sda 或其他如适用）："
read DISK
DISK=${DISK:-/dev/nvme0n1}
if [[ ! -b "$DISK" ]]; then
    echo -e "${RED}错误：设备 $DISK 不存在！${NC}"
    exit 1
fi
echo -e "${GREEN}使用主硬盘：$DISK${NC}"

# 分区磁盘
echo "启动 fdisk 分区 $DISK..."
echo "建议："
echo "1. 创建 1G EFI 分区 ($DISK"p1)，类型：EFI System (1)"
echo "2. 创建剩余空间的 Btrfs 分区 ($DISK"p2)，类型：Linux filesystem (20)"
echo "完成后保存并退出（w）。按 Enter 启动 fdisk..."
read
fdisk "$DISK"
echo -e "${GREEN}分区完成。${NC}"

# 格式化分区
echo "格式化分区..."
mkfs.fat -F 32 "${DISK}p1"
mkfs.btrfs -f -O ssd "${DISK}p2"
echo -e "${GREEN}分区格式化完成。${NC}"

# 创建并挂载 Btrfs 子卷
echo "创建并挂载 Btrfs 子卷..."
mount "${DISK}p2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@swap
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
umount /mnt

# 挂载子卷
mkdir -p /mnt/{home,var/log,var/cache,swap,boot}
mount -o subvol=@,compress=zstd,noatime "${DISK}p2" /mnt
mount -o subvol=@home,compress=zstd,noatime "${DISK}p2" /mnt/home
mount -o subvol=@log,compress=zstd,noatime "${DISK}p2" /mnt/var/log
mount -o subvol=@cache,compress=zstd,noatime "${DISK}p2" /mnt/var/cache
mount -o subvol=@swap "${DISK}p2" /mnt/swap
mount "${DISK}p1" /mnt/boot
echo -e "${GREEN}Btrfs 子卷挂载完成。${NC}"

# 创建 64GB Swapfile
echo "创建 64GB Swapfile..."
chattr +C /mnt/swap
btrfs filesystem mkswapfile --size 64g --uuid clear /mnt/swap/swapfile
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
swapon /mnt/swap/swapfile
swapon -s
swapoff /mnt/swap/swapfile
echo -e "${GREEN}Swapfile 创建完成。${NC}"

# 安装基本系统和定制包
echo "安装基本系统和软件包..."
pacstrap /mnt base linux linux-headers systemd vim networkmanager \
    btrfs-progs base-devel git \
    nvidia-open-dkms nvidia-settings nvidia-utils lib32-nvidia-utils libva-nvidia-driver egl-wayland \
    fcitx5 fcitx5-chinese-addons fcitx5-pinyin \
    hyprland xdg-desktop-portal-hyprland wayland-protocols libxkbcommon libinput mesa \
    iwd
echo -e "${GREEN}软件包安装完成。${NC}"

# 生成 fstab
echo "生成 fstab 文件..."
genfstab -U /mnt >> /mnt/etc/fstab
echo "/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
echo "请检查 /mnt/etc/fstab，确保 Btrfs 子卷和 Swapfile 配置正确。按 Enter 打开 nano..."
read
nano /mnt/etc/fstab
echo -e "${GREEN}fstab 配置完成。${NC}"

# 进入 chroot 环境
echo "进入 chroot 环境..."
arch-chroot /mnt /bin/bash << 'EOF'

# 设置时区
echo "设置时区..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc

# 启用时间同步
echo "启用 systemd-timesyncd..."
systemctl enable --now systemd-timesyncd
echo "[Time]" > /etc/systemd/timesyncd.conf
echo "NTP=cn.pool.ntp.org time.google.com" >> /etc/systemd/timesyncd.conf
echo "FallbackNTP=pool.ntp.org" >> /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd
if timedatectl status | grep -q "System clock synchronized: yes"; then
    echo -e "${GREEN}时间同步启用成功。${NC}"
else
    echo -e "${RED}错误：时间同步失败，请检查！${NC}"
    exit 1
fi

# 本地化
echo "配置本地化..."
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# 设置主机名和 hosts
echo "设置主机名和 hosts..."
echo "dev" > /etc/hostname
cat << EOT > /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.1.1	dev.localdomain	dev
EOT
if ping -c 1 localhost &> /dev/null && ping -c 1 dev &> /dev/null; then
    echo -e "${GREEN}hosts 配置验证通过。${NC}"
else
    echo -e "${RED}错误：hosts 配置失败，请检查！${NC}"
    exit 1
fi

# 启用网络服务
echo "启用 NetworkManager..."
systemctl enable NetworkManager
systemctl enable iwd

# 设置 root 和用户密码
echo "设置 root 密码..."
passwd
echo "创建用户 syaofox..."
useradd -m -g users -G wheel,video syaofox
echo "设置 syaofox 密码..."
passwd syaofox
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# 配置 NVIDIA
echo "配置 NVIDIA 驱动..."
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
    echo -e "${GREEN}NVIDIA DRM 配置成功。${NC}"
else
    echo -e "${RED}警告：NVIDIA DRM 未启用，可能影响 Hyprland 性能！${NC}"
fi

# 配置 systemd-boot
echo "安装 systemd-boot..."
bootctl install
pacman -S --noconfirm intel-ucode # 替换为 amd-ucode 如果适用
mkinitcpio -P
echo "请获取 Btrfs 根分区 UUID（运行 'blkid /dev/nvme0n1p2'）并编辑 /boot/loader/entries/arch.conf"
echo "按 Enter 打开 nano..."
read
blkid /dev/nvme0n1p2
nano /boot/loader/entries/arch.conf
cat << EOT > /boot/loader/loader.conf
default arch.conf
timeout 4
editor no
EOT
if bootctl status &> /dev/null; then
    echo -e "${GREEN}systemd-boot 配置成功。${NC}"
else
    echo -e "${RED}错误：systemd-boot 安装失败，请检查！${NC}"
    exit 1
fi

# 配置 Hyprland 和 Fcitx5
echo "配置 Hyprland 和 Fcitx5..."
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
echo "启用 NVIDIA 电源管理..."
systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
mkinitcpio -P

# 退出 chroot
exit
EOF

# 安装 paru
echo "安装 paru AUR 助手..."
arch-chroot /mnt /bin/bash -c "
    su syaofox -c '
        cd ~
        git clone https://aur.archlinux.org/paru.git
        cd paru
        makepkg -si --noconfirm
        cd ..
        rm -rf paru
        echo \"ParallelDownloads = 5\" >> ~/.config/paru/paru.conf
    '
"
echo -e "${GREEN}paru 安装完成。${NC}"

# 安装 snapper 和 brave
echo "安装 snapper 和 brave..."
arch-chroot /mnt /bin/bash -c "
    su syaofox -c 'paru -S --noconfirm snapper snap-pac brave-bin'
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
"
echo -e "${GREEN}snapper 和 brave 安装完成。${NC}"

# 优化 Brave
echo "优化 Brave..."
arch-chroot /mnt /bin/bash -c "
    su syaofox -c '
        echo \"--enable-features=UseOzonePlatform,WaylandLinuxDrmSyncobj\" > ~/.config/brave-flags.conf
        echo \"--ozone-platform=wayland\" >> ~/.config/brave-flags.conf
    '
"
echo -e "${GREEN}Brave 优化完成。${NC}"

# 安装 SDDM
echo "安装 SDDM..."
pacstrap /mnt sddm
arch-chroot /mnt systemctl enable sddm
echo -e "${GREEN}SDDM 安装完成。${NC}"

# 最终检查
echo "执行最终检查..."
arch-chroot /mnt cat /etc/fstab
arch-chroot /mnt cat /boot/loader/entries/arch.conf
echo -e "${GREEN}请确认 fstab 和 arch.conf 配置正确。按 Enter 继续...${NC}"
read

# 卸载并重启
echo "卸载分区并准备重启..."
umount -R /mnt
echo -e "${GREEN}安装完成！请拔掉 USB 启动盘并按 Enter 重启...${NC}"
read
reboot