为了满足您的需求，我将原 `install_arch.sh` 脚本拆分为两个独立的脚本：

1. **install_base_arch.sh**：安装基础 Arch Linux 系统，包括 Btrfs 分区、静态 IPv4 配置、时间同步、NVIDIA 驱动等核心功能。
2. **install_hyprland.sh**：安装 Hyprland 桌面环境，支持选择手动启动或安装 Display Manager（SDDM），并配置 Alacritty（`Super + Enter`）、Rofi（`Super + Space`）、通知、音量、截图工具等。

### 设计思路
- **install_base_arch.sh**：
  - 完成磁盘分区、格式化、Btrfs 子卷、Swapfile、基础系统安装（`pacstrap`）。
  - 配置静态 IPv4（通过 `nmcli` 和 NetworkManager）、时间同步（`systemd-timesyncd`）、NVIDIA 驱动、systemd-boot。
  - 创建用户 `syaofox` 并设置密码。
  - 不包含桌面环境相关内容，确保基础系统独立。
- **install_hyprland.sh**：
  - 运行于已安装的基础 Arch 系统（假定挂载点 `/` 已正确配置）。
  - 提供交互式选择：手动启动 Hyprland 或安装 SDDM。
  - 安装 Hyprland、Alacritty、Rofi、桌面管理工具（通知、音量、截图）。
  - 配置 Fcitx5 输入法、Brave 浏览器、Snapper 快照。
- **静态 IPv4**：在 `install_base_arch.sh` 中保留交互式静态 IPv4 配置，确保网络可用。
- **模块化**：两个脚本独立运行，`install_hyprland.sh` 可在基础系统安装后单独执行。
- **日志和错误检查**：每个脚本记录日志到 `/root/install_base_arch.log` 或 `/root/install_hyprland.log`。

### 脚本 1：安装基础 Arch 系统


---

### 脚本 2：安装 Hyprland 桌面环境


#### 1. 运行基础 Arch 安装脚本
在 Arch Linux Live ISO 环境中：
```bash
pacman -Sy dialog
chmod +x install_base_arch.sh
./install_base_arch.sh
```
- **步骤**：
  - **网络配置**：支持静态 IPv4（输入 IP、子网掩码、网关、DNS、Wi-Fi SSID）或 DHCP。
  - **硬盘选择**：交互式选择磁盘，分区（1G EFI + Btrfs），格式化，挂载 Btrfs 子卷。
  - **Swapfile**：创建 64GB Swapfile。
  - **系统安装**：安装 `base`, `linux`, `systemd`, `networkmanager`, `nvidia-open-dkms` 等。
  - **配置**：设置时间同步（国内 NTP 服务器）、本地化（`en_US.UTF-8`, `zh_CN.UTF-8`）、主机名、用户（`syaofox`）、NVIDIA 驱动、systemd-boot。
  - **最终检查**：验证 `fstab` 和 `arch.conf`。
- **网络（Live ISO）**：
  - 如果需要静态 IPv4，先手动配置（参考上一回答）：
    ```bash
    nmcli con add type ethernet ifname enp0s3 con-name "static-eth" \
          ipv4.method manual \
          ipv4.addresses 192.168.1.100/24 \
          ipv4.gateway 192.168.1.1 \
          ipv4.dns "8.8.8.8,8.8.4.4"
    nmcli con up static-eth
    ```
  - 对于 Wi-Fi，先连接：
    ```bash
    systemctl start iwd
    iwctl
    # station wlan0 scan
    # station wlan0 connect "Your-Wifi-SSID"
    ```
    然后配置静态 IPv4：
    ```bash
    nmcli con add type wifi ifname wlan0 con-name "static-wifi" ssid "Your-Wifi-SSID" \
          ipv4.method manual \
          ipv4.addresses 192.168.1.100/24 \
          ipv4.gateway 192.168.1.1 \
          ipv4.dns "8.8.8.8,8.8.4.4"
    nmcli con up static-wifi
    ```
