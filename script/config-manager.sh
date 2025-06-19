#!/bin/bash
#========================================================================================================================
# OpenWrt 配置管理脚本
# 功能: 管理不同源码分支的配置文件，确保编译配置的一致性和正确性
# 用法: ./config-manager.sh [操作] [参数...]
#========================================================================================================================

# 脚本版本
VERSION="1.0.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置目录
CONFIG_BASE_DIR="config"

# 支持的源码分支
SUPPORTED_BRANCHES=("openwrt-main" "lede-master" "immortalwrt-master" "Lienol-master")

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${PURPLE}[DEBUG]${NC} $1"; }

# 显示标题
show_header() {
    echo -e "${CYAN}"
    echo "========================================================================================================================="
    echo "                                    🔧 OpenWrt 配置管理脚本 v${VERSION}"
    echo "========================================================================================================================="
    echo -e "${NC}"
}

# 显示帮助信息
show_help() {
    cat << EOF
${CYAN}使用方法:${NC}
  $0 [操作] [选项...]

${CYAN}操作:${NC}
  init                初始化配置目录结构
  validate            验证配置文件的完整性
  sync                同步配置文件
  backup              备份配置文件
  restore             恢复配置文件
  create              创建新的分支配置
  update              更新现有配置
  list                列出所有配置

${CYAN}选项:${NC}
  -b, --branch        指定源码分支
  -f, --force         强制执行操作
  -v, --verbose       详细输出
  -h, --help          显示帮助信息
  --version           显示版本信息

${CYAN}示例:${NC}
  # 初始化配置目录
  $0 init
  
  # 验证所有配置
  $0 validate
  
  # 验证特定分支配置
  $0 validate -b lede-master
  
  # 创建新分支配置
  $0 create -b custom-branch
  
  # 备份配置
  $0 backup

${CYAN}配置文件说明:${NC}
  config/[分支名]/
  ├── config                 # 编译配置文件
  ├── feeds.conf.default     # feeds源配置
  ├── diy-part1.sh          # 第一阶段自定义脚本
  └── diy-part2.sh          # 第二阶段自定义脚本
EOF
}

# 检查配置目录是否存在
check_config_dir() {
    if [ ! -d "$CONFIG_BASE_DIR" ]; then
        log_warning "配置目录不存在，将自动创建"
        mkdir -p "$CONFIG_BASE_DIR"
    fi
}

# 初始化配置目录结构
init_config() {
    log_info "初始化配置目录结构..."
    
    check_config_dir
    
    for branch in "${SUPPORTED_BRANCHES[@]}"; do
        local branch_dir="$CONFIG_BASE_DIR/$branch"
        
        if [ ! -d "$branch_dir" ]; then
            log_info "创建分支配置目录: $branch"
            mkdir -p "$branch_dir"
            
            # 创建默认配置文件
            create_default_config "$branch"
            create_default_feeds_conf "$branch"
            create_default_diy_scripts "$branch"
        else
            log_debug "分支配置目录已存在: $branch"
        fi
    done
    
    log_success "配置目录初始化完成"
}

# 创建默认编译配置
create_default_config() {
    local branch="$1"
    local config_file="$CONFIG_BASE_DIR/$branch/config"
    
    if [ -f "$config_file" ]; then
        return 0
    fi
    
    log_debug "创建默认配置文件: $config_file"
    
    cat > "$config_file" << 'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y

# 根文件系统配置
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_IMAGES_GZIP=y

# 基础系统包
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y

# 网络组件
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl-openssl=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_luci-app-opkg=y

# 常用工具
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_nano=y

# 禁用IPv6（可选）
# CONFIG_IPV6 is not set
EOF
}

# 创建默认feeds配置
create_default_feeds_conf() {
    local branch="$1"
    local feeds_file="$CONFIG_BASE_DIR/$branch/feeds.conf.default"
    
    if [ -f "$feeds_file" ]; then
        return 0
    fi
    
    log_debug "创建默认feeds配置: $feeds_file"
    
    case "$branch" in
        "openwrt-main")
            cat > "$feeds_file" << 'EOF'
src-git packages https://git.openwrt.org/feed/packages.git
src-git luci https://git.openwrt.org/project/luci.git
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
EOF
            ;;
        "lede-master")
            cat > "$feeds_file" << 'EOF'
src-git packages https://github.com/coolsnowwolf/packages
src-git luci https://github.com/coolsnowwolf/luci
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
src-git freifunk https://github.com/freifunk/openwrt-packages.git
#src-git video https://github.com/openwrt/video.git
#src-git targets https://github.com/openwrt/targets.git
#src-git oldpackages http://git.openwrt.org/packages.git
#src-link custom /usr/src/openwrt/custom-feed
EOF
            ;;
        "immortalwrt-master"|"Lienol-master")
            cat > "$feeds_file" << 'EOF'
src-git packages https://github.com/immortalwrt/packages.git
src-git luci https://github.com/immortalwrt/luci.git
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
EOF
            ;;
    esac
}

# 创建默认DIY脚本
create_default_diy_scripts() {
    local branch="$1"
    local diy_p1_file="$CONFIG_BASE_DIR/$branch/diy-part1.sh"
    local diy_p2_file="$CONFIG_BASE_DIR/$branch/diy-part2.sh"
    
    # 创建diy-part1.sh
    if [ ! -f "$diy_p1_file" ]; then
        log_debug "创建第一阶段DIY脚本: $diy_p1_file"
        cat > "$diy_p1_file" << 'EOF'
#!/bin/bash
#========================================================================================================================
# OpenWrt 第一阶段自定义脚本
# 功能: 在更新feeds之前执行的自定义操作
# 执行时机: feeds update 之前
#========================================================================================================================

echo "🔧 执行第一阶段自定义脚本..."

# 添加自定义feeds源（示例）
# sed -i '$a src-git custom https://github.com/user/custom-packages' feeds.conf.default

# 删除冲突的包（示例）
# rm -rf package/lean/luci-theme-argon

echo "✅ 第一阶段自定义脚本执行完成"
EOF
        chmod +x "$diy_p1_file"
    fi
    
    # 创建diy-part2.sh
    if [ ! -f "$diy_p2_file" ]; then
        log_debug "创建第二阶段DIY脚本: $diy_p2_file"
        cat > "$diy_p2_file" << 'EOF'
#!/bin/bash
#========================================================================================================================
# OpenWrt 第二阶段自定义脚本
# 功能: 在安装feeds之后执行的自定义操作
# 执行时机: feeds install 之后，make defconfig 之前
#========================================================================================================================

echo "🔧 执行第二阶段自定义脚本..."

# 修改默认IP地址（示例）
# sed -i 's/192.168.1.1/192.168.50.1/g' package/base-files/files/bin/config_generate

# 修改默认主题（示例）
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 修改主机名（示例）
# sed -i 's/OpenWrt/MyRouter/g' package/base-files/files/bin/config_generate

# 修改默认时区（示例）
# sed -i "s/'UTC'/'CST-8'/g" package/base-files/files/bin/config_generate

echo "✅ 第二阶段自定义脚本执行完成"
EOF
        chmod +x "$diy_p2_file"
    fi
}

# 验证配置文件
validate_config() {
    local target_branch="$1"
    local verbose="$2"
    local errors=0
    
    log_info "验证配置文件..."
    
    # 确定要验证的分支
    local branches_to_check=()
    if [ -n "$target_branch" ]; then
        if [[ " ${SUPPORTED_BRANCHES[@]} " =~ " ${target_branch} " ]]; then
            branches_to_check=("$target_branch")
        else
            log_error "不支持的分支: $target_branch"
            return 1
        fi
    else
        branches_to_check=("${SUPPORTED_BRANCHES[@]}")
    fi
    
    for branch in "${branches_to_check[@]}"; do
        local branch_dir="$CONFIG_BASE_DIR/$branch"
        
        [ "$verbose" = true ] && log_info "验证分支: $branch"
        
        # 检查目录是否存在
        if [ ! -d "$branch_dir" ]; then
            log_error "分支配置目录不存在: $branch_dir"
            ((errors++))
            continue
        fi
        
        # 检查必需的文件
        local required_files=("config" "feeds.conf.default" "diy-part1.sh" "diy-part2.sh")
        for file in "${required_files[@]}"; do
            local file_path="$branch_dir/$file"
            
            if [ ! -f "$file_path" ]; then
                log_error "缺少配置文件: $file_path"
                ((errors++))
            else
                [ "$verbose" = true ] && log_debug "✓ $file_path"
                
                # 验证脚本文件的可执行权限
                if [[ "$file" == *.sh ]] && [ ! -x "$file_path" ]; then
                    log_warning "脚本文件缺少执行权限: $file_path"
                    chmod +x "$file_path"
                    log_info "已自动添加执行权限: $file_path"
                fi
                
                # 验证文件内容
                validate_file_content "$file_path" "$file" "$verbose"
            fi
        done
    done
    
    if [ $errors -eq 0 ]; then
        log_success "配置验证通过"
        return 0
    else
        log_error "发现 $errors 个配置错误"
        return 1
    fi
}

# 验证文件内容
validate_file_content() {
    local file_path="$1"
    local file_name="$2"
    local verbose="$3"
    
    case "$file_name" in
        "config")
            # 验证config文件的基本配置项
            if ! grep -q "CONFIG_TARGET_" "$file_path"; then
                log_warning "配置文件缺少目标平台配置: $file_path"
            fi
            ;;
        "feeds.conf.default")
            # 验证feeds配置文件
            if [ ! -s "$file_path" ]; then
                log_warning "feeds配置文件为空: $file_path"
            fi
            ;;
        "diy-part1.sh"|"diy-part2.sh")
            # 验证脚本文件
            if ! head -n1 "$file_path" | grep -q "#!/bin/bash"; then
                log_warning "脚本文件缺少shebang: $file_path"
            fi
            ;;
    esac
}

# 备份配置文件
backup_config() {
    local backup_dir="config_backup_$(date +%Y%m%d_%H%M%S)"
    
    log_info "备份配置文件到: $backup_dir"
    
    if [ ! -d "$CONFIG_BASE_DIR" ]; then
        log_error "配置目录不存在，无法备份"
        return 1
    fi
    
    cp -r "$CONFIG_BASE_DIR" "$backup_dir"
    
    # 创建备份信息文件
    cat > "$backup_dir/backup_info.txt" << EOF
配置备份信息
=============
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份目录: $backup_dir
原始目录: $CONFIG_BASE_DIR
脚本版本: $VERSION

包含的分支配置:
$(ls -1 "$backup_dir" | grep -v backup_info.txt)

恢复方法:
rm -rf $CONFIG_BASE_DIR
mv $backup_dir $CONFIG_BASE_DIR
EOF
    
    log_success "配置备份完成: $backup_dir"
}

# 恢复配置文件
restore_config() {
    local backup_dir="$1"
    
    if [ -z "$backup_dir" ]; then
        log_error "请指定备份目录"
        echo "可用的备份目录:"
        ls -1d config_backup_* 2>/dev/null || echo "  (无可用备份)"
        return 1
    fi
    
    if [ ! -d "$backup_dir" ]; then
        log_error "备份目录不存在: $backup_dir"
        return 1
    fi
    
    log_warning "此操作将覆盖当前配置，请确认继续 [y/N]"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消"
        return 0
    fi
    
    log_info "恢复配置从: $backup_dir"
    
    # 备份当前配置
    if [ -d "$CONFIG_BASE_DIR" ]; then
        mv "$CONFIG_BASE_DIR" "${CONFIG_BASE_DIR}_temp_$(date +%s)"
    fi
    
    # 恢复配置
    cp -r "$backup_dir" "$CONFIG_BASE_DIR"
    rm -f "$CONFIG_BASE_DIR/backup_info.txt"
    
    log_success "配置恢复完成"
}

# 创建新分支配置
create_branch_config() {
    local new_branch="$1"
    local base_branch="$2"
    
    if [ -z "$new_branch" ]; then
        log_error "请指定新分支名称"
        return 1
    fi
    
    local new_branch_dir="$CONFIG_BASE_DIR/$new_branch"
    
    if [ -d "$new_branch_dir" ]; then
        log_error "分支配置已存在: $new_branch"
        return 1
    fi
    
    log_info "创建新分支配置: $new_branch"
    
    # 选择基础模板
    if [ -n "$base_branch" ] && [ -d "$CONFIG_BASE_DIR/$base_branch" ]; then
        log_info "基于现有分支创建: $base_branch"
        cp -r "$CONFIG_BASE_DIR/$base_branch" "$new_branch_dir"
    else
        log_info "基于默认模板创建"
        mkdir -p "$new_branch_dir"
        create_default_config "$new_branch"
        create_default_feeds_conf "$new_branch"
        create_default_diy_scripts "$new_branch"
    fi
    
    log_success "新分支配置创建完成: $new_branch_dir"
}

# 同步配置文件
sync_config() {
    local source_branch="$1"
    local target_branch="$2"
    
    if [ -z "$source_branch" ] || [ -z "$target_branch" ]; then
        log_error "请指定源分支和目标分支"
        echo "用法: $0 sync --source <源分支> --target <目标分支>"
        return 1
    fi
    
    local source_dir="$CONFIG_BASE_DIR/$source_branch"
    local target_dir="$CONFIG_BASE_DIR/$target_branch"
    
    if [ ! -d "$source_dir" ]; then
        log_error "源分支配置不存在: $source_dir"
        return 1
    fi
    
    log_info "同步配置: $source_branch -> $target_branch"
    
    # 备份目标配置
    if [ -d "$target_dir" ]; then
        mv "$target_dir" "${target_dir}_backup_$(date +%s)"
    fi
    
    # 复制配置
    cp -r "$source_dir" "$target_dir"
    
    log_success "配置同步完成"
}

# 列出所有配置
list_config() {
    local verbose="$1"
    
    log_info "配置列表:"
    
    if [ ! -d "$CONFIG_BASE_DIR" ]; then
        log_warning "配置目录不存在"
        return 1
    fi
    
    echo -e "\n${CYAN}分支配置:${NC}"
    printf "%-20s %-10s %-15s %s\n" "分支名称" "状态" "最后修改" "文件数量"
    echo "------------------------------------------------------------"
    
    for branch_dir in "$CONFIG_BASE_DIR"/*; do
        if [ -d "$branch_dir" ]; then
            local branch_name=$(basename "$branch_dir")
            local status="❌ 不完整"
            local file_count=0
            local last_modified=""
            
            # 检查配置完整性
            local required_files=("config" "feeds.conf.default" "diy-part1.sh" "diy-part2.sh")
            local missing_files=0
            
            for file in "${required_files[@]}"; do
                if [ -f "$branch_dir/$file" ]; then
                    ((file_count++))
                else
                    ((missing_files++))
                fi
            done
            
            if [ $missing_files -eq 0 ]; then
                status="✅ 完整"
            fi
            
            # 获取最后修改时间
            if [ $file_count -gt 0 ]; then
                last_modified=$(find "$branch_dir" -type f -exec stat -c %Y {} \; 2>/dev/null | sort -n | tail -1)
                if [ -n "$last_modified" ]; then
                    last_modified=$(date -d "@$last_modified" '+%Y-%m-%d %H:%M')
                fi
            fi
            
            printf "%-20s %-10s %-15s %d/4\n" "$branch_name" "$status" "$last_modified" "$file_count"
            
            # 详细信息
            if [ "$verbose" = true ]; then
                echo "  配置文件:"
                for file in "${required_files[@]}"; do
                    if [ -f "$branch_dir/$file" ]; then
                        echo "    ✓ $file"
                    else
                        echo "    ❌ $file"
                    fi
                done
                echo
            fi
        fi
    done
}

# 更新配置文件
update_config() {
    local branch="$1"
    local force="$2"
    
    if [ -z "$branch" ]; then
        log_error "请指定要更新的分支"
        return 1
    fi
    
    local branch_dir="$CONFIG_BASE_DIR/$branch"
    
    if [ ! -d "$branch_dir" ]; then
        log_error "分支配置不存在: $branch"
        return 1
    fi
    
    log_info "更新分支配置: $branch"
    
    # 检查现有文件
    local required_files=("config" "feeds.conf.default" "diy-part1.sh" "diy-part2.sh")
    
    for file in "${required_files[@]}"; do
        local file_path="$branch_dir/$file"
        
        if [ ! -f "$file_path" ] || [ "$force" = true ]; then
            log_info "更新文件: $file"
            
            case "$file" in
                "config")
                    create_default_config "$branch"
                    ;;
                "feeds.conf.default")
                    create_default_feeds_conf "$branch"
                    ;;
                "diy-part1.sh"|"diy-part2.sh")
                    create_default_diy_scripts "$branch"
                    ;;
            esac
        else
            log_debug "文件已存在，跳过: $file"
        fi
    done
    
    log_success "配置更新完成"
}

# 主函数
main() {
    local operation=""
    local branch=""
    local source_branch=""
    local target_branch=""
    local backup_dir=""
    local base_branch=""
    local force=false
    local verbose=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            init|validate|sync|backup|restore|create|update|list)
                operation="$1"
                shift
                ;;
            -b|--branch)
                branch="$2"
                shift 2
                ;;
            --source)
                source_branch="$2"
                shift 2
                ;;
            --target)
                target_branch="$2"
                shift 2
                ;;
            --backup-dir)
                backup_dir="$2"
                shift 2
                ;;
            --base)
                base_branch="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                echo "配置管理脚本 版本 $VERSION"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                echo "使用 $0 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
    
    # 显示标题
    show_header
    
    # 执行操作
    case "$operation" in
        "init")
            init_config
            ;;
        "validate")
            validate_config "$branch" "$verbose"
            ;;
        "sync")
            sync_config "$source_branch" "$target_branch"
            ;;
        "backup")
            backup_config
            ;;
        "restore")
            restore_config "$backup_dir"
            ;;
        "create")
            create_branch_config "$branch" "$base_branch"
            ;;
        "update")
            update_config "$branch" "$force"
            ;;
        "list")
            list_config "$verbose"
            ;;
        "")
            log_error "请指定操作"
            echo "使用 $0 --help 查看帮助信息"
            exit 1
            ;;
        *)
            log_error "未知操作: $operation"
            exit 1
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi