#!/bin/bash

# Arch Linux DWL 桌面环境安装脚本（手动启动，无 Display Manager）
# 基于 2025 年 10 月 23 日的 Arch Linux Wiki 和 TonyBTW DWL 教程
# 优化：交互式菜单（dialog），安装 DWL、foot、wmenu、slstatus、桌面工具
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

# 编译和配置 DWL
configure_dwl() {
    echo "配置 DWL 和相关工具..." | tee -a "$LOGFILE"
    su syaofox -c '
        cd ~
        git clone https://codeberg.org/dwl/dwl.git
        cd dwl
        wget https://codeberg.org/dwl/community/raw/branch/master/bar.diff -O patches/bar.diff
        patch -i patches/bar.diff
        cat << EOT > config.def.h
/* See LICENSE file for copyright and license details. */
#include <X11/XF86keysym.h>

/* appearance */
static const int sloppyfocus               = 1;  /* focus follows mouse */
static const int bypass_surface_visibility = 0;  /* 1 means idle inhibitors will disable idle tracking even for visible windows */
static const unsigned int borderpx         = 1;  /* border pixel of windows */
static const float bordercolor[]          = {0.5, 0.5, 0.5, 1.0};
static const float focuscolor[]            = {1.0, 0.0, 0.0, 1.0};
static const float urgentcolor[]           = {0.0, 1.0, 0.0, 1.0};
static const char *fonts[]                 = {"JetBrainsMono Nerd Font Mono:style=Bold:size=16"};
static const char *barfont                = "JetBrainsMono Nerd Font Mono:style=Bold:size=16";
/* tagging - tagcount must be no greater than 31 */
static const int tagcount = 9;

/* logging */
static const int log_level = WLR_DEBUG;

/* startup */
static const char *const autostart[] = {
    NULL /* terminate */
};

/* commands */
static const char *termcmd[]  = { "foot", NULL };
static const char *wmenucmd[] = { "wmenu-run", "-f", "JetBrainsMono Nerd Font 16", "-l", "10", NULL };

static const Key keys[] = {
    /* Note that Shift changes certain key codes: c -> C, 2 -> at, etc. */
    /* modifier                  key                 function        argument */
    { MODKEY,                    XKB_KEY_d,          spawn,          {.v = wmenucmd} },
    { MODKEY,                    XKB_KEY_Return,     spawn,          {.v = termcmd} },
    { MODKEY,                    XKB_KEY_q,          killclient,     {0} },
    { MODKEY,                    XKB_KEY_j,          focusstack,     {.i = +1} },
    { MODKEY,                    XKB_KEY_k,          focusstack,     {.i = -1} },
    { MODKEY,                    XKB_KEY_h,          setmfact,       {.f = -0.05} },
    { MODKEY,                    XKB_KEY_l,          setmfact,       {.f = +0.05} },
    { MODKEY,                    XKB_KEY_i,          incnmaster,     {.i = +1} },
    { MODKEY,                    XKB_KEY_p,          incnmaster,     {.i = -1} },
    { MODKEY,                    XKB_KEY_e,          togglefullscreen, {0} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_space,      togglefloating, {0} },
    { MODKEY,                    XKB_KEY_t,          setlayout,      {.v = &layouts[0]} }, /* tile */
    { MODKEY,                    XKB_KEY_f,          setlayout,      {.v = &layouts[1]} }, /* floating */
    { MODKEY,                    XKB_KEY_m,          setlayout,      {.v = &layouts[2]} }, /* monocle */
    { MODKEY,                    XKB_KEY_space,      setlayout,      {0} },
    { MODKEY,                    XKB_KEY_b,          togglebar,      {0} },
    { MODKEY,                    XKB_KEY_Tab,        view,           {0} },
    { MODKEY,                    XKB_KEY_1,          view,           {.ui = 1 << 0} },
    { MODKEY,                    XKB_KEY_2,          view,           {.ui = 1 << 1} },
    { MODKEY,                    XKB_KEY_3,          view,           {.ui = 1 << 2} },
    { MODKEY,                    XKB_KEY_4,          view,           {.ui = 1 << 3} },
    { MODKEY,                    XKB_KEY_5,          view,           {.ui = 1 << 4} },
    { MODKEY,                    XKB_KEY_6,          view,           {.ui = 1 << 5} },
    { MODKEY,                    XKB_KEY_7,          view,           {.ui = 1 << 6} },
    { MODKEY,                    XKB_KEY_8,          view,           {.ui = 1 << 7} },
    { MODKEY,                    XKB_KEY_9,          view,           {.ui = 1 << 8} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_1,          tag,            {.ui = 1 << 0} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_2,          tag,            {.ui = 1 << 1} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_3,          tag,            {.ui = 1 << 2} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_4,          tag,            {.ui = 1 << 3} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_5,          tag,            {.ui = 1 << 4} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_6,          tag,            {.ui = 1 << 5} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_7,          tag,            {.ui = 1 << 6} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_8,          tag,            {.ui = 1 << 7} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_9,          tag,            {.ui = 1 << 8} },
    { MODKEY,                    XKB_KEY_0,          view,           {.ui = ~0} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_parenright, tag,            {.ui = ~0} },
    { MODKEY,                    XKB_KEY_comma,      focusmon,       {.i = -1} },
    { MODKEY,                    XKB_KEY_period,     focusmon,       {.i = +1} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_less,       tagmon,         {.i = -1} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_greater,    tagmon,         {.i = +1} },
    { MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Q,          quit,           {0} },
    { WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT, XKB_KEY_BackSpace, quit, {1} },
};

static const Button buttons[] = {
    { MODKEY, BTN_LEFT,   movemouse,  {0} },
    { MODKEY, BTN_RIGHT,  resizemouse, {0} },
};

static const MonitorRule monrules[] = {
    /* name       mfact  nmaster scale layout       rotate/reflect                x    y */
    { "eDP-1",    0.55,  1,      1,    &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,   -1,  -1 },
};

static const int repeat_rate = 35;
static const int repeat_delay = 200;

/* layout(s) */
static const Layout layouts[] = {
    /* symbol     arrange function */
    { "[]=",      tile },
    { "><>",      NULL },    /* no layout function means floating behavior */
    { "[M]",      monocle },
};

/* monitors */
static const MonitorRule monrules[] = {
    /* name       mfact nmaster scale layout       rotate/reflect                x    y  */
    { NULL,       0.55, 1,      1,    &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,   -1, -1 },
};

/* keyboard */
static const struct xkb_rule_names xkb_rules = {
    /* can specify fields: rules, model, layout, variant, options */
    /* example:
    .options = "ctrl:nocaps",
    */
    .options = NULL,
};

static const int repeat_rate = 25;
static const int repeat_delay = 600;

/* Trackpad */
static const int tap_to_click = 1;
static const int tap_and_drag = 1;
static const int drag_lock = 1;
static const int natural_scrolling = 0;
static const int disable_while_typing = 1;
static const int left_handed = 0;
static const int middle_button_emulation = 0;
/* You can choose between:
LIBINPUT_CONFIG_SCROLL_NO_SCROLL
LIBINPUT_CONFIG_SCROLL_2FG
LIBINPUT_CONFIG_SCROLL_EDGE
LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN
*/
static const enum libinput_config_scroll_method scroll_method = LIBINPUT_CONFIG_SCROLL_2FG;

/* You can choose between:
LIBINPUT_CONFIG_CLICK_METHOD_NONE
LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS
LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER
*/
static const enum libinput_config_click_method click_method = LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS;

/* You can choose between:
LIBINPUT_CONFIG_SEND_DEFAULT
LIBINPUT_CONFIG_SEND_VERTICAL
LIBINPUT_CONFIG_SEND_HORIZONTAL
*/
static const enum libinput_config_send_events_mode events_mode = LIBINPUT_CONFIG_SEND_DEFAULT;

/* You can choose between:
LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT
LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE
*/
static const enum libinput_config_accel_profile accel_profile = LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
static const double accel_speed = 0.0;

/* You can choose between:
LIBINPUT_CONFIG_TAP_MAP_LRM -- left, right, middle
LIBINPUT_CONFIG_TAP_MAP_LMR -- left, middle, right
*/
static const enum libinput_config_tap_button_map button_map = LIBINPUT_CONFIG_TAP_MAP_LRM;

/* If you want to use the windows key for MODKEY, use: */
#define MODKEY WLR_MODIFIER_LOGO
EOT
        rm -f config.h
        sudo make clean install
    '
    dialog --msgbox "DWL 编译和配置完成。" 6 30
    echo -e "${GREEN}DWL 编译和配置完成。${NC}" | tee -a "$LOGFILE"
}

# 配置 slstatus、壁纸和截图脚本
configure_extras() {
    echo "配置 slstatus、壁纸和截图脚本..." | tee -a "$LOGFILE"
    su syaofox -c '
        cd ~
        git clone https://git.suckless.org/slstatus
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
    # 添加截图快捷键到 DWL 配置
    su syaofox -c '
        cd ~/dwl
        sed -i "/{ MODKEY, *XKB_KEY_q, *killclient, *{0} }/a \
        \    { MODKEY,                    XKB_KEY_s,          spawn,          {.v = (const char *[]){\"~/screenshot.sh\", NULL}} }," config.def.h
        rm -f config.h
        sudo make clean install
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