#!/bin/bash

# Arch Linux Hyprland 桌面环境安装脚本（支持手动启动或 SDDM，添加 Btrfs Assistant）
# 基于 2025 年 10 月 23 日的 Arch Linux Wiki 和 Hyprland Wiki
# 优化：交互式菜单（dialog），安装 Hyprland、Alacritty、Rofi、桌面工具、Btrfs Assistant
# 运行环境：已安装基础 Arch Linux 系统，需 root 权限

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 日志文件
LOGFILE="/root/install_hyprland.log"
echo "Hyprland 桌面环境安装日志 - $(date)" > "$LOGFILE"

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

# 安装 Hyprland 和相关软件
install_hyprland() {
    dialog --yesno "是否安装桌面管理工具（通知：mako，音量：pamixer+swayosd，截图：grim+slurp）？" 8 50
    DESKTOP_TOOLS=$([[ $? -eq 0 ]] && echo "mako pamixer swayosd grim slurp" || echo "")
    dialog --yesno "是否安装 Alacritty 终端（Super+Enter 快捷键）？" 8 40
    ALACRITTY=$([[ $? -eq 0 ]] && echo "alacritty" || echo "")
    dialog --yesno "是否安装 Rofi 应用启动器（Super+Space 快捷键）？" 8 40
    ROFI=$([[ $? -eq 0 ]] && echo "rofi" || echo "")
    dialog --yesno "是否安装 SDDM 显示管理器？否则将手动启动 Hyprland（登录终端后输入 'Hyprland'）。"
 8 50
    SDDM=$([[ $? -eq 0 ]] && echo "sddm" || echo "")
    dialog --yesno "是否安装 Btrfs Assistant（Snapper 的 GUI 工具）？" 8 40
    BTRFS_ASSISTANT=$([[ $? -eq 0 ]] && echo "btrfs-assistant-bin" || echo "")
    echo "安装 Hyprland 和相关软件包..." | tee -a "$LOGFILE"
    pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland wayland-protocols libxkbcommon libinput mesa \
        fcitx5 fcitx5-chinese-addons fcitx5-pinyin \
        $DESKTOP_TOOLS $ALACRITTY $ROFI $SDDM
    dialog --msgbox "Hyprland 及相关软件包安装完成。" 6 30
    echo -e "${GREEN}Hyprland 及相关软件包安装完成。${NC}" | tee -a "$LOGFILE"
}

# 配置 Hyprland 和相关工具
configure_hyprland() {
    echo "配置 Hyprland、Fcitx5、Alacritty 和 Rofi..." | tee -a "$LOGFILE"
    mkdir -p /home/syaofox/.config/hypr
    cp /usr/share/hyprland/hyprland.conf /home/syaofox/.config/hypr/hyprland.conf
    chown syaofox:users /home/syaofox/.config/hypr -R
    cat << EOT >> /home/syaofox/.config/hypr/hyprland.conf
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
env = ELECTRON_OZONE_PLATFORM_HINT,auto
# 通知、音量、截图
exec-once = mako
exec-once = swayosd-server
bind = , XF86AudioRaiseVolume, exec, pamixer -i 5 && swayosd-client --output-volume raise
bind = , XF86AudioLowerVolume, exec, pamixer -d 5 && swayosd-client --output-volume lower
bind = , XF86AudioMute, exec, pamixer -t && swayosd-client --output-volume mute
bind = \$mainMod, Print, exec, hyprshot -m window -s ~/Pictures
bind = , Print, exec, hyprshot -m output -s ~/Pictures
bind = \$mainMod SHIFT, Print, exec, hyprshot -m region -s ~/Pictures
# 终端 (Alacritty) 和应用启动器 (Rofi)
bind = \$mainMod, Return, exec, alacritty
bind = \$mainMod, space, exec, rofi -show drun
EOT
    if [[ -n "$ALACRITTY" ]]; then
        mkdir -p /home/syaofox/.config/alacritty
        cat << EOT > /home/syaofox/.config/alacritty/alacritty.toml
[font]
size = 12
normal = { family = "monospace", style = "Regular" }

[window]
opacity = 0.9
EOT
        chown syaofox:users /home/syaofox/.config/alacritty -R
    fi
    if [[ -n "$ROFI" ]]; then
        mkdir -p /home/syaofox/.config/rofi
        cat << EOT > /home/syaofox/.config/rofi/config.rasi
configuration {
    modi: "drun,run";
    show-icons: true;
    display-drun: "Apps";
    drun-display-format: "{name}";
}
@theme "/usr/share/rofi/themes/arc-dark.rasi"
EOT
        chown syaofox:users /home/syaofox/.config/rofi -R
    fi
    cat << EOT >> /home/syaofox/.bashrc
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
EOT
    if [[ -z "$SDDM" ]]; then
        echo "echo \"输入 'Hyprland' 启动桌面环境\"" >> /home/syaofox/.bashrc
    fi
    chown syaofox:users /home/syaofox/.bashrc
    if [[ -n "$SDDM" ]]; then
        echo "配置 SDDM..." | tee -a "$LOGFILE"
        systemctl enable sddm
        mkdir -p /etc/sddm.conf.d
        cat << EOT > /etc/sddm.conf.d/hyprland.conf
[Autologin]
User=syaofox
Session=hyprland.desktop
EOT
        echo -e "${GREEN}SDDM 配置完成。${NC}" | tee -a "$LOGFILE"
    fi
    dialog --msgbox "Hyprland 配置完成。\n$( [[ -n "$SDDM" ]] && echo "将通过 SDDM 自动登录 Hyprland。" || echo "登录后输入 'Hyprland' 启动桌面环境。" )\nSuper + Enter: 打开 Alacritty\nSuper + Space: 打开 Rofi" 10 50
    echo -e "${GREEN}Hyprland 配置完成。${NC}" | tee -a "$LOGFILE"
}

# 安装 paru、snapper、brave、hyprshot 和 btrfs-assistant
install_extras() {
    echo "安装 paru、snapper、brave、hyprshot 和 btrfs-assistant..." | tee -a "$LOGFILE"
    su syaofox -c '
        cd ~
        git clone https://aur.archlinux.org/paru.git
        cd paru
        makepkg -si --noconfirm
        cd ..
        rm -rf paru
        echo "ParallelDownloads = 5" >> ~/.config/paru/paru.conf
        paru -S --noconfirm snapper snap-pac brave-bin hyprshot '"$BTRFS_ASSISTANT"'
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
    dialog --msgbox "paru、snapper、brave、hyprshot 和 btrfs-assistant 安装完成。" 6 30
    echo -e "${GREEN}paru、snapper、brave、hyprshot 和 btrfs-assistant 安装完成。${NC}" | tee -a "$LOGFILE"
}

# 主函数
main() {
    check_root
    install_dialog
    check_network
    install_hyprland
    configure_hyprland
    install_extras
    dialog --msgbox "Hyprland 桌面环境安装完成！请重启系统。\n$( [[ -n "$SDDM" ]] && echo "将通过 SDDM 自动登录 Hyprland。" || echo "登录后输入 'Hyprland' 启动桌面环境。" )\nSuper + Enter: 打开 Alacritty\nSuper + Space: 打开 Rofi\n运行 'btrfs-assistant' 管理快照" 14 60
}

main