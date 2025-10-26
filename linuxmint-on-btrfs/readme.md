以下是针对 Linux Mint 22.2 的 Btrfs + 交换文件全新安装流程的优化版教程，仅实现以下三项改进：
1. **添加 `@tmp` 子卷**（挂载点 `/tmp`），优化临时文件管理并排除 Timeshift 快照。
2. **优化 `@cache` 压缩策略**，将 `@cache` 子卷的压缩设置为 `compress=no`，以适应多样化缓存数据，减少不必要的 CPU 开销。
3. **动态子卷命名**，通过脚本动态检测现有子卷，避免重复创建并提高兼容性。

优化后的教程保持原有结构的清晰性，修复潜在问题（如分区说明不清、错误检查不足），并确保适合初学者和进阶用户。脚本包含错误处理、交互提示，并整合了上述优化。

---

# Linux Mint 22.2 Btrfs + 交换文件全新安装流程

本文提供 Linux Mint 22.2 的全新安装流程，使用 Btrfs 文件系统，配置 `@`, `@home`, `@swap`, `@cache`, `@log`, 和 `@tmp` 子卷，并设置交换文件以优化 Timeshift 快照和系统性能。教程假设您使用 UEFI 系统，并熟悉基本 Linux 操作。

## 第一部分：安装前准备
1. **备份数据**  
   备份目标磁盘上的所有重要数据，安装过程会格式化分区，可能导致数据丢失。

2. **验证 ISO 文件**  
   从 [Linux Mint 官网](https://linuxmint.com/download.php) 下载 Linux Mint 22.2 ISO 文件，验证其完整性：  
   ```bash
   sha256sum linuxmint-22.2.iso
   ```
   将输出与官网提供的校验和对比。

3. **准备安装介质**  
   使用 Rufus（Windows）、Ventoy 或 `dd`（Linux/macOS）制作可启动 USB 驱动器。  
   示例（Linux，替换 `/dev/sdX` 为您的 USB 设备）：  
   ```bash
   sudo dd if=linuxmint-22.2.iso of=/dev/sdX bs=4M status=progress && sync
   ```

4. **启动 Live Session**  
   插入 USB，重启电脑，进入 BIOS/UEFI 设置，选择 USB 启动，进入 Linux Mint Live 环境。

## 第二部分：分区设置
1. **打开分区工具**  
   在 Live Session 中，打开 GParted：  
   ```bash
   sudo gparted
   ```

2. **创建分区表**  
   - 选择目标磁盘（例如 `/dev/nvme0n1` 或 `/dev/sda`）。  
   - 确认备份后，创建新分区表：  
     - 菜单：`Device > Create Partition Table > gpt`（UEFI 系统使用 GPT）。

3. **创建分区**  
   创建以下分区：  
   | 分区类型        | 大小（建议）      | 文件系统 | 标志 (Flags) | 挂载点（安装时使用） | 作用                     |
   |-----------------|-------------------|----------|--------------|----------------------|--------------------------|
   | EFI 系统分区 (ESP) | 512MB ~ 1GB      | FAT32    | boot, esp    | /boot/efi            | UEFI 启动所需            |
   | Btrfs 主分区    | 剩余所有空间      | Btrfs    | 无           | /                    | 系统和用户数据（含子卷） |

   **注意**：  
   - 不需要单独的交换分区，将在 `@swap` 子卷中创建交换文件。  
   - 确保 EFI 分区标记为 `boot, esp`。  
   - 记录 Btrfs 分区设备名（例如 `/dev/nvme0n1p2`）。

4. **应用更改**  
   在 GParted 中点击绿色勾号（✔）应用分区操作，完成后关闭 GParted。

## 第三部分：运行 Linux Mint 安装程序
1. **启动安装程序**  
   双击桌面上的 `Install Linux Mint` 图标。

2. **配置基本选项**  
   - 选择语言、键盘布局。  
   - 勾选“安装多媒体解码器”（推荐）。  
   - 连接网络以便下载更新。

3. **分区设置**  
   - 选择 **Something else（手动分区）**。  
   - 配置挂载点：  
     - **EFI 分区**：选择 FAT32 分区，设置为 `EFI System Partition`，挂载点 `/boot/efi`，无需格式化（若已有数据）。  
     - **Btrfs 分区**：选择 Btrfs 分区，设置为 `Btrfs journaling file system`，勾选 `Format`，挂载点 `/`。  
   - 确认“引导加载程序安装设备”为目标磁盘（例如 `/dev/nvme0n1`）。

4. **完成安装**  
   - 设置用户名、密码、时区等。  
   - 点击 `Install Now`，等待安装完成。  
   - 选择 **Continue Testing**（不要重启），以进行子卷和交换文件配置。

## 第四部分：配置 Btrfs 子卷和交换文件
在 Live Session 环境中配置子卷和交换文件，确保 Timeshift 快照排除和性能优化。

### 步骤 1：检查和准备
1. **定义变量**  
   定义 Btrfs 分区设备名（替换为您的实际分区，例如 `/dev/nvme0n1p2`）：  
   ```bash
   BTRFS_DEV=/dev/nvme0n1p2
   ```

2. **检查分区**  
   确认分区存在：  
   ```bash
   lsblk
   ```

3. **挂载 Btrfs 顶层**  
   ```bash
   sudo mkdir -p /mnt
   sudo umount -R /mnt 2>/dev/null
   sudo mount $BTRFS_DEV /mnt
   ```

4. **获取 Btrfs UUID**  
   ```bash
   BTRFS_UUID=$(lsblk -no UUID $BTRFS_DEV)
   echo "Btrfs UUID: $BTRFS_UUID"
   ```

### 步骤 2：创建子卷
Linux Mint 安装程序已创建 `@` 和 `@home` 子卷，动态检查并创建 `@swap`, `@cache`, `@log`, `@tmp`：  
```bash
for subvol in @swap @cache @log @tmp; do
    if sudo btrfs subvolume list /mnt | grep -q "$subvol"; then
        echo "Subvolume $subvol already exists, skipping."
    else
        sudo btrfs subvolume create /mnt/$subvol
    fi
done
```

### 步骤 3：迁移数据
将 `/var/log`, `/var/cache`, `/tmp` 数据迁移到新子卷：  
1. **挂载 @ 子卷**  
   ```bash
   sudo umount /mnt
   sudo mount -o subvol=@ $BTRFS_DEV /mnt
   ```

2. **创建临时挂载点**  
   ```bash
   sudo mkdir -p /mnt_log /mnt_cache /mnt_tmp
   sudo mount -o subvol=@log $BTRFS_DEV /mnt_log
   sudo mount -o subvol=@cache $BTRFS_DEV /mnt_cache
   sudo mount -o subvol=@tmp $BTRFS_DEV /mnt_tmp
   ```

3. **迁移数据**  
   ```bash
   for dir in log cache tmp; do
       src="/mnt/var/$dir"
       dst="/mnt_$dir"
       if [ "$dir" = "tmp" ]; then
           src="/mnt/$dir"
       fi
       if [ -d "$src" ] && [ "$(ls -A "$src")" ]; then
           sudo mv "$src"/* "$dst"/
           sudo rmdir "$src"
       fi
   done
   ```

4. **卸载临时挂载点**  
   ```bash
   sudo umount /mnt_log /mnt_cache /mnt_tmp
   sudo rm -rf /mnt_log /mnt_cache /mnt_tmp
   ```

### 步骤 4：配置交换文件
1. **创建挂载点**  
   ```bash
   sudo mkdir -p /mnt/{var/log,var/cache,tmp,swap,home}
   sudo mount -o subvol=@home $BTRFS_DEV /mnt/home 2>/dev/null
   sudo mount -o subvol=@log $BTRFS_DEV /mnt/var/log
   sudo mount -o subvol=@cache $BTRFS_DEV /mnt/var/cache
   sudo mount -o subvol=@tmp $BTRFS_DEV /mnt/tmp
   sudo mount -o subvol=@swap $BTRFS_DEV /mnt/swap
   ```

2. **创建交换文件**  
   交换文件大小建议为物理内存的 1-2 倍（例如 8GB 内存设 8-16GB）：  
   ```bash
   sudo btrfs filesystem mkswapfile --size 8G /mnt/swap/swapfile
   sudo chmod 600 /mnt/swap/swapfile
   ```

3. **启用并验证交换文件**  
   ```bash
   sudo swapon /mnt/swap/swapfile
   swapon --show
   ```

### 步骤 5：更新 fstab
编辑 `/mnt/etc/fstab`：  
```bash
sudo nano /mnt/etc/fstab
```

替换为以下内容（将 `a94861b2-e36a-405f-9175-982750cea431` 替换为您的 `$BTRFS_UUID`，并确认 EFI 分区的 UUID）：  
```
# / (Root Subvolume)
UUID=a94861b2-e36a-405f-9175-982750cea431 /               btrfs   subvol=@,defaults,relatime,compress=zstd 0 0
# /boot/efi
UUID=78C6-1B05  /boot/efi       vfat    umask=0077      0 1
# /home
UUID=a94861b2-e36a-405f-9175-982750cea431 /home           btrfs   subvol=@home,defaults,relatime,compress=zstd 0 0
# /var/log
UUID=a94861b2-e36a-405f-9175-982750cea431 /var/log        btrfs   subvol=@log,defaults,noatime,compress=no 0 0
# /var/cache
UUID=a94861b2-e36a-405f-9175-982750cea431 /var/cache      btrfs   subvol=@cache,defaults,noatime,compress=no 0 0
# /tmp
UUID=a94861b2-e36a-405f-9175-982750cea431 /tmp            btrfs   subvol=@tmp,defaults,noatime,compress=no 0 0
# /swap
UUID=a94861b2-e36a-405f-9175-982750cea431 /swap           btrfs   subvol=@swap,defaults,noatime,compress=no 0 0
# Swap File
/swap/swapfile none swap defaults 0 0
```

**优化说明**：  
- `@log`, `@cache`, `@tmp`, `@swap` 使用 `compress=no` 和 `noatime`，优化频繁写入性能。  
- `@`, `@home` 使用 `compress=zstd`，平衡空间和性能。  
- 验证 fstab：  
  ```bash
  sudo findmnt --verify --fstab /mnt/etc/fstab
  ```

### 步骤 6：完成配置
1. **卸载挂载点**  
   ```bash
   cd ~
   sudo umount -R /mnt
   ```

2. **重启系统**  
   ```bash
   reboot
   ```

## 第五部分：验证安装
1. **检查交换文件**  
   ```bash
   free -h
   swapon --show
   ```
   确认 Swap 显示 8G 且路径为 `/swap/swapfile`.

2. **验证子卷挂载**  
   ```bash
   btrfs subvolume list /
   findmnt -t btrfs
   ```
   确认 `@`, `@home`, `@swap`, `@cache`, `@log`, `@tmp` 正确挂载。

3. **验证 Timeshift 排除**  
   打开 Timeshift，检查快照设置，确认 `/var/log`, `/var/cache`, `/tmp`, 和 `/swap` 未包含在快照中：  
   ```bash
   sudo timeshift --check
   ```

## 第六部分：自动化脚本
以下是优化后的脚本，包含 `@tmp` 子卷、动态子卷检测、和 `@cache` 的 `compress=no` 策略。

```bash
#!/bin/bash
# configure_btrfs.sh - Configure Btrfs subvolumes and swap file for Linux Mint 22.2

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run as root (use sudo)."
    exit 1
fi

# Prompt for Btrfs partition
echo "Enter your Btrfs partition (e.g., /dev/nvme0n1p2):"
read BTRFS_DEV
if [ ! -b "$BTRFS_DEV" ]; then
    echo "Error: $BTRFS_DEV is not a valid block device."
    exit 1
fi

# Get Btrfs UUID
BTRFS_UUID=$(lsblk -no UUID "$BTRFS_DEV")
if [ -z "$BTRFS_UUID" ]; then
    echo "Error: Failed to get UUID for $BTRFS_DEV."
    exit 1
fi
echo "Btrfs UUID: $BTRFS_UUID"

# Get EFI partition UUID
EFI_DEV=$(lsblk -no NAME,MOUNTPOINT | grep /mnt/boot/efi | awk '{print $1}')
EFI_UUID=$(lsblk -no UUID "$EFI_DEV" 2>/dev/null)
if [ -z "$EFI_UUID" ]; then
    echo "Warning: Could not detect EFI partition UUID. Please update fstab manually."
    EFI_UUID="YOUR_EFI_UUID"
fi

# Prompt for swap file size
echo "Enter swap file size (e.g., 8G for 8GB):"
read SWAP_SIZE
if ! [[ "$SWAP_SIZE" =~ ^[0-9]+[GM]$ ]]; then
    echo "Error: Invalid swap size format. Use format like 8G."
    exit 1
fi

# Unmount any existing mounts
umount -R /mnt 2>/dev/null
mkdir -p /mnt

# Mount Btrfs top-level
mount "$BTRFS_DEV" /mnt || { echo "Error: Failed to mount $BTRFS_DEV."; exit 1; }

# Create subvolumes with dynamic check
SUBVOLS=(@swap @cache @log @tmp)
for subvol in "${SUBVOLS[@]}"; do
    if btrfs subvolume list /mnt | grep -q "$subvol"; then
        echo "Subvolume $subvol already exists, skipping."
    else
        btrfs subvolume create "/mnt/$subvol" || { echo "Error: Failed to create $subvol."; exit 1; }
    fi
done

# Unmount top-level
umount /mnt

# Mount @ subvolume and migrate data
mount -o subvol=@ "$BTRFS_DEV" /mnt || { echo "Error: Failed to mount @ subvolume."; exit 1; }
mkdir -p /mnt_log /mnt_cache /mnt_tmp
mount -o subvol=@log "$BTRFS_DEV" /mnt_log || { echo "Error: Failed to mount @log."; exit 1; }
mount -o subvol=@cache "$BTRFS_DEV" /mnt_cache || { echo "Error: Failed to mount @cache."; exit 1; }
mount -o subvol=@tmp "$BTRFS_DEV" /mnt_tmp || { echo "Error: Failed to mount @tmp."; exit 1; }

# Migrate /var/log, /var/cache, /tmp
for dir in log cache tmp; do
    src="/mnt/var/$dir"
    dst="/mnt_$dir"
    if [ "$dir" = "tmp" ]; then
        src="/mnt/$dir"
    fi
    if [ -d "$src" ] && [ "$(ls -A "$src")" ]; then
        mv "$src"/* "$dst"/ || { echo "Error: Failed to migrate /$dir."; exit 1; }
        rmdir "$src"
    fi
done

# Unmount temporary mounts
umount /mnt_log /mnt_cache /mnt_tmp
rm -rf /mnt_log /mnt_cache /mnt_tmp

# Create permanent mount points and mount subvolumes
mkdir -p /mnt/{var/log,var/cache,tmp,swap,home}
mount -o subvol=@home "$BTRFS_DEV" /mnt/home 2>/dev/null
mount -o subvol=@log "$BTRFS_DEV" /mnt/var/log || { echo "Error: Failed to mount @log."; exit 1; }
mount -o subvol=@cache "$BTRFS_DEV" /mnt/var/cache || { echo "Error: Failed to mount @cache."; exit 1; }
mount -o subvol=@tmp "$BTRFS_DEV" /mnt/tmp || { echo "Error: Failed to mount @tmp."; exit 1; }
mount -o subvol=@swap "$BTRFS_DEV" /mnt/swap || { echo "Error: Failed to mount @swap."; exit 1; }

# Create and enable swap file
btrfs filesystem mkswapfile --size "$SWAP_SIZE" /mnt/swap/swapfile || { echo "Error: Failed to create swapfile."; exit 1; }
chmod 600 /mnt/swap/swapfile
swapon /mnt/swap/swapfile || { echo "Error: Failed to enable swapfile."; exit 1; }
swapon --show

# Update fstab
FSTAB=/mnt/etc/fstab
cat > "$FSTAB" << EOF
# / (Root Subvolume)
UUID=$BTRFS_UUID /               btrfs   subvol=@,defaults,relatime,compress=zstd 0 0
# /boot/efi
UUID=$EFI_UUID  /boot/efi       vfat    umask=0077      0 1
# /home
UUID=$BTRFS_UUID /home           btrfs   subvol=@home,defaults,relatime,compress=zstd 0 0
# /var/log
UUID=$BTRFS_UUID /var/log        btrfs   subvol=@log,defaults,noatime,compress=no 0 0
# /var/cache
UUID=$BTRFS_UUID /var/cache      btrfs   subvol=@cache,defaults,noatime,compress=no 0 0
# /tmp
UUID=$BTRFS_UUID /tmp            btrfs   subvol=@tmp,defaults,noatime,compress=no 0 0
# /swap
UUID=$BTRFS_UUID /swap           btrfs   subvol=@swap,defaults,noatime,compress=no 0 0
# Swap File
/swap/swapfile none swap defaults 0 0
EOF

# Verify fstab
findmnt --verify --fstab "$F四大" || { echo "Error: fstab verification failed."; exit 1; }

# Unmount all
cd ~
umount -R /mnt

echo "Configuration complete! Reboot now: sudo reboot"
```

**运行脚本**：  
```bash
chmod +x configure_btrfs.sh
sudo ./configure_btrfs.sh
```

## 优化亮点
1. **添加 `@tmp` 子卷**：  
   - 挂载点 `/tmp`，使用 `compress=no` 和 `noatime`，优化临时文件性能，Timeshift 自动排除，减少快照大小。
2. **优化 `@cache` 压缩策略**：  
   - 设置 `compress=no`，适应多样化缓存数据（如已压缩的 `.deb` 文件），减少 CPU 开销。
3. **动态子卷命名**：  
   - 脚本检查现有子卷，避免重复创建，增强兼容性和健壮性。
4. **保持清晰性**：教程分块清晰，包含备份、验证和 Timeshift 检查，适合初学者。
5. **错误处理**：脚本包含分区检查、挂载验证和 fstab 校验，降低配置错误风险。

## 注意事项
- **硬件兼容性**：确保系统支持 Btrfs 和 UEFI。
- **交换文件大小**：根据内存调整（8GB 内存建议 8-16GB 交换文件）。
- **Timeshift 配置**：运行 `sudo timeshift --check` 确认 `/var/log`, `/var/cache`, `/tmp`, `/swap` 排除。
- **错误排查**：若启动失败，使用 Live USB 检查 `/mnt/etc/fstab` 或挂载点。

如需进一步定制（如针对特定硬件或服务器场景），请提供更多细节！