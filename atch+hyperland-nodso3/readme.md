
要在 Arch Linux 安装脚本运行前配置网络为手动 IPv4（即静态 IP），您需要在 Arch Linux Live ISO 环境中手动设置网络接口的 IP 地址、子网掩码、网关和 DNS 服务器。由于脚本中使用了 **NetworkManager** 管理网络，我将提供以下步骤：

1. **在 Live ISO 中手动配置静态 IPv4**：使用 `nmcli` 或 `ip` 命令设置静态 IP，确保网络在安装过程中可用。
2. **在安装系统中配置静态 IP**：修改脚本，在 `configure_system` 函数中为 NetworkManager 配置静态 IPv4，写入 `/mnt/etc/NetworkManager/system-connections/`。
3. **更新脚本**：添加交互式提示，让用户输入 IPv4 地址、子网掩码、网关和 DNS 服务器，并在安装后自动应用。

以下是具体操作和更新后的脚本。

---

### 在 Live ISO 中配置静态 IPv4
在运行 `install_arch.sh` 脚本之前，您需要确保 Live ISO 环境的网络正常连接，以便下载软件包。以下是在 Live ISO 中设置静态 IPv4 的步骤：

1. **检查网络接口**：
   ```bash
   ip link
   ```
   - 找到您的网络接口名称，例如 `enp0s3`（有线）或 `wlan0`（无线）。
   - 示例输出：
     ```
     1: lo: <LOOPBACK,UP,LOWER_UP> ...
     2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
     ```

2. **使用 nmcli 配置静态 IPv4**：
   假设您的接口为 `enp0s3`，示例静态 IP 配置为：
   - IP 地址：`192.168.1.100`
   - 子网掩码：`255.255.255.0`（或 `/24`）
   - 网关：`192.168.1.1`
   - DNS 服务器：`8.8.8.8, 8.8.4.4`
   
   运行以下命令：
   ```bash
   nmcli con add type ethernet ifname enp0s3 con-name "static-eth" \
         ipv4.method manual \
         ipv4.addresses 192.168.1.100/24 \
         ipv4.gateway 192.168.1.1 \
         ipv4.dns "8.8.8.8,8.8.4.4"
   nmcli con up static-eth
   ```

3. **验证网络**：
   ```bash
   ping -c 4 archlinux.org
   ```
   - 如果收到回复，网络配置成功。
   - 如果失败，检查接口名称、IP 地址或网关。

4. **无线网络（可选）**：
   如果使用 Wi-Fi（接口如 `wlan0`），先连接到无线网络：
   ```bash
   systemctl start iwd
   iwctl
   # 在 iwctl 交互式界面中：
   device list
   station wlan0 scan
   station wlan0 get-networks
   station wlan0 connect "Your-Wifi-SSID"
   exit
   ```
   然后配置静态 IP：
   ```bash
   nmcli con add type wifi ifname wlan0 con-name "static-wifi" ssid "Your-Wifi-SSID" \
         ipv4.method manual \
         ipv4.addresses 192.168.1.100/24 \
         ipv4.gateway 192.168.1.1 \
         ipv4.dns "8.8.8.8,8.8.4.4"
   nmcli con up static-wifi
   ```

5. **继续运行脚本**：
   确认网络可用后，运行脚本：
   ```bash
   pacman -Sy dialog
   chmod +x install_arch.sh
   ./install_arch.sh
   ```

---

### 更新脚本：为安装系统配置静态 IPv4
我将修改 `install_arch.sh`，在 `check_network` 函数中添加交互式提示，收集用户输入的静态 IPv4 配置（IP 地址、子网掩码、网关、DNS），并在 `configure_system` 函数中为安装后的系统配置 NetworkManager 的静态 IPv4 连接。

#### 更新内容
1. **交互式网络配置**：
   - 在 `check_network` 中，询问用户是否使用静态 IPv4。
   - 如果选择静态，提示输入 IP 地址、子网掩码、网关和 DNS。
2. **保存配置**：
   - 在 `configure_system` 中，写入 `/mnt/etc/NetworkManager/system-connections/static-eth.nmconnection`（有线）或 `static-wifi.nmconnection`（无线）。
3. **保留现有功能**：
   - 保持 Alacritty (`Super + Enter`)、Rofi (`Super + Space`)、手动启动 Hyprland、通知/音量/截图工具。

### 优化后的安装脚本

<xaiArtifact artifact_id="df120ad5-5b28-4f1d-9377-19ad8e96ca68" artifact_version_id="684c524b-99e3-4b94-9ce8-750114c5e6a4" title="install_arch.sh" contentType="text/x-sh">
#!/bin/bash

# Arch Linux Btrfs 开发者定制安装脚本（含 Hyprland、NVIDIA、Alacritty、Rofi 和静态 IPv4）
# 基于 2025 年 10 月 23 日的 Arch Linux Wiki 和 Hyprland Wiki
# 优化：交互式菜单（dialog），模块化设计，手动启动 Hyprland，Alacritty (Super+Enter)，Rofi (Super+Space)，静态 IPv4 配置
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

### 更新说明
1. **静态 IPv4 配置**：
   - **Live ISO 环境**：建议在运行脚本前使用 `nmcli` 手动配置静态 IPv4（见上文）。
   - **安装系统**：
     - 在 `check_network` 中，添加交互式提示，收集 IP 地址、子网掩码、网关、DNS 和 Wi-Fi SSID（如果适用）。
     - 子网掩码支持 `255.255.255.0` 或 `/24` 格式（自动转换）。
     - 在 `configure_system` 中，写入 NetworkManager 配置文件（`static-eth.nmconnection` 或 `static-wifi.nmconnection`）。
     - 默认接口：有线用 `enp0s3`，无线用 `wlan0`（可手动调整配置文件）。
   - **验证**：在 `final_check` 中，显示静态 IPv4 配置文件（如果启用）。
2. **保留功能**：
   - **Alacritty**：绑定 `Super + Enter`，默认配置文件（字体大小 12，透明度 0.9）。
   - **Rofi**：绑定 `Super + Space`，默认使用 `arc-dark` 主题。
   - 手动启动 Hyprland（终端输入 `Hyprland`）。
   - 通知（`mako`）、音量（`pamixer` + `swayosd`）、截图（`grim` + `slurp` + `hyprshot`）。
   - 时间同步（`systemd-timesyncd`）、NVIDIA 配置、Btrfs 和 Snapper。
3. **交互式菜单**：
   - 新增静态 IPv4 配置询问（IP、子网掩码、网关、DNS、Wi-Fi SSID）。
   - 保留可选安装 `iwd`、`desktop_tools`、`alacritty`、`rofi`。

### 使用说明
1. **Live ISO 网络配置**：
   - 在运行脚本前，按照上文步骤为 Live ISO 配置静态 IPv4（确保 `pacstrap` 能下载软件包）。
   - 示例：
     ```bash
     nmcli con add type ethernet ifname enp0s3 con-name "static-eth" \
           ipv4.method manual \
           ipv4.addresses 192.168.1.100/24 \
           ipv4.gateway 192.168.1.1 \
           ipv4.dns "8.8.8.8,8.8.4.4"
     nmcli con up static-eth
     ```

2. **运行脚本**：
   ```bash
   pacman -Sy dialog
   chmod +x install_arch.sh
   ./install_arch.sh
   ```

3. **交互式菜单**：
   - **网络配置**：
     - 询问是否配置静态 IPv4。
     - 输入 IP 地址（例如 `192.168.1.100`）、子网掩码（`255.255.255.0` 或 `/24`）、网关（`192.168.1.1`）、DNS（`8.8.8.8,8.8.4.4`）。
     - 如果是 Wi-Fi，输入 SSID。
     - 未提供完整信息则回退到 DHCP。
   - **其他**：硬盘选择、无线支持、桌面工具、Alacritty、Rofi、分区、密码、fstab、arch.conf。
   - **最终检查**：验证 `fstab`、`arch.conf` 和静态 IPv4 配置文件。

4. **启动后**：
   - 登录终端，输入 `Hyprland` 启动桌面。
   - **Super + Enter**：打开 Alacritty。
   - **Super + Space**：打开 Rofi。
   - **通知**：`mako` 自动启动（测试：`notify-send "Test" "Hello"`）。
   - **音量**：键盘音量键，`swayosd` 显示 OSD。
   - **截图**：`Super + Print`（窗口）、`Print`（全屏）、`Super + Shift + Print`（区域）。
   - **输入法**：运行 `fcitx5-configtool` 配置拼音输入法。
   - **网络**：重启后，NetworkManager 自动应用静态 IPv4（检查：`nmcli con show`）。

5. **验证和自定义**：
   - **网络**：
     - 检查连接：`nmcli con show --active`。
     - 编辑静态配置：`sudo nano /etc/NetworkManager/system-connections/static-eth.nmconnection`（或 `static-wifi.nmconnection`）。
     - 重新加载：`nmcli con reload`。
   - **Alacritty**：编辑 `~/.config/alacritty/alacritty.toml`。
   - **Rofi**：编辑 `~/.config/rofi/config.rasi`，更换主题（如 `solarized`）。
   - **时间同步**：`timedatectl status` 确认同步。

### 注意事项
- **备份**：运行前备份数据，分区会清除磁盘。
- **NVIDIA**：若 GPU 非 Turing+ 架构，将 `nvidia-open-dkms` 替换为 `nvidia-dkms`。
- **接口名称**：脚本默认 `enp0s3`（有线）或 `wlan0`（无线），若不同，编辑 `/etc/NetworkManager/system-connections/` 文件。
- **调试**：查看 `/root/install_arch.log` 或 Hyprland Discord 的 `#hyprland-nvidia` 频道。
- **Wi-Fi 密码**：若 Wi-Fi 需要密码，安装后手动运行 `nmcli con modify static-wifi wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Your-Password"`。

如果您需要特定 IP 配置（如固定接口名称、Wi-Fi 密码）或进一步定制，请提供详细信息！