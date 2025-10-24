### 使用说明
1. **准备环境**：
   ```bash
   pacman -Sy dialog
   chmod +x install_arch.sh
   ./install_arch.sh
   ```
2. **交互式菜单**：
   - **硬盘选择**：列出可用磁盘（名称、大小、型号）。
   - **无线支持**：询问是否安装 `iwd`。
   - **桌面管理工具**：询问是否安装 `mako`, `pamixer`, `swayosd`, `grim`, `slurp`, `hyprshot`。
   - **SDDM**：询问是否安装 SDDM。
   - **手动步骤**：分区（`fdisk`）、密码、编辑 `fstab` 和 `arch.conf`。
3. **使用桌面工具**：
   - **通知**：登录 Hyprland 后，`mako` 自动显示通知（测试：`notify-send "Test" "Hello"`）。
   - **音量**：使用键盘音量键，`swayosd` 显示 OSD 条。
   - **截图**：使用 `Super + Print`（窗口）、`Print`（全屏）、`Super + Shift + Print`（区域），截图保存到 `~/Pictures`。
4. **Fcitx5**：登录 Hyprland 后运行 `fcitx5-configtool` 配置拼音输入法。

### 注意事项
- **备份**：运行前备份数据，分区操作会清除磁盘。
- **NVIDIA**：若 GPU 非 Turing+ 架构，需将 `nvidia-open-dkms` 替换为 `nvidia-dkms`。
- **调试**：问题可查看 `/root/install_arch.log` 或 Hyprland Discord 的 `#hyprland-nvidia` 频道。
- **依赖**：确保网络连接正常，`paru` 安装 `hyprshot` 需要 AUR 访问。

如需进一步定制（如添加其他工具或调整绑定），请提供详细信息！