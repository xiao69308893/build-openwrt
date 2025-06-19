#!/bin/bash
#========================================================================================================================
# X86设备编译问题修复脚本
# 功能: 修复X86设备特有的编译问题，主要是udebug/ucode依赖问题
# 用法: ./fix-x86.sh [error_type]
#========================================================================================================================

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共函数
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
fi

# X86设备特定的修复
fix_x86_udebug_issue() {
    log_info "修复X86设备udebug/ucode依赖问题..."
    
    local fixes_applied=()
    
    # 方案1: 删除有问题的udebug包
    if [ -d "package/libs/udebug" ]; then
        log_warning "删除有问题的udebug包"
        safe_remove "package/libs/udebug" "udebug包目录"
        fixes_applied+=("删除udebug包")
    fi
    
    # 方案2: 在配置中禁用udebug相关包
    if [ -f ".config" ]; then
        backup_file_if_exists ".config"
        
        # 禁用udebug相关配置
        disable_kernel_config "PACKAGE_udebug" ".config" "udebug包"
        disable_kernel_config "PACKAGE_libudebug" ".config" "libudebug包"
        disable_kernel_config "PACKAGE_udebug_cli" ".config" "udebug-cli包"
        
        fixes_applied+=("禁用udebug配置")
    fi
    
    # 方案3: 确保ucode包正确安装
    if ! [ -d "package/utils/ucode" ] && ! [ -d "feeds/packages/lang/ucode" ]; then
        log_info "安装ucode包..."
        ./scripts/feeds update packages
        ./scripts/feeds install ucode
        
        if [ $? -eq 0 ]; then
            fixes_applied+=("安装ucode包")
        fi
    fi
    
    # 方案4: 清理相关编译缓存
    clean_build_cache "build_dir/target-x86_64_musl/udebug*"
    fixes_applied+=("清理udebug编译缓存")
    
    show_fix_summary "${fixes_applied[@]}"
    return 0
}

# X86设备通用优化
optimize_x86_config() {
    log_info "应用X86设备通用优化..."
    
    local fixes_applied=()
    
    # 删除可能冲突的包
    local conflicting_packages=(
        "package/utils/ucode"
        "package/utils/fbtest"
    )
    
    for pkg in "${conflicting_packages[@]}"; do
        if [ -d "$pkg" ]; then
            safe_remove "$pkg" "冲突包 $(basename $pkg)"
            fixes_applied+=("删除冲突包: $(basename $pkg)")
        fi
    done
    
    # 优化X86配置
    if [ -f ".config" ]; then
        backup_file_if_exists ".config"
        
        # 确保关键X86配置启用
        add_config_if_missing "CONFIG_TARGET_x86=y" ".config" "X86目标平台"
        add_config_if_missing "CONFIG_TARGET_x86_64=y" ".config" "X86_64架构"
        
        # 禁用可能有问题的功能
        disable_kernel_config "VIDEO_DEV" ".config" "视频设备支持"
        disable_kernel_config "MEDIA_SUPPORT" ".config" "媒体设备支持"
        
        fixes_applied+=("优化X86内核配置")
    fi
    
    show_fix_summary "${fixes_applied[@]}"
    return 0
}

# X86设备feeds修复
fix_x86_feeds() {
    log_info "修复X86设备feeds问题..."
    
    local fixes_applied=()
    
    # 清理feeds缓存
    if [ -d "feeds" ]; then
        log_info "清理feeds缓存..."
        ./scripts/feeds clean
        fixes_applied+=("清理feeds缓存")
    fi
    
    # 重新配置feeds
    if [ -f "feeds.conf.default" ]; then
        backup_file_if_exists "feeds.conf.default"
        
        # 确保基础feeds配置正确
        cat > feeds.conf.default << 'EOF'
src-git packages https://github.com/coolsnowwolf/packages
src-git luci https://github.com/coolsnowwolf/luci
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
EOF
        
        fixes_applied+=("重置feeds配置")
    fi
    
    # 更新并重新安装feeds
    update_feeds && reinstall_feeds
    if [ $? -eq 0 ]; then
        fixes_applied+=("重新安装feeds")
    fi
    
    show_fix_summary "${fixes_applied[@]}"
    return 0
}

# 主函数
main() {
    local error_type="${1:-auto}"
    
    log_info "开始X86设备修复，错误类型: $error_type"
    
    case "$error_type" in
        "udebug")
            fix_x86_udebug_issue
            ;;
        "feeds")
            fix_x86_feeds
            ;;
        "auto"|*)
            # 自动修复所有常见问题
            fix_x86_udebug_issue
            optimize_x86_config
            ;;
    esac
    
    log_success "X86设备修复完成"
    
    # 生成修复报告
    generate_fix_report "x86_64" "$error_type" "udebug修复" "配置优化"
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi