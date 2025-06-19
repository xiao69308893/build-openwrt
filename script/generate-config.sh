#!/bin/bash
#========================================================================================================================
# OpenWrt 配置生成脚本 (修复版本)
# 功能: 根据设备和插件需求自动生成完整的.config文件
# 修复: 添加 --runtime-config 参数支持，与 build-orchestrator.sh 兼容
# 用法: ./generate-config.sh [设备] [插件列表] [选项...]
#========================================================================================================================

# 脚本版本
SCRIPT_VERSION="3.0.1-fixed"

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 运行时配置支持（新增）
RUNTIME_CONFIG_FILE=""

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${PURPLE}[DEBUG]${NC} $1"; }

# 从运行时配置读取值（新增功能）
get_runtime_config_value() {
    local key="$1"
    local default="$2"
    
    if [ -n "$RUNTIME_CONFIG_FILE" ] && [ -f "$RUNTIME_CONFIG_FILE" ]; then
        local value=$(jq -r "$key" "$RUNTIME_CONFIG_FILE" 2>/dev/null)
        if [ "$value" != "null" ] && [ -n "$value" ]; then
            echo "$value"
        else
            echo "$default"
        fi
    else
        echo "$default"
    fi
}

# 显示标题
show_header() {
    echo -e "${CYAN}"
    echo "========================================================================================================================="
    echo "                                    📝 OpenWrt 配置生成脚本 v${SCRIPT_VERSION} (兼容版)"
    echo "                                        智能配置生成 | 自动修复功能"
    echo "========================================================================================================================="
    echo -e "${NC}"
}

# 显示帮助信息（添加了 --runtime-config 参数说明）
show_help() {
    cat << EOF
${CYAN}使用方法:${NC}
  $0 [设备] [插件列表] [选项...]

${CYAN}支持的设备:${NC}
  x86_64              x86_64架构设备
  xiaomi_4a_gigabit   小米4A千兆版
  newifi_d2           新路由D2
  rpi_4b              树莓派4B
  nanopi_r2s          NanoPi R2S

${CYAN}选项:${NC}
  --auto-fix          启用自动修复功能
  --no-validate       跳过配置验证
  --dry-run           仅显示配置，不写入文件
  --verbose           详细输出模式
  --runtime-config    运行时配置文件 (新增)
  -h, --help          显示帮助信息
  --version           显示版本信息

${CYAN}示例:${NC}
  # 基础使用
  $0 x86_64                                        # 生成x86_64基础配置
  $0 x86_64 "luci-app-ssr-plus"                   # 生成x86_64配置+SSR插件
  $0 rpi_4b "luci-app-samba4,luci-theme-argon"    # 树莓派配置+多插件
  
  # 高级选项
  $0 x86_64 "luci-app-ssr-plus" --auto-fix        # 启用自动修复
  $0 x86_64 "luci-app-ssr-plus" --dry-run         # 预览配置
  
  # 与编排器配合使用
  $0 --runtime-config /tmp/runtime.json x86_64 "luci-app-ssr-plus" --auto-fix

${CYAN}支持的插件:${NC}
  luci-app-ssr-plus   SSR Plus+ 科学上网
  luci-app-passwall   PassWall 科学上网
  luci-app-openclash  OpenClash 代理工具
  luci-app-samba4     Samba4 文件共享
  luci-app-aria2      Aria2 下载工具
  luci-theme-argon    Argon 主题
  luci-theme-material Material 主题
  ... 更多插件请参考插件数据库

${CYAN}输出文件:${NC}
  .config             OpenWrt编译配置文件
  feeds.conf.default  Feeds源配置文件 (如果不存在)
EOF
}

# 检查环境
check_environment() {
    # 检查jq工具
    if ! command -v jq &> /dev/null; then
        log_warning "未找到jq工具，部分功能可能受限"
    fi
    
    # 检查当前目录是否合适
    if [ ! -f "Config.in" ] && [ ! -f "Makefile" ] && [ ! -d "target" ]; then
        log_warning "当前目录可能不是OpenWrt源码根目录"
    fi
    
    return 0
}

# 获取设备配置
get_device_config() {
    local device="$1"
    
    log_debug "生成设备配置: $device"
    
    case "$device" in
        "x86_64")
            cat << 'EOF'

# ======================== X86_64 设备配置 ========================
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y

# 引导配置
CONFIG_GRUB_IMAGES=y
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_VDI_IMAGES=y
CONFIG_VMDK_IMAGES=y

# 分区大小
CONFIG_TARGET_KERNEL_PARTSIZE=32
CONFIG_TARGET_ROOTFS_PARTSIZE=500
CONFIG_TARGET_IMAGES_GZIP=y

# X86网卡驱动
CONFIG_PACKAGE_kmod-e1000=y
CONFIG_PACKAGE_kmod-e1000e=y
CONFIG_PACKAGE_kmod-igb=y
CONFIG_PACKAGE_kmod-igbvf=y
CONFIG_PACKAGE_kmod-ixgbe=y
CONFIG_PACKAGE_kmod-r8125=y
CONFIG_PACKAGE_kmod-r8168=y
CONFIG_PACKAGE_kmod-vmxnet3=y

# EFI 支持
CONFIG_GRUB_EFI_IMAGES=y

EOF
            ;;
            
        "xiaomi_4a_gigabit")
            cat << 'EOF'

# ======================== 小米4A千兆版 设备配置 ========================
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt7621=y
CONFIG_TARGET_ramips_mt7621_DEVICE_xiaomi_mi-router-4a-gigabit=y

# 图像压缩
CONFIG_TARGET_IMAGES_GZIP=y

# MT7621无线驱动
CONFIG_PACKAGE_kmod-mt7603=y
CONFIG_PACKAGE_kmod-mt76x2=y
CONFIG_PACKAGE_wpad-basic-wolfssl=y

EOF
            ;;
            
        "newifi_d2")
            cat << 'EOF'

# ======================== 新路由D2 设备配置 ========================
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt7621=y
CONFIG_TARGET_ramips_mt7621_DEVICE_d-team_newifi-d2=y

# 图像压缩
CONFIG_TARGET_IMAGES_GZIP=y

# MT7621无线和USB驱动
CONFIG_PACKAGE_kmod-mt7603=y
CONFIG_PACKAGE_kmod-mt76x2=y
CONFIG_PACKAGE_kmod-usb3=y
CONFIG_PACKAGE_wpad-basic-wolfssl=y

EOF
            ;;
            
        "rpi_4b")
            cat << 'EOF'

# ======================== 树莓派4B 设备配置 ========================
CONFIG_TARGET_bcm27xx=y
CONFIG_TARGET_bcm27xx_bcm2711=y
CONFIG_TARGET_bcm27xx_bcm2711_DEVICE_rpi-4=y

# 分区大小
CONFIG_TARGET_KERNEL_PARTSIZE=64
CONFIG_TARGET_ROOTFS_PARTSIZE=2048
CONFIG_TARGET_IMAGES_GZIP=y

# 树莓派特定驱动
CONFIG_PACKAGE_kmod-usb-net-asix=y
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
CONFIG_PACKAGE_bcm27xx-gpu-fw=y
CONFIG_PACKAGE_bcm27xx-userland=y

EOF
            ;;
            
        "nanopi_r2s")
            cat << 'EOF'

# ======================== NanoPi R2S 设备配置 ========================
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r2s=y

# 分区大小
CONFIG_TARGET_KERNEL_PARTSIZE=32
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
CONFIG_TARGET_IMAGES_GZIP=y

# R2S特定驱动
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y

EOF
            ;;
            
        *)
            log_warning "未知设备类型: $device，使用通用配置"
            cat << 'EOF'

# ======================== 通用设备配置 ========================
# 请根据实际设备修改目标配置
CONFIG_TARGET_IMAGES_GZIP=y

EOF
            ;;
    esac
}

