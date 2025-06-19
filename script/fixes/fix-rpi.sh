#!/bin/bash
#========================================================================================================================
# 树莓派设备编译问题修复脚本
# 功能: 修复树莓派特有的编译问题，主要是imx219摄像头补丁错误
# 用法: ./fix-rpi.sh [error_type]
#========================================================================================================================

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共函数
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
fi

# 修复树莓派摄像头补丁问题
fix_rpi_camera_patches() {
    log_info "修复树莓派摄像头补丁问题..."
    
    local fixes_applied=()
    
    # 删除有问题的摄像头相关补丁
    local problematic_patches=(
        "target/linux/bcm27xx/patches-6.6/*imx219*"
        "target/linux/bcm27xx/patches-6.6/*ov5647*"
        "target/linux/bcm27xx/patches-6.6/*950-04*"
        "target/linux/bcm27xx/patches-6.6/*media*"
        "target/linux/bcm27xx/patches-6.6/*camera*"
    )
    
    for pattern in "${problematic_patches[@]}"; do
        if ls $pattern 2>/dev/null >/dev/null; then
            rm -f $pattern
            log_info "删除摄像头补丁: $pattern"
            fixes_applied+=("删除摄像头补丁")
        fi
    done
    
    show_fix_summary "${fixes_applied[@]}"
    return 0
}

# 修复树莓派内核配置
fix_rpi_kernel_config() {
    log_info "修复树莓派内核配置..."
    
    local fixes_applied=()
    
    # 查找所有bcm27xx配置文件
    local config_files=($(find target/linux/bcm27xx/ -name "config-*" -type f))
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            log_info "处理配置文件: $config_file"
            backup_file_if_exists "$config_file"
            
            # 禁用所有摄像头和媒体相关配置
            local media_configs=(
                "VIDEO_IMX219"
                "VIDEO_OV5647"
                "VIDEO_DEV"
                "VIDEO_V4L2"
                "MEDIA_SUPPORT"
                "MEDIA_CAMERA_SUPPORT"
                "VIDEO_BCM2835"
                "SND_BCM2835_SOC_I2S"
            )
            
            for config in "${media_configs[@]}"; do
                disable_kernel_config "$config" "$config_file" "$config"
            done
            
            # 添加树莓派特定的稳定配置
            cat >> "$config_file" << 'EOF'

# 树莓派编译问题修复配置
# CONFIG_MEDIA_SUPPORT is not set
# CONFIG_VIDEO_DEV is not set
# CONFIG_VIDEO_V4L2 is not set
# CONFIG_VIDEO_IMX219 is not set
# CONFIG_VIDEO_OV5647 is not set
# CONFIG_SND_BCM2835_SOC_I2S is not set

# 树莓派稳定性优化
CONFIG_ARM64_PAGE_SHIFT=12
CONFIG_ARM64_CONT_SHIFT=4
EOF
            
            fixes_applied+=("修复内核配置: $(basename $config_file)")
        fi
    done
    
    show_fix_summary "${fixes_applied[@]}"
    return 0
}

# 删除树莓派冲突包
remove_rpi_conflicting_packages() {
    log_info "删除树莓派冲突包..."
    
    local fixes_applied=()
    
    # 可能冲突的包目录
    local conflicting_packages=(
        "package/kernel/linux/modules/video.mk"
        "package/libs/libcamera"
        "package/multimedia/gstreamer1"
    )
    
    for pkg in "${conflicting_packages[@]}"; do
        if safe_remove "$pkg" "冲突包 $(basename $pkg)"; then
            fixes_applied+=("删除冲突包: $(basename $pkg)")
        fi
    done
    
    show_fix_summary "${fixes_applied[@]}"
    return 0
}

# 优化树莓派编译配置
optimize_rpi_build_config() {
    log_info "优化树莓派编译配置..."
    
    local fixes_applied=()
    
    if [ -f ".config" ]; then
        backup_file_if_exists ".config"
        
        # 确保基础树莓派配置正确
        add_config_if_missing "CONFIG_TARGET_bcm27xx=y" ".config" "bcm27xx目标"
        add_config_if_missing "CONFIG_TARGET_bcm27xx_bcm2711=y" ".config" "bcm2711架构"
        
        # 禁用可能有问题的功能
        disable_kernel_config "VIDEO_DEV" ".config" "视频设备"
        disable_kernel_config "MEDIA_SUPPORT" ".config" "媒体支持"
        disable_kernel_config "SOUND" ".config" "声音支持(可选)"
        
        # 启用必要的硬件支持
        add_config_if_missing "CONFIG_PACKAGE_kmod-thermal=y" ".config" "温度监控"
        add_config_if_missing "CONFIG_PACKAGE_rng-tools=y" ".config" "随机数生成器"
        
        fixes_applied+=("优化树莓派编译配置")
    fi
    
    show_fix_summary "${fixes_applied[@]}"
    return 0
}

# 修复树莓派Makefile
fix_rpi_makefile() {
    log_info "检查树莓派Makefile..."
    
    local makefile="target/linux/bcm27xx/Makefile"
    local fixes_applied=()
    
    if [ -f "$makefile" ]; then
        backup_file_if_exists "$makefile"
        
        # 检查内核版本配置
        local kernel_version=$(grep "KERNEL_PATCHVER" "$makefile" | cut -d'=' -f2 | tr -d ' ')
        log_info "当前内核版本: $kernel_version"
        
        # 如果是6.6版本，考虑降级到更稳定的版本
        if [[ "$kernel_version" == "6.6" ]]; then
            if [ -d "target/linux/bcm27xx/patches-6.1" ]; then
                log_warning "建议降级到内核6.1版本以获得更好的稳定性"
                log_info "可手动修改 $makefile 中的 KERNEL_PATCHVER := 6.1"
            fi
        fi
        
        fixes_applied+=("检查Makefile配置")
    fi
    
    show_fix_summary "${fixes_applied[@]}"
    return 0
}

# 清理树莓派编译缓存
clean_rpi_build_cache() {
    log_info "清理树莓派编译缓存..."
    
    local cache_dirs=(
        "build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711"
        "staging_dir/target-aarch64_cortex-a72_musl"
        "tmp/info/.packageinfo-kernel_*"
    )
    
    for cache_dir in "${cache_dirs[@]}"; do
        if [ -e "$cache_dir" ]; then
            rm -rf "$cache_dir"
            log_info "清理缓存: $cache_dir"
        fi
    done
    
    return 0
}

# 树莓派自动修复
auto_fix_rpi() {
    log_info "自动修复树莓派编译问题..."
    
    local all_fixes=()
    
    # 执行所有修复步骤
    if fix_rpi_camera_patches; then
        all_fixes+=("摄像头补丁修复")
    fi
    
    if fix_rpi_kernel_config; then
        all_fixes+=("内核配置修复")
    fi
    
    if remove_rpi_conflicting_packages; then
        all_fixes+=("冲突包清理")
    fi
    
    if optimize_rpi_build_config; then
        all_fixes+=("编译配置优化")
    fi
    
    if fix_rpi_makefile; then
        all_fixes+=("Makefile检查")
    fi
    
    clean_rpi_build_cache
    all_fixes+=("编译缓存清理")
    
    echo ""
    log_success "树莓派自动修复完成"
    show_fix_summary "${all_fixes[@]}"
    
    return 0
}

# 验证树莓派修复
verify_rpi_fix() {
    log_info "验证树莓派修复结果..."
    
    # 检查问题补丁是否已删除
    if ! ls target/linux/bcm27xx/patches-6.6/*imx219* 2>/dev/null >/dev/null; then
        log_success "有问题的imx219补丁已删除"
    else
        log_warning "imx219补丁仍然存在"
    fi
    
    # 检查内核配置
    local config_files=($(find target/linux/bcm27xx/ -name "config-*" -type f))
    for config_file in "${config_files[@]}"; do
        if grep -q "# CONFIG_VIDEO_IMX219 is not set" "$config_file"; then
            log_success "视频配置已正确禁用: $(basename $config_file)"
        fi
    done
    
    return 0
}

# 显示树莓派修复建议
show_rpi_recommendations() {
    echo ""
    log_info "树莓派编译建议："
    echo "=================================="
    echo "  1. 已禁用摄像头功能避免编译失败"
    echo "  2. 如需摄像头，请在编译成功后手动启用"
    echo "  3. 建议使用32GB以上SD卡"
    echo "  4. 首次编译时间可能较长"
    echo ""
    echo "  后续操作:"
    echo "    1. make clean"
    echo "    2. make defconfig"
    echo "    3. make -j4 (树莓派推荐4线程)"
    echo "=================================="
}

# 主函数
main() {
    local error_type="${1:-auto}"
    
    log_info "开始树莓派修复，错误类型: $error_type"
    
    case "$error_type" in
        "imx219"|"camera")
            fix_rpi_camera_patches
            fix_rpi_kernel_config
            ;;
        "kernel")
            fix_rpi_kernel_config
            fix_rpi_makefile
            ;;
        "config")
            optimize_rpi_build_config
            ;;
        "auto"|*)
            auto_fix_rpi
            ;;
    esac
    
    # 验证修复结果
    verify_rpi_fix
    
    # 显示修复建议
    show_rpi_recommendations
    
    # 生成修复报告
    generate_fix_report "rpi_4b" "$error_type" "摄像头补丁修复" "内核配置优化" "编译缓存清理"
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi