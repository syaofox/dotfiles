感谢您提供 Tony Banters 的 DWL 和 slstatus 仓库（https://github.com/tonybanters/dwl 和 https://github.com/tonybanters/slstatus）。结合您之前的请求（Arch Linux、Btrfs、NVIDIA 显卡、Snapper、Btrfs Assistant、手动启动 DWL 无 Display Manager），我将更新 `install_dwl.sh` 脚本，使用 Tony Banters 的预配置 DWL 和 slstatus 仓库，并确保与现有系统（Btrfs 子卷、NVIDIA 驱动、静态 IPv4 等）无缝集成。

### 更新说明
- **DWL 仓库**：使用 https://github.com/tonybanters/dwl（包含 bar 补丁和自定义工作区样式：青色数字表示占用，紫色下划线表示活跃，白色表示空闲）。
- **slstatus 仓库**：使用 https://github.com/tonybanters/slstatus（支持颜色和下划线，与 DWL bar 匹配）。
- **保留功能**：
  - Btrfs 子卷（`@`, `@home`, `@swap`, `@log`, `@cache`），64GB Swapfile。
  - Snapper（`root` 和 `home` 配置），Btrfs Assistant（GUI 快照管理）。
  - NVIDIA 驱动（`nvidia-open-dkms`，R575+，Wayland 优化）。
  - 手动启动 DWL（`~/start_dwl.sh`），无 SDDM。
  - 快捷键：`Super + d`（wmenu）、`Super + Return`（foot）、`Super + q`（关闭窗口）、`Super + s`（截图）。
  - Fcitx5 输入法，Brave 浏览器，静态 IPv4（可选）。
- **优化**：
  - 使用 Tony Banters 的 DWL 配置（无需手动补丁）。
  - 配置 slstatus 显示 CPU、内存、时间等（参考 TonyBTW 教程）。
  - 壁纸脚本（`swaybg`）和截图脚本（`grim + slurp`）。
  - 交互式安装（`dialog`），日志记录，错误检查。
- **假设**：
  - 基础系统已通过 `install_base_arch.sh` 安装（参考前文）。
  - 壁纸需手动下载到 `~/walls/wall1.png`（如 wallhaven.cc）。
  - 若需要额外 slstatus 模块（电池、音量等），可后续手动配置。

以下是更新后的 `install_dwl.sh` 脚本，替换 DWL 和 slstatus 仓库为 Tony Banters 的版本，并确保与现有配置兼容。

---

### 脚本：安装 DWL 桌面环境（基于 Tony Banters 仓库）

<xaiArtifact artifact_id="3aa001fd-a035-4ca7-b8ba-00f45e6e5bba" artifact_version_id="06bcf8cc-b254-42e0-9840-1758b00136d5" title="install_dwl.sh" contentType="text/x-sh">
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
</xaiArtifact>

---

### 变更说明
1. **DWL 仓库**：
   - 替换 `https://codeberg.org/dwl/dwl.git` 为 `https://github.com/tonybanters/dwl.git`。
   - Tony Banters 的仓库已包含 bar 补丁和工作区样式（青色占用、紫色活跃、白色空闲），无需手动应用 `bar.diff` 或修改 `dwl.c`。
2. **slstatus 仓库**：
   - 替换 `https://git.suckless.org/slstatus` 为 `https://github.com/tonybanters/slstatus.git`。
   - 默认包含颜色和下划线支持，与 DWL bar 匹配。
3. **截图快捷键**：
   - 检查 `config.def.h` 是否已有 `Super + s`，若无则添加（避免覆盖 Tony Banters 的配置）。
4. **壁纸**：
   - 脚本创建 `~/start_dwl.sh`，使用 `swaybg` 设置 `~/walls/wall1.png`。
   - 用户需手动下载壁纸：
     ```bash
     wget -O ~/walls/wall1.png <URL>  # 示例：https://wallhaven.cc/w/example
     ```
5. **其他**：
   - 保留 `install_base_arch.sh`（ID: `cab96f07-3da2-417f-83db-d29dfcfa084f`）配置，确保 Btrfs、NVIDIA、静态 IPv4 等功能。
   - 保持交互式安装（`dialog`）、日志（`/root/install_dwl.log`）、错误处理。
   - Snapper 和 Btrfs Assistant 提供快照管理（GUI 和 CLI）。

---

### 使用说明

#### 1. 运行基础 Arch 安装脚本
- **前提**：已在 Arch Linux Live ISO 环境中运行 `install_base_arch.sh`（参考前文）。
- **执行**：
  ```bash
  pacman -Sy dialog
  chmod +x install_base_arch.sh
  ./install_base_arch.sh
  ```
- **功能**：
  - 配置 Btrfs 子卷、64GB Swapfile、NVIDIA 驱动（`nvidia-open-dkms`）、systemd-boot。
  - 支持静态 IPv4（Wi-Fi 或有线）或 DHCP。
  - 创建用户 `syaofox`，主机名 `dev`。
- **网络（Live ISO）**：
  - 静态 IPv4（有线）：
    ```bash
    nmcli con add type ethernet ifname enp0s3 con-name "static-eth" \
          ipv4.method manual \
          ipv4.addresses 192.168.1.100/24 \
          ipv4.gateway 192.168.1.1 \
          ipv4.dns "8.8.8.8,8.8.4.4"
    nmcli con up static-eth
    ```
  - Wi-Fi：
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
- **完成**：重启，登录 `syaofox`。

#### 2. 运行 DWL 安装脚本
- **执行**：
  ```bash
  sudo pacman -Sy dialog
  chmod +x install_dwl.sh
  sudo ./install_dwl.sh
  ```
- **功能**：
  - 安装 DWL 依赖：`wayland`, `wlroots`, `foot`, `wmenu`, `wl-clipboard`, `grim`, `slurp`, `swaybg`, `firefox`, `ttf-jetbrains-mono-nerd`。
  - 克隆 Tony Banters 的 DWL 和 slstatus 仓库，编译安装。
  - 配置壁纸（`~/start_dwl.sh`）、截图（`~/screenshot.sh`）、Fcitx5。
  - 安装 `paru`, `snapper`, `snap-pac`, `brave-bin`, `btrfs-assistant-bin`（可选）。
  - 设置 Snapper（`root` 和 `home` 快照，时间线和清理）。
  - 添加 Brave Wayland 支持。

#### 3. 使用 DWL
- **启动**：
  ```bash
  ./start_dwl.sh
  ```
  或：
  ```bash
  slstatus -s | dwl -s "sh -c 'swaybg -i ~/walls/wall1.png &'"
  ```
- **快捷键**（基于 Tony Banters DWL 配置）：
  - `Super + d`：wmenu（应用启动器）。
  - `Super + Return`：foot 终端。
  - `Super + q`：关闭窗口。
  - `Super + s`：截图（区域或全屏，复制到剪贴板）。
  - `Super + j/k`：焦点切换（下/上窗口）。
  - `Super + h/l`：调整 master 大小。
  - `Super + t/f/m`：切换平铺/浮动/单窗口布局。
  - `Super + b`：切换状态栏。
  - `Super + Shift + q`：退出 DWL。
  - 完整快捷键：参考 TonyBTW 教程表格（前文）。
- **输入法**：
  - 配置：`fcitx5-configtool`（添加拼音）。
  - 若不生效：`fcitx5-diagnose`。
- **快照管理**：
  - GUI：`btrfs-assistant`（通过 wmenu：`Super + d` 输入 `btrfs-assistant`）。
  - CLI：
    ```bash
    sudo snapper -c root list
    sudo snapper -c root create --description "Before update"
    sudo snapper -c root rollback 1
    ```
- **壁纸**：
  - 下载：
    ```bash
    wget -O ~/walls/wall1.png <URL>  # 示例：https://wallhaven.cc/w/example
    ```
  - 更新：编辑 `~/start_dwl.sh` 替换壁纸路径。
- **网络**：
  - 检查：`nmcli con show --active`。
  - Wi-Fi 密码（若静态 IPv4）：
    ```bash
    sudo nmcli con modify static-wifi wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Your-Password"
    ```

#### 4. 快照管理（Btrfs Assistant）
- **启动**：
  ```bash
  btrfs-assistant
  ```
  或通过 wmenu（`Super + d`）。
- **功能**：
  - 查看 `/.snapshots` 和 `/home/.snapshots` 的快照。
  - 创建：点击 “Create Snapshot”，选择 `root` 或 `home`。
  - 比较：选择两个快照，查看差异。
  - 恢复：
    - 选择快照，点击 “Restore”。
    - 更新 `/boot/loader/entries/arch.conf`：
      ```bash
      sudo nano /boot/loader/entries/arch.conf
      ```
      示例：
      ```
      options root=UUID=<Btrfs-UUID> rw rootflags=subvol=/.snapshots/1/snapshot nvidia-drm.modeset=1
      ```
      获取 UUID：
      ```bash
      blkid /dev/nvme0n1p2
      ```
  - 删除：选择快照，点击 “Delete”。
- **CLI 验证**：
  ```bash
  sudo snapper -c root list
  sudo snapper -c root status 0..1
  ```

---

### 注意事项
- **备份**：运行 `install_base_arch.sh` 前备份数据（清除磁盘）。
- **NVIDIA**：
  - 验证：`cat /sys/module/nvidia_drm/parameters/modeset`（应为 Y）。
  - 若旧 GPU（非 Turing+），替换为 `nvidia-dkms` 或 `nvidia-535xx-dkms`：
    ```bash
    sudo pacman -S nvidia-dkms
    mkinitcpio -P
    ```
  - Electron 应用（如 Brave）闪烁：
    ```bash
    cat ~/.config/brave-flags.conf
    # 确保包含 --ozone-platform=wayland
    ```
- **Wi-Fi 密码**：
  - 若静态 IPv4 Wi-Fi：
    ```bash
    sudo nmcli con modify static-wifi wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Your-Password"
    ```
- **DWL 自定义**：
  - 编辑 `~/dwl/config.def.h`（Tony Banters 版本已优化）。
  - 重新编译：`cd ~/dwl; rm config.h; sudo make clean install`。
- **slstatus 自定义**：
  - 编辑 `~/slstatus/config.h` 添加模块（电池、音量等）。
  - 编译：`cd ~/slstatus; sudo make clean install`。
- **壁纸**：
  - 脚本未包含壁纸下载，需手动：
    ```bash
    wget -O ~/walls/wall1.png <URL>
    ```
- **快照恢复**：
  - 恢复 `root` 快照后更新 `systemd-boot`：
    ```bash
    sudo nano /boot/loader/entries/arch.conf
    ```
  - 若失败，使用 Live ISO 修复：
    ```bash
    mount -o subvol=@ /dev/nvme0n1p2 /mnt
    arch-chroot /mnt
    nano /boot/loader/entries/arch.conf
    ```
- **调试**：
  - 日志：`/root/install_base_arch.log`, `/root/install_dwl.log`。
  - DWL 问题：参考 https://github.com/tonybanters/dwl 或 DWL Discord。
  - NVIDIA Wayland：参考 Arch Wiki 或 NVIDIA 论坛。

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
   或使用 Btrfs Assistant（`Super + d` 输入 `btrfs-assistant`）。
3. **恢复快照**：
   ```bash
   sudo snapper -c root rollback 1
   sudo nano /boot/loader/entries/arch.conf  # 更新 rootflags
   reboot
   ```
4. **截图**：
   - `Super + s`：区域或全屏截图，复制到剪贴板。
5. **输入法**：
   ```bash
   fcitx5-configtool  # 配置拼音
   ```

---

### 高级定制
- **slstatus 模块**：
  - 编辑 `~/slstatus/config.h`，添加电池、网络、音量等：
    ```c
    static const struct arg args[] = {
        { cpu_perc, "CPU: %s%% ", NULL },
        { ram_perc, "RAM: %s%% ", NULL },
        { datetime, "%s", "%F %T" },
    };
    ```
  - 编译：`cd ~/slstatus; sudo make clean install`.
- **DWL 工作区样式**：
  - Tony Banters 的 DWL 已包含自定义样式（青色/紫色/白色）。
  - 调整：编辑 `~/dwl/dwl.c` 或 `config.def.h`，重新编译。
- **多显示器**：
  - 编辑 `~/dwl/config.def.h` 的 `monrules`：
    ```c
    static const MonitorRule monrules[] = {
        { "eDP-1", 0.55, 1, 1, &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL, -1, -1 },
        { "HDMI-A-1", 0.55, 1, 1, &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL, -1, -1 },
    };
    ```
  - 编译：`cd ~/dwl; rm config.h; sudo make clean install`.

如果您需要进一步调整（如特定 slstatus 模块、DWL 补丁、或多显示器配置），请提供详细信息！