# 获取通用配置
get_common_config() {
    cat << 'EOF'
# ======================== 编译选项 ========================

# 编译工具链
CONFIG_MAKE_TOOLCHAIN=y
CONFIG_IB=y
CONFIG_SDK=y

# 文件系统
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y

# 构建设置
CONFIG_SIGNED_PACKAGES=y
CONFIG_SIGNATURE_CHECK=y
CONFIG_BUILD_LOG=y

# ======================== 内核配置 ========================

# IPv6支持
CONFIG_IPV6=y
CONFIG_KERNEL_IPV6=y
CONFIG_PACKAGE_ipv6helper=y

# 文件系统支持
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-ntfs=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_ntfs-3g=y

# USB支持
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y

# 网络优化
CONFIG_PACKAGE_kmod-tcp-bbr=y
CONFIG_PACKAGE_kmod-tun=y

# ======================== 基础软件包 ========================
# LuCI Web界面
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lib-base=y
CONFIG_PACKAGE_luci-lib-ip=y
CONFIG_PACKAGE_luci-lib-jsonc=y
CONFIG_PACKAGE_luci-lib-nixio=y
CONFIG_PACKAGE_luci-mod-admin-full=y
CONFIG_PACKAGE_luci-mod-network=y
CONFIG_PACKAGE_luci-mod-status=y
CONFIG_PACKAGE_luci-mod-system=y
CONFIG_PACKAGE_luci-proto-ipv6=y
CONFIG_PACKAGE_luci-proto-ppp=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y

# 核心系统组件
CONFIG_PACKAGE_base-files=y
CONFIG_PACKAGE_busybox=y
CONFIG_PACKAGE_ca-certificates=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_dropbear=y
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_nftables=y
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_odhcp6c=y
CONFIG_PACKAGE_odhcpd-ipv6only=y
CONFIG_PACKAGE_ppp=y
CONFIG_PACKAGE_ppp-mod-pppoe=y

# 网络工具
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_iptables-legacy=y

# 系统工具
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_vim-fuller=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_unzip=y
CONFIG_PACKAGE_gzip=y
CONFIG_PACKAGE_tar=y

# USB和存储支持
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y

# 网络基础依赖
CONFIG_PACKAGE_kmod-nf-nathelper=y
CONFIG_PACKAGE_kmod-nf-nathelper-extra=y
CONFIG_PACKAGE_kmod-ipt-raw=y
CONFIG_PACKAGE_kmod-ipt-tproxy=y

EOF
}

# 获取插件配置
get_plugin_config() {
    local plugin="$1"
    
    log_debug "生成插件配置: $plugin"
    
    case "$plugin" in
        "luci-app-ssr-plus")
            cat << 'EOF'

# ======================== SSR Plus+ 插件 ========================
CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Client=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Simple_Obfs=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray_Plugin=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NaiveProxy=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Redsocks2=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client=y
CONFIG_PACKAGE_luci-i18n-ssr-plus-zh-cn=y

# SSR Plus+ 相关依赖
CONFIG_PACKAGE_shadowsocks-libev-config=y
CONFIG_PACKAGE_shadowsocks-libev-ss-local=y
CONFIG_PACKAGE_shadowsocks-libev-ss-redir=y
CONFIG_PACKAGE_dns2socks=y
CONFIG_PACKAGE_dns2tcp=y
CONFIG_PACKAGE_microsocks=y
CONFIG_PACKAGE_pdnsd-alt=y
CONFIG_PACKAGE_tcping=y
CONFIG_PACKAGE_resolveip=y

EOF
            ;;
            
        "luci-app-passwall")
            cat << 'EOF'

# ======================== PassWall 插件 ========================
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy=y
CONFIG_PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Brook=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ChinaDNS_NG=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Haproxy=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_NaiveProxy=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Simple_Obfs=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Plus=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y
CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y

EOF
            ;;
            
        "luci-app-openclash")
            cat << 'EOF'

# ======================== OpenClash 插件 ========================
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-i18n-openclash-zh-cn=y

# OpenClash 相关依赖
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_coreutils-nohup=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ca-certificates=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_libcap=y
CONFIG_PACKAGE_libcap-bin=y
CONFIG_PACKAGE_ruby=y
CONFIG_PACKAGE_ruby-yaml=y
CONFIG_PACKAGE_kmod-tun=y

EOF
            ;;
            
        "luci-app-samba4")
            cat << 'EOF'

# ======================== Samba4 文件共享 ========================
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y
CONFIG_PACKAGE_samba4-libs=y
CONFIG_PACKAGE_samba4-server=y

EOF
            ;;
            
        "luci-app-aria2")
            cat << 'EOF'

# ======================== Aria2 下载器 ========================
CONFIG_PACKAGE_luci-app-aria2=y
CONFIG_PACKAGE_luci-i18n-aria2-zh-cn=y
CONFIG_PACKAGE_aria2=y
CONFIG_PACKAGE_ariang=y
EOF
            ;;
            
        "luci-app-adbyby-plus")
            cat << 'EOF'

# ======================== ADByby Plus+ 广告过滤 ========================
CONFIG_PACKAGE_luci-app-adbyby-plus=y
CONFIG_PACKAGE_luci-i18n-adbyby-plus-zh-cn=y
CONFIG_PACKAGE_adbyby=y
EOF
            ;;
            
        "luci-app-adguardhome")
            cat << 'EOF'

# ======================== AdGuard Home ========================
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_luci-i18n-adguardhome-zh-cn=y
CONFIG_PACKAGE_adguardhome=y
EOF
            ;;
            
        "luci-app-wol")
            cat << 'EOF'

# ======================== 网络唤醒 ========================
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_luci-i18n-wol-zh-cn=y
CONFIG_PACKAGE_etherwake=y
EOF
            ;;
            
        *)
            log_warning "未知插件: $plugin，生成基本配置"
            echo ""
            echo "# 未知插件配置: $plugin"
            echo "CONFIG_PACKAGE_${plugin}=y"
            
            cat << 'EOF'

EOF
            ;;
            
        "luci-theme-argon")
            cat << 'EOF'

# ======================== Argon 主题 ========================
CONFIG_PACKAGE_luci-theme-argon=y

EOF
            ;;
            
        "luci-theme-material")
            cat << 'EOF'

# ======================== Material 主题 ========================
CONFIG_PACKAGE_luci-theme-material=y

EOF
            ;;
            
        "luci-app-netdata")
            cat << 'EOF'

# ======================== Netdata 系统监控 ========================
CONFIG_PACKAGE_luci-app-netdata=y
CONFIG_PACKAGE_luci-i18n-netdata-zh-cn=y
CONFIG_PACKAGE_netdata=y

EOF
            ;;
            
        *)
            log_warning "未知插件: $plugin，将添加基础配置"
            cat << EOF

# ======================== 自定义插件: $plugin ========================
CONFIG_PACKAGE_$plugin=y

EOF
            ;;
    esac
}

# 应用自动修复
apply_auto_fixes() {
    local device="$1"
    local auto_fix="$2"
    
    if [ "$auto_fix" != true ]; then
        log_debug "自动修复功能未启用"
        return 0
    fi
    
    log_info "开始应用自动修复..."
    
    # 确保修复脚本存在且可执行
    local main_fix_script="$SCRIPT_DIR/fixes/fix-build-issues.sh"
    
    if [ ! -f "$main_fix_script" ]; then
        log_warning "主修复脚本不存在: $main_fix_script"
        return 1
    fi
    
    chmod +x "$main_fix_script"
    
    # 执行自动修复
    log_info "执行设备特定修复: $device"
    if "$main_fix_script" "$device" "auto"; then
        log_success "自动修复完成"
        return 0
    else
        log_warning "自动修复执行时遇到问题，但继续处理"
        return 0
    fi
}

# 验证配置内容
validate_config_content() {
    local config_content="$1"
    
    log_info "验证配置内容..."
    
    local issues=()
    
    # 检查基本配置
    if ! echo "$config_content" | grep -q "CONFIG_TARGET_"; then
        issues+=("缺少目标平台配置")
    fi
    
    if ! echo "$config_content" | grep -q "CONFIG_PACKAGE_luci=y"; then
        issues+=("缺少LuCI界面")
    fi
    
    if ! echo "$config_content" | grep -q "CONFIG_PACKAGE_base-files=y"; then
        issues+=("缺少核心基础包")
    fi

     # 设备特定验证
    case "$device" in
        "x86_64")
            if ! echo "$config_content" | grep -q "CONFIG_TARGET_x86_64=y"; then
                issues+=("X86_64配置不正确")
            fi
            ;;
        "rpi_4b")
            if ! echo "$config_content" | grep -q "CONFIG_TARGET_bcm27xx=y"; then
                issues+=("树莓派配置不正确")
            fi
            ;;
    esac
    
    if [ ${#issues[@]} -gt 0 ]; then
        log_warning "配置验证发现问题:"
        for issue in "${issues[@]}"; do
            log_warning "  - $issue"
        done
        return 1
    else
        log_success "配置验证通过"
        return 0
    fi
}

# 生成完整配置
generate_full_config() {
    local device="$1"
    local plugins="$2"
    local auto_fix="$3"
    
    log_info "生成完整配置 - 设备: $device"
    
    # 配置文件头
    local config_content=""
    config_content+="# ========================================================================================================================
# OpenWrt 编译配置文件 (自动生成)
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 生成工具: generate-config.sh v${SCRIPT_VERSION}
# 目标设备: $device
# 选择插件: ${plugins:-无}
# 自动修复: $auto_fix
# ========================================================================================================================"$'\n'
    
    # 设备配置
    config_content+="$(get_device_config "$device")"
    
    # 通用配置
    config_content+="$(get_common_config)"
    
    # 插件配置
    if [ -n "$plugins" ]; then
        log_info "处理插件列表: $plugins"
        
        # 解析插件列表
        IFS=',' read -ra plugin_array <<< "$plugins"
        
        for plugin in "${plugin_array[@]}"; do
            # 清理插件名称（去除空格）
            plugin=$(echo "$plugin" | xargs)
            
            if [ -n "$plugin" ]; then
                config_content+="$(get_plugin_config "$plugin")"
            fi
        done
    else
        log_info "未指定插件，仅生成基础配置"
    fi
    
    # 配置文件尾
    config_content+="
# ======================== 配置文件结束 ========================
# 注意事项:
# 1. 首次编译前请执行: make menuconfig 检查配置
# 2. 建议使用: make -j\$(nproc) V=s 进行编译
# 3. 如遇到问题，可使用 --auto-fix 选项重新生成
# 4. 更多信息请参考: https://openwrt.org/
# ========================================================================================================================"
    
    echo "$config_content"
}

# 检测潜在问题
detect_potential_issues() {
    local device="$1"
    local plugins="$2"
    
    log_info "检测潜在问题..."
    
    local warnings=()
    
    # 检查插件冲突
    if [[ "$plugins" == *"ssr-plus"* ]] && [[ "$plugins" == *"passwall"* ]]; then
        warnings+=("SSR Plus+ 和 PassWall 可能存在冲突")
    fi
    
    if [[ "$plugins" == *"ssr-plus"* ]] && [[ "$plugins" == *"openclash"* ]]; then
        warnings+=("SSR Plus+ 和 OpenClash 可能存在冲突")
    fi
    
    # 检查设备兼容性
    if [[ "$device" == "xiaomi_4a_gigabit" ]] && [[ "$plugins" == *"openclash"* ]]; then
        warnings+=("小米4A千兆版存储空间有限，OpenClash可能无法正常运行")
    fi
    
    # 显示警告
    if [ ${#warnings[@]} -gt 0 ]; then
        log_warning "检测到潜在问题:"
        for warning in "${warnings[@]}"; do
            log_warning "  - $warning"
        done
        echo ""
    fi
}

# 主函数（修改了参数解析部分）
main() {
    local device=""
    local plugins=""
    local output_file=".config"
    local auto_fix=false
    local validate=true
    local dry_run=false
    local verbose=false
    local runtime_config=""  # 新增：支持运行时配置
    
    # 解析命令行参数（添加了 --runtime-config 处理）
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto-fix)
                auto_fix=true
                shift
                ;;
            --no-validate)
                validate=false
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --runtime-config)  # 新增：支持运行时配置参数
                runtime_config="$2"
                RUNTIME_CONFIG_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version)
                echo "generate-config.sh v${SCRIPT_VERSION}"
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                echo "使用 --help 查看帮助信息"
                exit 1
                ;;
            *)
                if [ -z "$device" ]; then
                    device="$1"
                elif [ -z "$plugins" ]; then
                    plugins="$1"
                elif [ -z "$output_file" ] || [ "$output_file" = ".config" ]; then
                    output_file="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 显示标题
    show_header
    
    # 如果提供了运行时配置，读取相关设置（新增功能）
    if [ -n "$RUNTIME_CONFIG_FILE" ]; then
        log_debug "使用运行时配置: $RUNTIME_CONFIG_FILE"
        
        # 从运行时配置读取设置
        if [ "$verbose" = false ]; then
            local runtime_verbose=$(get_runtime_config_value '.verbose_mode' 'false')
            if [ "$runtime_verbose" = "true" ]; then
                verbose=true
            fi
        fi
        
        if [ "$auto_fix" = false ]; then
            local runtime_auto_fix=$(get_runtime_config_value '.auto_fix_enabled' 'false')
            if [ "$runtime_auto_fix" = "true" ]; then
                auto_fix=true
            fi
        fi
    fi
    
    # 检查必需参数
    if [ -z "$device" ]; then
        log_error "请指定设备类型"
        echo "使用 --help 查看帮助信息"
        exit 1
    fi
    
    # 检查环境
    if ! check_environment; then
        if [ "$auto_fix" != true ]; then
            log_error "环境检查失败，请使用 --auto-fix 选项或手动修复"
            exit 1
        fi
    fi
    
    # 详细输出模式
    if [ "$verbose" = true ]; then
        log_info "运行参数:"
        log_info "  设备: $device"
        log_info "  插件: ${plugins:-无}"
        log_info "  输出: $output_file"
        log_info "  自动修复: $auto_fix"
        log_info "  验证: $validate"
        log_info "  预览模式: $dry_run"
        log_info "  运行时配置: ${RUNTIME_CONFIG_FILE:-无}"
        echo ""
        
        # 检测潜在问题
        detect_potential_issues "$device" "$plugins"
    fi
    
    # 应用自动修复（在生成配置之前）
    if [ "$auto_fix" = true ]; then
        apply_auto_fixes "$device" "$auto_fix"
    fi
    
    # 生成配置
    log_info "开始生成配置文件..."
    local config_content=$(generate_full_config "$device" "$plugins" "$auto_fix")
    
    # 验证配置
    if [ "$validate" = true ]; then
        if ! validate_config_content "$config_content"; then
            if [ "$auto_fix" = true ]; then
                log_info "尝试自动修复配置问题..."
                # 可以在这里添加配置修复逻辑
            else
                log_error "配置验证失败，请使用 --auto-fix 选项或手动修复"
                exit 1
            fi
        fi
    fi
    
    # 输出配置
    if [ "$dry_run" = true ]; then
        log_info "预览模式 - 生成的配置内容:"
        echo "=========================================="
        echo "$config_content"
        echo "=========================================="
        log_info "预览完成，未写入文件"
    else
        # 写入配置文件
        echo "$config_content" > "$output_file"
        
        if [ $? -eq 0 ]; then
            log_success "配置文件生成成功: $output_file"
            
            # 显示文件信息
            local file_size=$(wc -l < "$output_file")
            local file_bytes=$(stat -c%s "$output_file" 2>/dev/null || echo "未知")
            log_info "文件信息: $file_size 行, $file_bytes 字节"
            
            # 显示配置摘要
            if [ "$verbose" = true ]; then
                log_info "配置摘要:"
                local target_count=$(grep -c "CONFIG_TARGET_" "$output_file" || echo "0")
                local package_count=$(grep -c "CONFIG_PACKAGE_.*=y" "$output_file" || echo "0")
                log_info "  目标配置: $target_count 项"
                log_info "  包配置: $package_count 项"
                
                echo ""
                log_info "后续步骤:"
                log_info "  1. 执行 feeds update && feeds install -a"
                log_info "  2. 执行 make menuconfig 检查配置"
                log_info "  3. 执行 make -j\$(nproc) V=s 开始编译"
            fi
        else
            log_error "配置文件写入失败"
            exit 1
        fi
    fi
    
    log_success "配置生成完成"
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi