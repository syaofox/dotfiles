#!/bin/bash

# Arch Linux DWL 桌面环境安装脚本（基于 Tony Banters 仓库，手动启动）
# 基于 2025 年 10 月 23 日的 Arch Linux Wiki 和 TonyBTW DWL 教程
# 优化：交互式菜单（dialog），安装 DWL（Tony Banters）、slstatus（Tony Banters）、foot、wmenu、桌面工具
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

# 编译和配置 DWL（Tony Banters 仓库）
configure_dwl() {
    echo "配置 DWL（Tony Banters 仓库）..." | tee -a "$LOGFILE"
    su syaofox -c '
        cd ~
        git clone https://github.com/tonybanters/dwl.git
        cd dwl
        # 使用 Tony Banters 的预配置（包含 bar 补丁和自定义工作区样式）
        rm -f config.h
        sudo make clean install
    '
    dialog --msgbox "DWL 编译和配置完成。" 6 30
    echo -e "${GREEN}DWL 编译和配置完成。${NC}" | tee -a "$LOGFILE"
}

# 配置 slstatus（Tony Banters 仓库）、壁纸和截图脚本
configure_extras() {
    echo "配置 slstatus（Tony Banters 仓库）、壁纸和截图脚本..." | tee -a "$LOGFILE"
    su syaofox -c '
        cd ~
        git clone https://github.com/tonybanters/slstatus.git
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
    # 添加截图快捷键到 DWL 配置（确保不覆盖 Tony Banters 的 config.h）
    su syaofox -c '
        cd ~/dwl
        if ! grep -q "XKB_KEY_s" config.def.h; then
            sed -i "/{ MODKEY, *XKB_KEY_q, *killclient, *{0} }/a \
            \    { MODKEY,                    XKB_KEY_s,          spawn,          {.v = (const char *[]){\"~/screenshot.sh\", NULL}} }," config.def.h
            rm -f config.h
            sudo make clean install
        fi
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