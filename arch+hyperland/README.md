
以下是将 **Arch Linux Btrfs 开发者定制完整安装教程（含 Hyprland 和 NVIDIA 支持）** 转化为一个流畅的 Bash 安装脚本（`install_arch.sh`）。该脚本涵盖了教程的所有步骤，自动化大部分操作，同时保留必要的用户交互（如分区、密码设置、编辑配置文件），并添加了错误检查和提示。脚本已优化，确保与 2025 年 10 月 23 日的 Arch Linux Wiki 和 Hyprland Wiki（Installation 和 NVidia 页面）一致，并包含了时间同步的补充配置。

### 脚本设计说明
1. **自动化与交互**：
   - 自动化非交互式步骤（如软件包安装、文件系统格式化、配置文件生成）。
   - 保留交互式步骤（如 `fdisk` 分区、密码设置、编辑 `fstab` 和 `arch.conf`），并提供清晰提示。
   - 添加错误检查（如网络、挂载点、UUID）以提高可靠性。
2. **时间同步**：
   - 包含 `systemd-timesyncd` 的启用和国内时间服务器配置，确保安装后系统时间同步。
3. **NVIDIA 和 Hyprland**：
   - 使用 `nvidia-open-dkms` 和 Hyprland 官方包，遵循 NVidia 页面推荐的环境变量和电源管理配置。
4. **Btrfs 和 Snapper**：
   - 配置 Btrfs 子卷和 Swapfile，启用 Snapper 自动快照。
5. **用户体验**：
   - 提供进度提示和验证步骤。
   - 使用颜色输出（红/绿）突出错误和成功信息。
   - 脚本在关键步骤暂停，允许用户检查或手动干预。

### 注意事项
- **运行环境**：脚本需在 Arch Linux Live 环境中以 root 用户运行。
- **用户输入**：用户需手动完成分区、编辑特定配置文件（如 `fstab` 和 `arch.conf`）以及设置密码。
- **硬件假设**：主硬盘为 `/dev/nvme0n1`，用户需根据实际硬件调整（如 `/dev/sda`）。
- **备份提示**：运行前请备份重要数据，脚本涉及磁盘操作，可能导致数据丢失。



### 使用说明
1. **保存脚本**：
   - 将上述脚本保存为 `install_arch.sh`。
   - 在 Arch Linux Live 环境中运行：
     ```bash
     chmod +x install_arch.sh
     ./install_arch.sh
     ```

2. **用户交互**：
   - **硬盘选择**：默认使用 `/dev/nvme0n1`，可输入其他设备（如 `/dev/sda`）。
   - **分区**：脚本暂停以运行 `fdisk`，用户需手动创建分区。
   - **fstab 编辑**：用户需检查并确认 `/etc/fstab`。
   - **密码设置**：在 chroot 环境中设置 `root` 和 `syaofox` 的密码。
   - **arch.conf 编辑**：用户需手动输入 Btrfs 根分区的 UUID。
   - **最终检查**：脚本显示 `fstab` 和 `arch.conf` 内容，用户需确认。

3. **错误处理**：
   - 脚本检查 UEFI 模式、网络连接、时间同步、NVIDIA DRM 和 systemd-boot 状态。
   - 失败时显示红色错误信息并退出。

4. **时间同步**：
   - 启用 `systemd-timesyncd` 并配置国内时间服务器（`cn.pool.ntp.org` 和 `time.google.com`）。
   - 验证时间同步状态，确保 "System clock synchronized: yes"。

5. **Hyprland 和 NVIDIA**：
   - 安装官方 `hyprland` 包，配置 NVIDIA 环境变量和电源管理。
   - 优化 Brave 以支持 Wayland 和 explicit sync。

### 注意事项
- **备份数据**：运行前确保备份重要数据，分区和格式化操作会清除磁盘。
- **硬件适配**：脚本假设主硬盘为 `/dev/nvme0n1`，若不同需手动输入。
- **NVIDIA 兼容性**：对于非 Turing+ GPU（如旧型号），可将 `nvidia-open-dkms` 替换为 `nvidia-dkms` 或 `nvidia-535xx-dkms`。
- **Fcitx5**：需在 Hyprland 中运行 `fcitx5-configtool` 配置输入法。
- **调试**：若 Hyprland 或 NVIDIA 出现问题，参考 Hyprland Discord 的 `#hyprland-nvidia` 频道。

如需进一步优化脚本（例如添加特定配置选项或支持其他硬件），请提供详细信息！