#!/bin/bash
# Syaofox - DWM Setup (Arch + en/zh + fcitx5 + official ly)
# Repo layout: arch-dwm/config/ + suckless/{dwm,slstatus} copied into ~/.config/, arch-dwm/scripts/ copied into ~/.config/scripts
# Build sources: ~/.config/dwm/
# Config files: ~/.config/alacritty/
# Startup: ~/.config/scripts/autostart.sh
# qimgv: image viewer
set -euo pipefail

# Ensure UTF-8 output even on minimal installs
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

declare -a MISSING_PACKAGES=()

# Track missing packages for final reminder
track_pkg_failure() {
    local pkg=$1
    MISSING_PACKAGES+=("$pkg")
}

# === Options ===
ONLY_CONFIG=false
INSTALL_MODE=""
SKIP_MENU=false
EXPORT_PACKAGES=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

while [[ $# -gt 0 ]]; do
    case $1 in
        --only-config)
            INSTALL_MODE="config"
            ONLY_CONFIG=true
            SKIP_MENU=true
            shift
            ;;
        --core-install)
            INSTALL_MODE="core"
            ONLY_CONFIG=false
            SKIP_MENU=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]
  (Run without arguments to show menu)
  --only-config     Copy configs and build only
  --core-install    Internal use (menu call)
  --help            Show help
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

set_mode() {
    local mode=$1
    case "$mode" in
        core)
            INSTALL_MODE="core"
            ONLY_CONFIG=false
            ;;
        config)
            INSTALL_MODE="config"
            ONLY_CONFIG=true
            ;;
    esac
}

prompt_install_mode() {
    while true; do
        cat << 'EOF'
Please select installation mode:
  1) Core installation (requires sudo/root)
  2) Config-only installation
  3) Exit
EOF
        read -rp "Enter option [1-3]: " choice
        case "$choice" in
            1)
                if [ "$EUID" -eq 0 ]; then
                    # 如果已经是root，确定目标用户
                    if [ -z "${INSTALL_USER:-}" ] && [ -n "${SUDO_USER:-}" ]; then
                        INSTALL_USER="$SUDO_USER"
                    elif [ -z "${INSTALL_USER:-}" ] && [ -n "${HOME:-}" ] && [ "$HOME" != "/root" ]; then
                        INSTALL_USER=$(basename "$HOME")
                    fi
                    if [ -z "${INSTALL_USER:-}" ]; then
                        echo "Error: Cannot determine target user. Please run this script as a regular user."
                        continue
                    fi
                    export INSTALL_USER
                    set_mode core
                    return 0
                fi
                if command -v sudo >/dev/null 2>&1; then
                    echo "Using sudo to run core installation..."
                    export INSTALL_USER="${USER:-$(whoami)}"
                    # 不使用 exec，以便执行完成后返回
                    if sudo --preserve-env=HOME,INSTALL_USER bash "$SCRIPT_PATH" --core-install; then
                        echo ""
                        echo -e "\033[0;36m[INFO] Core installation completed!\033[0m"
                        read -rp "Continue with config installation? (Y/n): " continue_choice
                        if [ -z "$continue_choice" ] || [[ "$continue_choice" =~ ^[Yy]$ ]]; then
                            # 确保以普通用户权限执行配置安装
                            # 此时主进程应该在普通用户权限下（因为是通过 sudo 子进程执行的）
                            # 但为了安全，再次检查权限
                            if [ "$EUID" -eq 0 ]; then
                                echo -e "\033[1;33m[WARN] Running as root detected, switching to user $INSTALL_USER for config installation...\033[0m"
                                if id "$INSTALL_USER" >/dev/null 2>&1; then
                                    exec su - "$INSTALL_USER" -c "cd '$SCRIPT_DIR' && bash '$SCRIPT_PATH' --only-config"
                                else
                                    echo "Error: User $INSTALL_USER does not exist."
                                    continue
                                fi
                            else
                                # 普通用户权限，直接继续
                                set_mode config
                                return 0
                            fi
                        else
                            echo -e "\033[1;33m[WARN] Skipping config installation, returning to menu...\033[0m"
                            continue
                        fi
                    else
                        echo -e "\033[1;33m[WARN] Core installation failed, returning to menu...\033[0m"
                        continue
                    fi
                else
                    echo "sudo not found. Please install sudo or run as root."
                    continue
                fi
                ;;
            2)
                # 检查是否以root身份运行配置安装
                if [ "$EUID" -eq 0 ]; then
                    echo -e "\033[1;33m[WARN] Running config installation as root detected.\033[0m"
                    # 确定目标用户
                    if [ -n "${SUDO_USER:-}" ]; then
                        CONFIG_USER="$SUDO_USER"
                    elif [ -n "${INSTALL_USER:-}" ]; then
                        CONFIG_USER="$INSTALL_USER"
                    elif [ -n "${HOME:-}" ] && [ "$HOME" != "/root" ]; then
                        CONFIG_USER=$(basename "$HOME")
                    else
                        echo "Error: Cannot determine target user. Please run config installation as a regular user."
                        echo "Hint: Use 'su - <username>' to switch to a regular user first."
                        continue
                    fi
                    if id "$CONFIG_USER" >/dev/null 2>&1; then
                        echo "Switching to user $CONFIG_USER to run config installation..."
                        read -rp "Press Enter to continue, or Ctrl+C to cancel: " dummy
                        # 切换到普通用户执行配置安装
                        exec su - "$CONFIG_USER" -c "cd '$SCRIPT_DIR' && bash '$SCRIPT_PATH' --only-config"
                    else
                        echo "Error: User $CONFIG_USER does not exist."
                        continue
                    fi
                else
                    set_mode config
                    return 0
                fi
                ;;
            3)
                exit 0
                ;;
            *)
                echo "Invalid option, please try again."
                ;;
        esac
    done
}

if [ "$SKIP_MENU" = false ]; then
    prompt_install_mode
fi

# === Paths ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUCKLESS_SRC="$SCRIPT_DIR/suckless"
DWM_SRC="$SUCKLESS_SRC/dwm"
SLSTATUS_SRC="$SUCKLESS_SRC/slstatus"
SLOCK_SRC="$SUCKLESS_SRC/slock"
CONFIG_SRC="$SCRIPT_DIR/config"
SCRIPTS_SRC="$SCRIPT_DIR/scripts"
TEMP_DIR="/tmp/dwm_$$"

# === Determine target user (before using HOME) ===
TARGET_USER=""
TARGET_HOME=""
if [ "$EUID" -eq 0 ]; then
    # 如果是 root 运行，确定目标用户
    if [ -n "${INSTALL_USER:-}" ]; then
        TARGET_USER="$INSTALL_USER"
    elif [ -n "${SUDO_USER:-}" ]; then
        TARGET_USER="$SUDO_USER"
    elif [ -n "${HOME:-}" ] && [ "$HOME" != "/root" ]; then
        TARGET_USER=$(basename "$HOME")
    fi
    if [ -n "$TARGET_USER" ] && id "$TARGET_USER" >/dev/null 2>&1; then
        TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    else
        # 无法确定目标用户，使用当前 HOME（可能是 /root）
        TARGET_USER=""
        TARGET_HOME="$HOME"
    fi
else
    # 普通用户运行
    TARGET_USER="${USER:-$(whoami)}"
    TARGET_HOME="$HOME"
fi

# 使用目标用户的 HOME 目录
CONFIG_DEST="$TARGET_HOME/.config"
LOG_FILE="$TARGET_HOME/dwm-install.log"

# 重定向日志到文件（tee 会同时输出到终端和文件）
# 注意：在菜单模式下，这不会干扰交互式输入，因为 tee 会保持终端输出
exec > >(tee -a "$LOG_FILE") 2>&1
mkdir -p "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT



# === Colors & logging ===
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
die() { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
msg() { echo -e "${CYAN}[INFO] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}" >&2; }

backup_existing_path() {
    local target=$1
    if [ -z "$target" ]; then
        return 0
    fi
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        return 0
    fi
    local parent backup_dir base suffix backup_path
    parent=$(dirname "$target")
    base=$(basename "$target")
    backup_dir="${parent}/.arch-dwm-backups"
    suffix="$(date +%Y%m%d%H%M%S)-$$"
    if ! mkdir -p "$backup_dir"; then
        warn "Failed to create backup directory for $target"
        return 1
    fi
    backup_path="${backup_dir}/${base}.${suffix}"
    if mv "$target" "$backup_path"; then
        msg "Moved existing $target to $backup_path"
        return 0
    else
        warn "Failed to move $target into backup directory"
        return 1
    fi
}

# === Step tracking ===
declare -a STEP_IDS=()
declare -a FAILED_STEPS=()
declare -A STEP_DESC=()
declare -A STEP_FUNC=()

register_step() {
    local id=$1 desc=$2 func=$3
    STEP_IDS+=("$id")
    STEP_DESC["$id"]="$desc"
    STEP_FUNC["$id"]="$func"
}

remove_failed_step() {
    local id=$1
    local updated=()
    for existing in "${FAILED_STEPS[@]}"; do
        if [ "$existing" != "$id" ]; then
            updated+=("$existing")
        fi
    done
    FAILED_STEPS=("${updated[@]}")
}

mark_step_failed() {
    local id=$1 already=false
    for existing in "${FAILED_STEPS[@]}"; do
        if [ "$existing" = "$id" ]; then
            already=true
            break
        fi
    done
    if [ "$already" = false ]; then
        FAILED_STEPS+=("$id")
    fi
}

execute_step() {
    local id=$1
    local func=${STEP_FUNC["$id"]}
    local desc=${STEP_DESC["$id"]}
    if [ -z "$func" ]; then
        warn "Step $id has no associated function"
        return 1
    fi
    msg ">>> $desc"
    if "$func"; then
        msg "Step completed: $desc"
        return 0
    else
        warn "Step failed: $desc"
        return 1
    fi
}

run_step() {
    local id=$1
    if execute_step "$id"; then
        remove_failed_step "$id"
        return 0
    else
        mark_step_failed "$id"
        return 1
    fi
}

run_all_steps() {
    local id
    for id in "${STEP_IDS[@]}"; do
        run_step "$id"
    done
}

prompt_retry_failed_steps() {
    while [ "${#FAILED_STEPS[@]}" -gt 0 ]; do
        echo
        warn "The following steps failed and can be retried:"
        local idx=1
        local id
        for id in "${FAILED_STEPS[@]}"; do
            echo "  [$idx] ${STEP_DESC["$id"]}"
            idx=$((idx + 1))
        done
        echo "  [Enter] Skip retry"
        read -rp "Enter the number of the step to retry: " choice
        if [ -z "$choice" ]; then
            break
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#FAILED_STEPS[@]}" ]; then
            local selected_id=${FAILED_STEPS[$((choice - 1))]}
            run_step "$selected_id"
        else
            warn "Invalid selection: $choice"
        fi
    done
}

if [ "$INSTALL_MODE" = "core" ] && [ "$EUID" -ne 0 ]; then
    die "--core-install requires root privileges. Please run through menu or with sudo."
fi

if [ "$INSTALL_MODE" = "config" ] && [ "$EUID" -eq 0 ]; then
    # 如果以root身份运行配置安装，这是不应该的
    # 配置安装应该以普通用户权限执行
    if [ -n "${SUDO_USER:-}" ]; then
        CONFIG_USER="$SUDO_USER"
    elif [ -n "${INSTALL_USER:-}" ]; then
        CONFIG_USER="$INSTALL_USER"
    else
        die "Error: Config installation must run as regular user, but running as root and cannot determine target user."
        die "Please run config installation as regular user, or use menu mode (option 2) to auto-switch user."
    fi
    warn "Running config installation as root detected. This is not safe."
    warn "Switching to user $CONFIG_USER to run config installation..."
    if id "$CONFIG_USER" >/dev/null 2>&1; then
        CONFIG_USER_HOME=$(getent passwd "$CONFIG_USER" | cut -d: -f6)
        exec su - "$CONFIG_USER" -c "cd '$SCRIPT_DIR' && bash '$SCRIPT_PATH' --only-config"
    else
        die "Error: User $CONFIG_USER does not exist."
    fi
fi

# === Welcome screen ===
# 只有在非菜单模式（SKIP_MENU=true）时才显示欢迎屏幕和确认提示
# 菜单模式下，用户已经在菜单中做了选择，不需要再次确认
if [ "$SKIP_MENU" = true ]; then
    clear
    echo -e "${CYAN}
  ╔══════════════════════════╗
  ║  Syaofox Arch DWM Setup  ║
  ║  DWM * ly * Alacritty    ║
  ╚══════════════════════════╝
${NC}"
    if [ "$ONLY_CONFIG" = true ]; then
        echo "Current mode: Config-only installation (regular user)"
        prompt_text="  Start config-only setup? (Y/n) "
    else
        echo "Current mode: Core installation (requires root)"
        prompt_text="  Start core installation? (Y/n) "
    fi
    read -p "$prompt_text" -n 1 -r; echo
    if [ -z "$REPLY" ]; then
        REPLY="Y"
    fi
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# === System update / Config setup ===
step_update_system() {
    msg "Updating system..."
    if sudo pacman -Syu --noconfirm; then
        return 0
    fi
    warn "System update failed"
    return 1
}

step_config_user_setup() {
    msg "Skipping system update (--only-config)"
    if command -v git >/dev/null 2>&1; then
        msg "Configuring Git global user info..."
        if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
            sudo -u "$TARGET_USER" git config --global user.name "syaofox"
            sudo -u "$TARGET_USER" git config --global user.email "syaofox@gmail.com"
        else
            if [ "$EUID" -eq 0 ]; then
                warn "Running as root to set Git global config. It's recommended to run as regular user to avoid writing to root's config."
            fi
            git config --global user.name "syaofox"
            git config --global user.email "syaofox@gmail.com"
        fi
        
        # Install Git LFS support
        if command -v git-lfs >/dev/null 2>&1; then
            msg "Installing Git LFS support..."
            if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
                if sudo -u "$TARGET_USER" git lfs install; then
                    msg "Git LFS installed successfully for user $TARGET_USER"
                else
                    warn "Failed to install Git LFS for user $TARGET_USER"
                fi
            else
                if git lfs install; then
                    msg "Git LFS installed successfully"
                else
                    warn "Failed to install Git LFS"
                fi
            fi
        else
            warn "git-lfs not found, skipping Git LFS installation. Please install git-lfs package first."
        fi
    else
        warn "git not found, skipping global user config. Please install git and manually run git config --global user.name/email."
    fi

    BASHRC_PATH="$TARGET_HOME/.bashrc"
    ALIAS_MARKER="# === dwm-arch-install aliases ==="
    if [ -f "$BASHRC_PATH" ] && grep -Fq "$ALIAS_MARKER" "$BASHRC_PATH"; then
        msg "Bash alias config detected, skipping append."
        return 0
    fi

    msg "Appending bash aliases and prompt config to $BASHRC_PATH"
    if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
        {
            printf '\n%s\n' "$ALIAS_MARKER"
            cat <<'EOF_ALIAS'
# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# custom alias
alias adult="cd /mnt/dnas/data/adult/; pwd"
alias ytd='yt-dlp -f "bestvideo+bestaudio/best" -o "~/Videos/ytb-down/%(title)s.%(ext)s"'
alias lzd='lazydocker'

eval "$(uv generate-shell-completion bash)"

# prompt style
PS1='\[\e[38;5;76m\]\u\[\e[0m\] in \[\e[38;5;111m\]\w\[\e[0m\] \\$ '

# uv path
export UV_CACHE_DIR=/mnt/github/.uv_cache
export PATH="$HOME/.local/bin:$PATH"
EOF_ALIAS
        } | sudo -u "$TARGET_USER" tee -a "$BASHRC_PATH" > /dev/null || return 1
    else
        {
            printf '\n%s\n' "$ALIAS_MARKER"
            cat <<'EOF_ALIAS'
# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# custom alias
alias adult="cd /mnt/dnas/data/adult/; pwd"
alias ytd='yt-dlp -f "bestvideo+bestaudio/best" -o "~/Videos/ytb-down/%(title)s.%(ext)s"'
alias lzd='lazydocker'

eval "$(uv generate-shell-completion bash)"

# prompt style
PS1='\[\e[38;5;76m\]\u\[\e[0m\] in \[\e[38;5;111m\]\w\[\e[0m\] \\$ '

# uv path
export UV_CACHE_DIR=/mnt/github/.uv_cache
export PATH="$HOME/.local/bin:$PATH"
EOF_ALIAS
        } >> "$BASHRC_PATH" || return 1
    fi
    return 0
}

# === Package groups ===
# shellcheck disable=SC2034  # accessed via declare -n
PACKAGES_CORE=(    
    xorg-server # 提供 Xorg 显示服务器
    xorg-xinit # 使用 startx 启动图形界面的工具
    xorg-xbacklight # X11 下调节屏幕亮度
    libxft # X11 字体渲染库
    libxinerama # X11 扩展库
    libx11 # X11 基础库
    webkit2gtk # WebKit 浏览器引擎
    xbindkeys # 基于 X11 的全局快捷键守护进程
    xorg-xinput # 配置输入设备的命令行工具
    xorg-xrandr # 配置与管理显示器分辨率及布局
    base-devel # Arch 构建软件包常用的编译工具集合
    sxhkd # 轻量级自定义快捷键守护进程
    xdotool # 模拟键鼠输入与窗口操作
    dbus # 进程间通信总线服务
    libnotify # 桌面通知消息库
    sof-firmware # 软硬件固件
)
# shellcheck disable=SC2034
PACKAGES_UI=(
    rofi # 快速启动器及窗口切换器
    dunst # 轻量级通知守护进程
    feh # 轻量级图片查看与壁纸设置工具
    lxappearance # GTK 主题与外观设置工具
    xsettingsd  # gtk 主题
    # kvantum 
    # qt5ct 
    # qt6ct 
    network-manager-applet # NetworkManager 托盘小程序
    nm-connection-editor # NetworkManager 连接管理图形界面
    blueman # 蓝牙设备管理器
    polkit-gnome # polkit 图形认证代理
    htop # 交互式系统进程监视器
    btop # 现代化终端资源监控工具
    fastfetch # 终端系统信息展示工具
    mpv # 多媒体播放器
)
# shellcheck disable=SC2034
PACKAGES_FILE=(
    thunar # XFCE 文件管理器
    thunar-archive-plugin # Thunar 压缩包集成插件
    thunar-volman # Thunar 可移动设备自动挂载
    thunar-media-tags-plugin # Thunar 媒体标签插件,批量重命名

    # nemo # 现代化的文件管理器
    # nemo-fileroller # Nemo 压缩包集成插件
    udisks2 # 磁盘管理和设备挂载服务
    gvfs # GNOME 虚拟文件系统支持
    dialog # 终端对话框界面工具
    mtools # FAT 文件系统管理工具集
    # samba # SMB/CIFS 文件共享服务
    nfs-utils # NFS 文件共享服务
    cifs-utils # 挂载 SMB/CIFS 共享的工具
    unzip # 解压 ZIP 压缩包
    timeshift # 系统备份和恢复工具
)
# shellcheck disable=SC2034
PACKAGES_AUDIO=(
    pavucontrol # PulseAudio/PipeWire 的图形化音量管理器
    pulsemixer # PulseAudio 的终端混音器
    pamixer # PulseAudio 命令行音量工具
    pipewire-pulse # 为 PipeWire 提供 PulseAudio 兼容层
    pasystray # PulseAudio 状态托盘图标
)
# shellcheck disable=SC2034
PACKAGES_UTIL=(
    avahi # 提供 mDNS/DNS-SD 服务发现
    acpi # 查询 ACPI 硬件信息
    acpid # ACPI 事件守护进程
    xfce4-power-manager # 图形化电源管理器
    flameshot # 交互式截图工具
    xdg-user-dirs # 创建标准用户目录
    xdg-user-dirs-gtk # GTK 环境下的 XDG 目录提示
    # fd # 现代化快速文件搜索工具
    xclip # 剪贴板管理工具
    clipmenu # 剪贴板管理器
    gnome-keyring # GNOME 密钥环密码存储
    seahorse # GNOME 密钥环图形管理工具
    picom # X11 合成器（Compositor）
)
# shellcheck disable=SC2034
PACKAGES_TERM=(
    alacritty # 跨平台 GPU 加速终端
    neovim # 改进版 Vim 文本编辑器
    gpick # 屏幕取色器工具
    tree # 文件树浏览工具
    less # 分页查看器
)
# shellcheck disable=SC2034
PACKAGES_FONT=(
    ttf-jetbrains-mono-nerd # JetBrains Mono Nerd Patched 字体
    noto-fonts # Noto Fonts 字体
    noto-fonts-cjk # Noto Fonts CJK 字体
    noto-fonts-extra # Noto Fonts Extra 字体
    noto-fonts-emoji # Noto Emoji 字体
    wqy-microhei # 文泉驿微米黑中文字体
    # ttf-ubuntu-font-family # Ubuntu 官方字体   

)
# shellcheck disable=SC2034
PACKAGES_INPUT=(
    fcitx5 # Linux 输入法框架
    fcitx5-configtool # Fcitx5 图形化配置工具
    fcitx5-gtk # Fcitx5 的 GTK 输入法模块
    fcitx5-qt # Fcitx5 的 Qt 输入法模块
    fcitx5-chinese-addons # Fcitx5 中文输入扩展
    fcitx5-material-color # Fcitx5 材料颜色主题
)
# shellcheck disable=SC2034
PACKAGES_BUILD=(
    cmake # 跨平台构建系统
    meson # 现代化高性能构建系统
    ninja # 与 Meson 配套的高速构建工具
    curl # 命令行网络请求工具
    pkgconf # pkg-config 的轻量替代实现

)
# shellcheck disable=SC2034
PACKAGES_DEV=(
    python # Python 解释器
    python-pip # Python 官方包管理器
    uv # Rust 编写的 Python 包管理与虚拟环境工具
    nodejs # JavaScript 运行时
    docker # Docker 容器平台
    docker-compose # Docker Compose 容器编排工具
    nvidia-container-toolkit # NVIDIA 容器工具包
    git # Git 版本控制工具
    git-lfs # Git 大文件存储工具
)
# shellcheck disable=SC2034
PACKAGES_DM=(
    ly # 终端界面的登录管理器
)

step_install_official_packages() {
    local had_failure=0
    for group in CORE UI FILE AUDIO UTIL TERM FONT INPUT BUILD DEV DM; do
        declare -n packages_ref="PACKAGES_${group}"
        msg "Installing $group packages..."
        if [ "${#packages_ref[@]}" -gt 0 ]; then
            if ! sudo pacman -S --noconfirm --needed "${packages_ref[@]}"; then
                warn "Failed to install $group packages in batch, retrying individually..."
                local group_failed=0
                for pkg in "${packages_ref[@]}"; do
                    if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
                        if ! sudo pacman -S --noconfirm "$pkg"; then
                            warn "$pkg failed to install and was added to the missing list"
                            track_pkg_failure "$pkg"
                            group_failed=1
                        fi
                    fi
                done
                if [ "$group_failed" -eq 1 ]; then
                    had_failure=1
                fi
            fi
        else
            warn "Package group $group is empty, skipping"
        fi
        unset -n packages_ref
    done
    sudo systemctl enable avahi-daemon acpid 2>/dev/null || true

    if pacman -Qi docker >/dev/null 2>&1; then
        msg "Setting up Docker service..."
        sudo systemctl start docker 2>/dev/null || true
        sudo systemctl enable docker 2>/dev/null || true
        DOCKER_USER=""
        if [ -n "${INSTALL_USER:-}" ]; then
            DOCKER_USER="$INSTALL_USER"
        elif [ -n "${SUDO_USER:-}" ]; then
            DOCKER_USER="$SUDO_USER"
        elif [ "$EUID" -eq 0 ] && [ -n "${HOME:-}" ] && [ "$HOME" != "/root" ]; then
            DOCKER_USER=$(basename "$HOME")
        fi
        if [ -n "$DOCKER_USER" ]; then
            if id "$DOCKER_USER" >/dev/null 2>&1; then
                sudo usermod -aG docker "$DOCKER_USER" 2>/dev/null || true
                msg "Added user $DOCKER_USER to docker group (requires re-login to take effect)"
            else
                warn "User $DOCKER_USER does not exist, cannot add to docker group"
            fi
        else
            warn "Cannot automatically add current user to docker group. Please run manually: sudo usermod -aG docker \$USER"
        fi
    fi
    return "$had_failure"
}

step_install_aur_packages() {
    local aur_failed=0
    local helper_choice=""
    local selected_helper="yay"
    local helper_configured=false

    read -r -p "Select AUR helper to use (yay/paru) [yay]: " helper_choice
    helper_choice=$(printf '%s' "${helper_choice:-}" | tr '[:upper:]' '[:lower:]')
    case "$helper_choice" in
        ""|"yay") selected_helper="yay" ;;
        "paru") selected_helper="paru" ;;
        *)
            warn "Invalid input ${helper_choice}, falling back to yay."
            selected_helper="yay"
            ;;
    esac

    configure_helper_cores() {
        local cores owner home conf backup
        cores=$(nproc 2>/dev/null || echo 1)
        if [ "$cores" -le 1 ]; then
            msg "Single-core or unknown CPU count detected, keeping makepkg defaults."
            helper_configured=true
            return 0
        fi
        owner="${TARGET_USER:-${USER:-root}}"
        home="${TARGET_HOME:-${HOME:-/root}}"
        conf="$home/.makepkg.conf"
        backup="${conf}.arch-dwm.bak"
        msg "Configuring ${conf} to use ${cores} CPU cores for AUR builds..."
        if ! mkdir -p "$(dirname "$conf")"; then
            warn "Unable to create directory for ${conf}"
            return 1
        fi
        if [ -f "$conf" ] && [ ! -f "$backup" ]; then
            if cp "$conf" "$backup"; then
                msg "Backup created at ${backup}"
            else
                warn "Failed to create backup ${backup}"
            fi
        fi
        if [ -f "$conf" ] && grep -q '^[#[:space:]]*MAKEFLAGS=' "$conf"; then
            if ! sed -i "s|^[#[:space:]]*MAKEFLAGS=.*|MAKEFLAGS=\"-j${cores}\"|g" "$conf"; then
                warn "Failed to update MAKEFLAGS in ${conf}"
                return 1
            fi
        else
            if ! printf 'MAKEFLAGS="-j%s"\n' "$cores" >> "$conf"; then
                warn "Failed to write ${conf}"
                return 1
            fi
        fi
        if [ "$EUID" -eq 0 ] && [ -n "$owner" ]; then
            chown "$owner":"$owner" "$conf" 2>/dev/null || true
            [ -f "$backup" ] && chown "$owner":"$owner" "$backup" 2>/dev/null || true
        fi
        helper_configured=true
        msg "MAKEFLAGS updated to -j${cores} in ${conf}"
        return 0
    }

    ensure_makepkg_configured() {
        if [ "$helper_configured" = false ]; then
            configure_helper_cores || true
        fi
    }

    install_aur_helper() {
        local helper=$1
        local repo_url="https://aur.archlinux.org/${helper}.git"
        local build_dir="/tmp/${helper}"

        msg "Installing ${helper} AUR helper..."
        if ! sudo -n true 2>/dev/null; then
            msg "${helper} installation may prompt for sudo password."
        fi
        sudo pacman -S --noconfirm --needed base-devel git
        rm -rf "$build_dir" 2>/dev/null || true
        if git clone "$repo_url" "$build_dir"; then
            if (cd "$build_dir" && makepkg -si --noconfirm); then
                msg "${helper} installed successfully"
                ensure_makepkg_configured
                rm -rf "$build_dir"
            else
                warn "Building ${helper} failed, please install it manually"
                track_pkg_failure "${helper} (AUR helper)"
                rm -rf "$build_dir" 2>/dev/null || true
            fi
        else
            warn "Failed to clone ${helper} repository, please check your network"
            track_pkg_failure "${helper} (AUR helper)"
        fi
        cd "$SCRIPT_DIR"
        if [ "$EUID" -eq 0 ]; then
            warn "Warning: Script is running as root after installing ${helper}. This should not happen."
            warn "AUR packages will be installed as root, which is not recommended."
        fi
    }

    if ! command -v "$selected_helper" >/dev/null 2>&1; then
        install_aur_helper "$selected_helper"
    fi

    if ! command -v "$selected_helper" >/dev/null 2>&1; then
        if [ "$selected_helper" = "yay" ] && command -v paru >/dev/null 2>&1; then
            warn "Unable to use yay, falling back to existing paru."
            selected_helper="paru"
            ensure_makepkg_configured
        elif [ "$selected_helper" = "paru" ] && command -v yay >/dev/null 2>&1; then
            warn "Unable to use paru, falling back to existing yay."
            selected_helper="yay"
            ensure_makepkg_configured
        fi
    fi

    AUR=$(command -v "$selected_helper")
    [ -n "$AUR" ] && ensure_makepkg_configured
    AUR_CATALOG=(
        "brave-bin::Privacy-focused browser based on Chromium"
        "cursor-bin::Cursor AI editor binary package"
        "tdx-bin::Tongdaxin stock trading client"
        "freefilesync-bin::Cross-platform file synchronization tool"
        "czkawka-gui-bin::Duplicate file cleaner GUI"
        "fsearch::Fast file indexer similar to Everything"
        "localsend-bin::Local network cross-platform file transfer tool"
        "pinta::Lightweight image editor"
        "xnconvert::Batch image format converter"
        "lazydocker-bin::Docker/TUI management panel"
        # "papirus-icon-theme::Papirus icon theme"
        # "Qogir-icon-theme::Qogir icon theme"
        "timeshift-autosnap::Timeshift autosnap support"
        "nemo-media-columns::Nemo media columns"
        "mint-y-icons::Mint Y icon theme"
        "mint-themes::Mint themes"
        "tokyonight-gtk-theme-git::Tokyo Night GTK theme"
        "nordic-theme::Nordic theme"
        "nordzy-icon-theme::Nordzy icon theme"
        "nordzy-cursors::Nordzy cursor theme"

    )
    msg "Available AUR packages:"
    for idx in "${!AUR_CATALOG[@]}"; do
        IFS="::" read -r pkg desc <<< "${AUR_CATALOG[$idx]}"
        printf '  [%d] %-18s %s\n' "$((idx + 1))" "$pkg" "$desc"
    done
    printf '  [0] %-18s %s\n' "ALL" "Install all above AUR packages"

    read -r -p "Enter package numbers to install (multiple numbers separated by space, 0=all, press Enter to skip): " selection_line
    AUR_SELECTIONS=()
    if [ -n "$selection_line" ]; then
        # shellcheck disable=SC2206  # 使用单词分割构建数组
        AUR_SELECTIONS=($selection_line)
    fi

    declare -a AUR_PACKAGES=()
    declare -A AUR_SELECTED_MAP=()
    if [ "${#AUR_SELECTIONS[@]}" -eq 0 ]; then
        msg "No AUR packages selected, skipping installation."
    else
        for sel in "${AUR_SELECTIONS[@]}"; do
            if [ "$sel" = "0" ]; then
                for entry in "${AUR_CATALOG[@]}"; do
                    IFS="::" read -r pkg _ <<< "$entry"
                    if [ -z "${AUR_SELECTED_MAP[$pkg]:-}" ]; then
                        AUR_PACKAGES+=("$pkg")
                        AUR_SELECTED_MAP[$pkg]=1
                    fi
                done
                # 0 表示全选，其余选择无需继续处理
                break
            elif [[ "$sel" =~ ^[0-9]+$ ]]; then
                idx=$((sel - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#AUR_CATALOG[@]}" ]; then
                    IFS="::" read -r pkg _ <<< "${AUR_CATALOG[$idx]}"
                    if [ -z "${AUR_SELECTED_MAP[$pkg]:-}" ]; then
                        AUR_PACKAGES+=("$pkg")
                        AUR_SELECTED_MAP[$pkg]=1
                    fi
                else
                    warn "Number $sel is out of range, ignored."
                fi
            else
                warn "Input $sel is not a valid number, ignored."
            fi
        done
    fi

    # 检查 AUR 软件是否已安装的函数
    # 注意：yay/paru 会以普通用户身份运行，如果需要 sudo 权限会自动提示
    # AUR 包安装在用户目录（~/.cache/yay），不会影响系统目录
    check_and_install_aur() {
        local pkg=$1
        local installed=false
        
        # 检查是否已安装（yay/paru 都支持 -Q 查询）
        if $AUR -Q "$pkg" >/dev/null 2>&1; then
            installed=true
            local pkg_version
            pkg_version=$($AUR -Q "$pkg" 2>/dev/null | head -n1 | awk '{print $2}')
            msg "$pkg is already installed (version: $pkg_version)"
            read -rp "Reinstall $pkg? (y/N): " reinstall_choice
            if [[ ! "$reinstall_choice" =~ ^[Yy]$ ]]; then
                msg "Skipping $pkg (user chose not to reinstall)"
                return 0
            fi
        fi
        
        # 安装或重新安装
        # yay/paru 会以当前用户身份运行（普通用户），如果需要安装到系统目录会自动使用 sudo
        # 但 AUR 包的构建和缓存都在用户目录，不会影响权限
        if [ "$installed" = true ]; then
            msg "Reinstalling $pkg ..."
        else
            msg "Installing $pkg ..."
        fi
        
        # yay -S 会以普通用户身份运行，如果需要 sudo 权限会自动提示
        if ! $AUR -S --noconfirm "$pkg"; then
            warn "$pkg installation failed, please run manually: $AUR -S $pkg"
            track_pkg_failure "$pkg (AUR)"
            return 1
        fi
        return 0
    }

    if [ -n "$AUR" ]; then
        if [ "${#AUR_PACKAGES[@]}" -gt 0 ]; then
            msg "Preparing to install AUR packages: ${AUR_PACKAGES[*]}"
            for aur_pkg in "${AUR_PACKAGES[@]}"; do
                check_and_install_aur "$aur_pkg"
            done
        else
            msg "No AUR packages to install."
        fi
    else
        warn "No usable AUR helper detected (attempted: $selected_helper). Skipping installation."
        if [ "${#AUR_PACKAGES[@]}" -gt 0 ]; then
            warn "Please install yay or paru, then run: yay -S ${AUR_PACKAGES[*]}"
            for aur_pkg in "${AUR_PACKAGES[@]}"; do
                track_pkg_failure "$aur_pkg (AUR)"
            done
        fi
    fi
    return "$aur_failed"
}

step_configure_locales() {
    msg "Configuring locales (en_US primary + zh_CN support)..."
    if ! sudo sed -i '/^#zh_CN\.UTF-8/s/^#//' /etc/locale.gen; then
        warn "Failed to enable zh_CN locale"
        return 1
    fi
    if ! sudo sed -i '/^#en_US\.UTF-8/s/^#//' /etc/locale.gen; then
        warn "Failed to enable en_US locale"
        return 1
    fi
    msg "Generating locale data..."
    if ! sudo locale-gen; then
        warn "locale-gen failed"
        return 1
    fi
    sudo localectl set-locale LANG=en_US.UTF-8 2>/dev/null || true
    if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
        if ! sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config"; then
            mkdir -p "$TARGET_HOME/.config" || return 1
        fi
        echo "LANG=en_US.UTF-8" | sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/locale.conf" > /dev/null
    else
        mkdir -p "$TARGET_HOME/.config"
        echo "LANG=en_US.UTF-8" > "$TARGET_HOME/.config/locale.conf"
    fi
    msg "Locales enabled: en_US.UTF-8 + zh_CN.UTF-8"
    return 0
}

step_sync_configs() {
    local sync_failed=0
    msg "Syncing config/ and suckless/ into ~/.config/ (using copies, not symlinks) ..."
    mkdir -p "$CONFIG_DEST" || return 1
    local config_items=()
    if [ -d "$CONFIG_SRC" ]; then
        while IFS= read -r entry; do
            [ -n "$entry" ] && config_items+=("$entry")
        done < <(find "$CONFIG_SRC" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
    else
        warn "Missing $CONFIG_SRC, skipping additional configs"
        sync_failed=1
    fi
    local item src dest
    for item in "${config_items[@]}"; do
        if [ "$item" = "dwm" ]; then
            src="$DWM_SRC"
        elif [ "$item" = "slstatus" ]; then
            src="$SLSTATUS_SRC"
        elif [ "$item" = "slock" ]; then
            src="$SLOCK_SRC"
        else
            src="$CONFIG_SRC/$item"
        fi
        dest="$CONFIG_DEST/$item"
        if [ ! -e "$src" ]; then
            warn "Missing $src, skipping"
            sync_failed=1
            continue
        fi
        mkdir -p "$(dirname "$dest")" || { sync_failed=1; continue; }
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            if backup_existing_path "$dest"; then
                msg "Backed up existing $dest before syncing"
            else
                warn "Unable to backup $dest, skipping"
                sync_failed=1
                continue
            fi
        fi
        if [ -d "$src" ]; then
            # 目录：复制内容到目标目录
            mkdir -p "$dest" || { sync_failed=1; continue; }
            if cp -a "$src/." "$dest/"; then
                msg "Copied directory $src -> $dest"
            else
                warn "Failed to copy directory $src -> $dest"
                sync_failed=1
            fi
        else
            # 单文件：直接复制
            if cp -a "$src" "$dest"; then
                msg "Copied file $src -> $dest"
            else
                warn "Failed to copy file $src -> $dest"
                sync_failed=1
            fi
        fi
    done
    if [ -d "$SCRIPTS_SRC" ]; then
        local scripts_dest="$CONFIG_DEST/scripts"
        mkdir -p "$(dirname "$scripts_dest")" || { sync_failed=1; }
        if [ -e "$scripts_dest" ] || [ -L "$scripts_dest" ]; then
            if backup_existing_path "$scripts_dest"; then
                msg "Backed up existing $scripts_dest before syncing"
            else
                warn "Unable to backup $scripts_dest, skipping scripts sync"
                sync_failed=1
                continue
            fi
        fi
        mkdir -p "$scripts_dest" || { sync_failed=1; }
        if cp -a "$SCRIPTS_SRC/." "$scripts_dest/"; then
            msg "Copied scripts directory $SCRIPTS_SRC -> $scripts_dest"
        else
            warn "Failed to copy scripts directory $SCRIPTS_SRC -> $scripts_dest"
            sync_failed=1
        fi
    else
        warn "Missing $SCRIPTS_SRC, skipping scripts link"
        sync_failed=1
    fi

    # Ensure fontconfig directory exists and refresh font cache so that custom
    # configs like config/fontconfig/conf.d/50-zh-default.conf take effect.
    if [ -d "$CONFIG_DEST/fontconfig" ]; then
        msg "Fontconfig directory detected at $CONFIG_DEST/fontconfig"
        if command -v fc-cache >/dev/null 2>&1; then
            msg "Refreshing font cache (fc-cache -fv) to apply fontconfig changes..."
            if ! fc-cache -fv; then
                warn "fc-cache failed; you may need to run 'fc-cache -fv' manually."
                sync_failed=1
            fi
        else
            warn "fc-cache command not found; please install fontconfig and run 'fc-cache -fv' manually."
            sync_failed=1
        fi
    fi

    if [ -d "$CONFIG_DEST/scripts" ]; then
        msg "Setting execute bit on scripts/ ..."
        chmod +x "$CONFIG_DEST/scripts/"* 2>/dev/null || true
        if [ ! -x "$CONFIG_DEST/scripts/autostart.sh" ]; then
            warn "autostart.sh missing or not executable, please verify"
            sync_failed=1
        fi
    fi

    if [ -d "$SUCKLESS_SRC" ]; then
        local suckless_dest="$CONFIG_DEST/suckless"
        mkdir -p "$(dirname "$suckless_dest")" || { sync_failed=1; }
        if [ -e "$suckless_dest" ] || [ -L "$suckless_dest" ]; then
            if backup_existing_path "$suckless_dest"; then
                msg "Backed up existing $suckless_dest before syncing"
            else
                warn "Unable to backup $suckless_dest, skipping suckless sync"
                sync_failed=1
                suckless_dest=""
            fi
        fi
        if [ -n "$suckless_dest" ]; then
            mkdir -p "$suckless_dest" || { sync_failed=1; }
            if cp -a "$SUCKLESS_SRC/." "$suckless_dest/"; then
                msg "Copied suckless directory $SUCKLESS_SRC -> $suckless_dest"
            else
                warn "Failed to copy suckless directory $SUCKLESS_SRC -> $suckless_dest"
                sync_failed=1
            fi
        fi
    else
        warn "Missing $SUCKLESS_SRC, skipping suckless link"
        sync_failed=1
    fi
    return "$sync_failed"
}

step_build_suckless() {
    local build_failed=0
    local tool src_dir
    local suckless_tools=(dwm slstatus slock)
    msg "Building ${suckless_tools[*]} ..."
    for tool in "${suckless_tools[@]}"; do
        src_dir="$SUCKLESS_SRC/$tool"
        if [ ! -d "$src_dir" ]; then
            warn "Missing $tool source directory, skipping"
            build_failed=1
            continue
        fi
        if ! (
            cd "$src_dir" &&
            make clean &&
            make &&
            sudo make install
        ); then
            warn "Failed to build $tool"
            build_failed=1
        fi
    done
    return "$build_failed"
}

step_create_dwm_desktop_entry() {
    msg "Creating dwm desktop entry..."
    if ! sudo mkdir -p /usr/share/xsessions; then
        warn "Failed to create /usr/share/xsessions"
        return 1
    fi
    if ! cat << 'EOF' | sudo tee /usr/share/xsessions/dwm.desktop > /dev/null
[Desktop Entry]
Name=dwm
Comment=Dynamic window manager
Exec=$HOME/.config/scripts/autostart.sh
Type=Application
EOF
    then
        warn "Failed to write dwm.desktop"
        return 1
    fi
    return 0
}

step_create_user_files() {
    local user_failed=0
    msg "Writing ~/.xinitrc"
    local XINITRC="$TARGET_HOME/.xinitrc"
    if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
        if ! cat << EOF | sudo -u "$TARGET_USER" tee "$XINITRC" > /dev/null
#!/bin/sh
export LANG=en_US.UTF-8
export XMODIFIERS=@im=fcitx
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx

# Launch unified startup script
exec $TARGET_HOME/.config/scripts/autostart.sh
EOF
        then
            warn "Failed to write $XINITRC"
            return 1
        fi
        chmod +x "$XINITRC"
        chown "$TARGET_USER:$TARGET_USER" "$XINITRC" 2>/dev/null || true
    else
        if ! cat > "$XINITRC" << EOF
#!/bin/sh
export LANG=en_US.UTF-8
export XMODIFIERS=@im=fcitx
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx

# Launch unified startup script
exec $TARGET_HOME/.config/scripts/autostart.sh
EOF
        then
            warn "Failed to write $XINITRC"
            return 1
        fi
        chmod +x "$XINITRC"
    fi

    msg "Writing ~/.xprofile"
    local XPROFILE="$TARGET_HOME/.xprofile"
    if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
        if ! cat << EOF | sudo -u "$TARGET_USER" tee "$XPROFILE" > /dev/null
export LANG=en_US.UTF-8
export XMODIFIERS=@im=fcitx
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx
EOF
        then
            warn "Failed to write $XPROFILE"
            user_failed=1
        fi
        chown "$TARGET_USER:$TARGET_USER" "$XPROFILE" 2>/dev/null || true
    else
        if ! cat > "$XPROFILE" << EOF
export LANG=en_US.UTF-8
export XMODIFIERS=@im=fcitx
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx
EOF
        then
            warn "Failed to write $XPROFILE"
            user_failed=1
        fi
    fi

    if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
        msg "Running as root, target user: $TARGET_USER (HOME: $TARGET_HOME)"
    fi
    if command -v xdg-user-dirs-update >/dev/null 2>&1; then
        if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
            sudo -u "$TARGET_USER" xdg-user-dirs-update || { warn "Cannot execute xdg-user-dirs-update as user $TARGET_USER"; user_failed=1; }
        else
            xdg-user-dirs-update || { warn "xdg-user-dirs-update failed"; user_failed=1; }
        fi
    else
        warn "xdg-user-dirs-update not found, install with: sudo pacman -S xdg-user-dirs"
        user_failed=1
    fi

    local SCREENSHOTS_DIR="$TARGET_HOME/Pictures/Screenshots"
    if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
        sudo -u "$TARGET_USER" mkdir -p "$SCREENSHOTS_DIR" || { warn "Cannot create $SCREENSHOTS_DIR"; user_failed=1; }
    else
        mkdir -p "$SCREENSHOTS_DIR" || { warn "Cannot create $SCREENSHOTS_DIR"; user_failed=1; }
    fi
    msg "Screenshots directory created at $SCREENSHOTS_DIR"

    msg "Creating X server log directory..."
    local XORG_LOG_DIR="$TARGET_HOME/.local/share/xorg"
    if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
        if sudo -u "$TARGET_USER" mkdir -p "$XORG_LOG_DIR"; then
            msg "X server log directory created at $XORG_LOG_DIR (owner: $TARGET_USER)"
        else
            warn "Cannot create X server log directory, will try to create manually and fix permissions"
            mkdir -p "$XORG_LOG_DIR" || { user_failed=1; }
            chown -R "$TARGET_USER:$TARGET_USER" "$XORG_LOG_DIR" 2>/dev/null || true
            chmod 755 "$XORG_LOG_DIR" 2>/dev/null || true
        fi
    else
        mkdir -p "$XORG_LOG_DIR" || { warn "Cannot create $XORG_LOG_DIR"; user_failed=1; }
        msg "X server log directory created at $XORG_LOG_DIR"
    fi

    return "$user_failed"
}

step_create_alacritty_desktop_entry() {
    msg "Creating Alacritty desktop file..."
    local ALACRITTY_DESKTOP_DIR="$TARGET_HOME/.local/share/applications"
    if [ "$EUID" -eq 0 ] && [ -n "$TARGET_USER" ]; then
        sudo -u "$TARGET_USER" mkdir -p "$ALACRITTY_DESKTOP_DIR" || mkdir -p "$ALACRITTY_DESKTOP_DIR"
        if ! cat << 'EOF' | sudo -u "$TARGET_USER" tee "$ALACRITTY_DESKTOP_DIR/alacritty.desktop" > /dev/null
[Desktop Entry]
Name=Alacritty
Comment=Fast GPU Terminal
Exec=alacritty
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF
        then
            warn "Failed to write Alacritty desktop file"
            return 1
        fi
        if [ "$EUID" -eq 0 ]; then
            chown "$TARGET_USER:$TARGET_USER" "$ALACRITTY_DESKTOP_DIR/alacritty.desktop" 2>/dev/null || true
        fi
    else
        mkdir -p "$ALACRITTY_DESKTOP_DIR" || { warn "Cannot create $ALACRITTY_DESKTOP_DIR"; return 1; }
        if ! cat > "$ALACRITTY_DESKTOP_DIR/alacritty.desktop" << 'EOF'
[Desktop Entry]
Name=Alacritty
Comment=Fast GPU Terminal
Exec=alacritty
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF
        then
            warn "Failed to write Alacritty desktop file"
            return 1
        fi
    fi
    return 0
}

step_enable_ly() {
    msg "Enabling ly display manager..."
    sudo systemctl disable getty@tty1.service 2>/dev/null || true
    if ! sudo systemctl enable ly; then
        warn "Failed to enable ly service"
        return 1
    fi
    return 0
}

# === Step registration & execution ===
if [ "$ONLY_CONFIG" = false ]; then
    register_step core_update "System update" step_update_system
    register_step core_packages "Install official packages" step_install_official_packages
    register_step core_locale "Configure locales" step_configure_locales
    register_step core_dwm_desktop "Create dwm desktop entry" step_create_dwm_desktop_entry
    register_step core_enable_ly "Enable ly display manager" step_enable_ly
else
    register_step config_user_setup "Configure user environment (Git/aliases)" step_config_user_setup
    register_step config_aur "Install AUR packages" step_install_aur_packages
    register_step config_sync "Sync configuration files" step_sync_configs
    register_step config_build "Build dwm and slstatus" step_build_suckless
    register_step config_user_files "Create per-user X files" step_create_user_files
    register_step config_alacritty "Create Alacritty desktop file" step_create_alacritty_desktop_entry
fi

run_all_steps
prompt_retry_failed_steps

# === Missing package reminder ===
if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then
    warn "The following packages could not be installed automatically:"
    for pkg in "${MISSING_PACKAGES[@]}"; do
        echo "  - $pkg"
    done
    echo
    echo "Try: sudo pacman -S <package>    or (AUR) yay -S <package>"
fi

# === Final summary ===
# 核心安装通过 --core-install 调用（SKIP_MENU=true），完成后不显示摘要（由主进程处理）
# 配置安装完成后显示完整摘要
if [ "$ONLY_CONFIG" = true ]; then
    # 配置安装完成
    echo -e "\n${GREEN}Configuration installation complete!${NC}\n"
    cat << EOF
Configs synced to ~/.config/ (copied from ./config and ./suckless):
  - ~/.config/alacritty/
  - ~/.config/dunst/dunstrc
  - ~/.config/sxhkd/sxhkdrc
  - ~/.config/scripts/autostart.sh  <- launches dunst, sxhkd, picom, slstatus, fcitx5
  - ~/.config/suckless/ (dwm/slstatus/slock sources, git repo copy)

User files created:
  - ~/.xinitrc + ~/.xprofile -> start autostart.sh
  - ~/.local/share/applications/alacritty.desktop
  - ~/.local/share/xorg/ (X server log directory)

Notes:
  - Tweak dwm: vim ./suckless/dwm/config.h -> make install
  - Wallpaper: ~/.config/walls/eva.jpg
  - Input method toggle: Ctrl + Space
  - How to launch dwm: Reboot -> ly login manager -> pick dwm, or run startx
EOF
elif [ "$SKIP_MENU" = true ]; then
    # 核心安装完成（通过 --core-install 调用），只显示简要信息
    # 详细摘要由主进程（菜单模式）处理
    echo -e "\n${GREEN}Core installation complete!${NC}\n"
    msg "Core installation completed."
else
    # 菜单模式下，核心安装完成后（这种情况不应该发生，因为核心安装会通过 --core-install 调用）
    echo -e "\n${GREEN}Core installation complete!${NC}\n"
    msg "Core installation completed."
fi

if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
    echo
    warn "The following steps are still failing and need manual attention:"
    for id in "${FAILED_STEPS[@]}"; do
        echo "  - ${STEP_DESC["$id"]}"
    done
fi
