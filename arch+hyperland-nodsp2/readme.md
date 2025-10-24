感谢您的确认，您提到的是 **Rofi**（应用启动器/菜单工具），并要求将其绑定到 `Super + Space` 快捷键，同时使用 **Alacritty** 作为终端（绑定到 `Super + Enter`），并希望手动启动 Hyprland（无 Display Manager）。我注意到您未明确提出新需求，但假设您想确认或进一步优化 Rofi 集成，或者可能需要额外配置（如 Rofi 主题、样式等）。以下是对 Rofi 的进一步说明和优化后的脚本，确保满足您的需求。

### Rofi 说明
- **功能**：Rofi 是一个轻量级应用启动器（`drun` 模式）、窗口切换器和通用菜单工具，完美适配 Hyprland 的 Wayland 环境。
- **兼容性**：Rofi 与 Alacritty 无冲突，可通过 `Super + Space` 快速调用。
- **安装**：已通过 `paru` 安装（AUR 包 `rofi`）。
- **绑定**：在 `hyprland.conf` 中绑定 `Super + Space` 到 `rofi -show drun`。
- **默认配置**：脚本不包含 Rofi 主题自定义，但可手动配置 `~/.config/rofi/config.rasi`。

### 脚本优化
1. **Rofi 增强**：
   - 添加默认 Rofi 配置文件（`~/.config/rofi/config.rasi`），设置简洁主题（基于 `arc-dark`）。
   - 确保 Rofi 在 `install_extras` 中安装，并验证安装成功。
2. **Alacritty 配置**：
   - 添加默认 Alacritty 配置文件（`~/.config/alacritty/alacritty.toml`），设置基本字体和透明度。
   - 保留 `Super + Enter` 绑定。
3. **交互式菜单**：
   - 新增单独询问是否安装 Rofi（之前包含在桌面工具中），提高灵活性。
   - 保留 Alacritty 和其他桌面工具（通知/音量/截图）的可选安装。
4. **其他**：
   - 保留手动启动 Hyprland、时间同步（`systemd-timesyncd`）、NVIDIA 配置、Btrfs 和 Snapper。
   - 增强日志记录，确保 Rofi 和 Alacritty 配置写入正确。




### 更新说明
1. **Rofi 配置**：
   - **安装**：在 `install_extras` 中通过 `paru -S rofi` 安装。
   - **快捷键**：在 `hyprland.conf` 中绑定 `bind = $mainMod, space, exec, rofi -show drun`（Super + Space）。
   - **默认配置**：添加 `~/.config/rofi/config.rasi`，使用 `arc-dark` 主题，启用 `drun` 和 `run` 模式，显示图标。
2. **Alacritty 配置**：
   - **安装**：在 `install_system` 中通过 `pacstrap` 添加 `alacritty`（可选）。
   - **快捷键**：绑定 `bind = $mainMod, Return, exec, alacritty`（Super + Enter）。
   - **默认配置**：添加 `~/.config/alacritty/alacritty.toml`，设置字体大小为 12，窗口透明度为 0.9。
3. **交互式菜单**：
   - 新增单独询问是否安装 Rofi（`dialog --yesno`）。
   - 保留 Alacritty 和桌面工具（`mako`, `pamixer`, `swayosd`, `grim`, `slurp`) 的可选安装。
4. **其他**：
   - 保留手动启动 Hyprland（通过终端输入 `Hyprland`）。
   - 保留时间同步（`systemd-timesyncd`）、NVIDIA 配置（`nvidia-open-dkms`）、Btrfs 和 Snapper。
   - 日志记录到 `/root/install_arch.log`，确保 Rofi 和 Alacritty 配置写入正确。

### 使用说明
1. **运行脚本**：
   ```bash
   pacman -Sy dialog
   chmod +x install_arch.sh
   ./install_arch.sh
   ```
2. **交互式菜单**：
   - **硬盘选择**：列出可用磁盘（名称、大小、型号）。
   - **无线支持**：询问是否安装 `iwd`。
   - **桌面工具**：询问是否安装 `mako`, `pamixer`, `swayosd`, `grim`, `slurp`。
   - **Alacritty**：询问是否安装（绑定 Super + Enter）。
   - **Rofi**：询问是否安装（绑定 Super + Space）。
   - **手动步骤**：分区（`fdisk`）、密码设置、编辑 `fstab` 和 `arch.conf`。
3. **启动后**：
   - 登录终端，输入 `Hyprland` 启动桌面。
   - **Super + Enter**：打开 Alacritty 终端。
   - **Super + Space**：打开 Rofi 应用启动器（搜索并运行程序）。
   - **通知**：`mako` 自动启动（测试：`notify-send "Test" "Hello"`）。
   - **音量**：键盘音量键（`XF86Audio*`），`swayosd` 显示 OSD。
   - **截图**：`Super + Print`（窗口）、`Print`（全屏）、`Super + Shift + Print`（区域），保存到 `~/Pictures`。
   - **输入法**：运行 `fcitx5-configtool` 配置拼音输入法。
4. **自定义**：
   - **Alacritty**：编辑 `~/.config/alacritty/alacritty.toml` 调整字体、主题、透明度等。
     - 示例：更改字体为 JetBrains Mono：
       ```toml
       [font]
       size = 12
       normal = { family = "JetBrains Mono", style = "Regular" }
       ```
   - **Rofi**：编辑 `~/.config/rofi/config.rasi` 调整样式，例如：
     ```rasi
     @theme "/usr/share/rofi/themes/solarized.rasi"
     ```
   - 测试 Rofi：`rofi -show drun`。
   - 重载 Hyprland 配置：`hyprctl reload`。
5. **验证时间同步**：
   - 运行 `timedatectl status`，确保 "System clock synchronized: yes"。

### 注意事项
- **备份**：运行前备份数据，分区操作会清除磁盘。
- **NVIDIA**：若 GPU 非 Turing+ 架构，将 `nvidia-open-dkms` 替换为 `nvidia-dkms`。
- **调试**：问题查看 `/root/install_arch.log` 或 Hyprland Discord 的 `#hyprland-nvidia` 频道。
- **终端登录**：启动到终端，需输入用户名/密码和 `Hyprland`。
- **Rofi 主题**：默认使用 `arc-dark`，可替换为 `/usr/share/rofi/themes/` 下的其他主题。

如果您有其他 Rofi 定制需求（例如特定模式、额外插件或样式），或需要调整快捷键，请提供详细信息！