- **完成**：重启进入新系统，登录为 `syaofox` 或 `root`。

#### 2. 运行 Hyprland 安装脚本
在已安装的基础 Arch 系统（或 chroot 环境）中：
```bash
sudo pacman -Sy dialog
chmod +x install_hyprland.sh
sudo ./install_hyprland.sh
```
- **步骤**：
  - **网络检查**：确保网络可用（静态 IPv4 或 DHCP）。
  - **软件安装**：
    - Hyprland 及依赖（`xdg-desktop-portal-hyprland`, `wayland-protocols`, `libxkbcommon`, `libinput`, `mesa`）。
    - 可选：`mako`, `pamixer`, `swayosd`, `grim`, `slurp`（通知/音量/截图）。
    - 可选：`alacritty`（`Super + Enter`）。
    - 可选：`rofi`（`Super + Space`）。
    - 可选：`sddm`（Display Manager）。
  - **配置**：
    - Hyprland：配置 `~/.config/hypr/hyprland.conf`，包括 NVIDIA 环境变量、通知/音量/截图绑定。
    - Alacritty：`~/.config/alacritty/alacritty.toml`（字体大小 12，透明度 0.9）。
    - Rofi：`~/.config/rofi/config.rasi`（`arc-dark` 主题）。
    - Fcitx5：设置输入法环境变量。
    - SDDM（可选）：配置自动登录 `syaofox` 到 Hyprland。
  - **额外软件**：安装 `paru`（AUR 助手）、`snapper`、`brave-bin`、`hyprshot`。
- **完成**：
  - 如果选择 SDDM：重启后自动登录 Hyprland。
  - 如果手动启动：登录终端，输入 `Hyprland`。

#### 3. 使用桌面环境
- **启动**：
  - SDDM：自动进入 Hyprland。
  - 手动：登录终端，输入 `Hyprland`。
- **快捷键**：
  - `Super + Enter`：打开 Alacritty。
  - `Super + Space`：打开 Rofi（应用启动器）。
  - `Super + Print`：窗口截图。
  - `Print`：全屏截图。
  - `Super + Shift + Print`：区域截图。
  - 音量键：调整音量并显示 OSD。
- **输入法**：运行 `fcitx5-configtool` 配置拼音输入法。
- **网络**：检查 `nmcli con show --active`，编辑 `/etc/NetworkManager/system-connections/` 调整静态 IPv4。

#### 4. 自定义
- **Alacritty**：编辑 `~/.config/alacritty/alacritty.toml`：
  ```toml
  [font]
  size = 14
  normal = { family = "JetBrains Mono", style = "Regular" }
  ```
- **Rofi**：编辑 `~/.config/rofi/config.rasi`：
  ```rasi
  @theme "/usr/share/rofi/themes/solarized.rasi"
  ```
- **SDDM**：编辑 `/etc/sddm.conf.d/hyprland.conf` 调整自动登录设置。
- **网络**：编辑 `/etc/NetworkManager/system-connections/static-eth.nmconnection` 或 `static-wifi.nmconnection`。

### 注意事项
- **备份**：运行 `install_base_arch.sh` 前备份数据，分区会清除磁盘。
- **NVIDIA**：若 GPU 非 Turing+ 架构，将 `nvidia-open-dkms` 替换为 `nvidia-dkms`。
- **网络接口**：默认 `enp0s3`（有线）或 `wlan0`（无线），若不同，编辑 NetworkManager 配置文件。
- **Wi-Fi 密码**：若 Wi-Fi 需要密码，安装后运行：
  ```bash
  nmcli con modify static-wifi wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Your-Password"
  ```
- **调试**：查看 `/root/install_base_arch.log` 或 `/root/install_hyprland.log`，或参考 Hyprland Discord 的 `#hyprland-nvidia` 频道。
- **依赖**：`install_hyprland.sh` 假定基础系统已正确安装（`install_base_arch.sh` 完成）。

如果您需要特定配置（如 Wi-Fi 密码、自定义 Rofi 主题、其他桌面工具），请提供详细信息！
