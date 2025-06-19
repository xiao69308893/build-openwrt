#!/bin/bash
#========================================================================================================================
# udebug错误专项修复脚本
# 功能: 专门修复 "ucode_include_dir-NOTFOUND" 错误
# 用法: ./fix-udebug.sh [device]
#========================================================================================================================

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共函数
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
fi

# 修复方案1: 删除udebug包
fix_method_remove_udebug() {
    log_info "方案1: 删除udebug包"
    
    local removed=false
    
    # 删除udebug包目录
    if safe_remove "package/libs/udebug" "udebug包目录"; then
        removed=true
    fi
    
    # 删除编译缓存
    local udebug_cache_dirs=(
        "build_dir/target-*/udebug*"
        "staging_dir/target-*/pkginfo/udebug*"
        "tmp/info/.packageinfo-libs_udebug"
    )
    
    for cache_dir in "${udebug_cache_dirs[@]}"; do
        if ls $cache_dir 2>/dev/null >/dev/null; then
            rm -rf $cache_dir
            log_info "清理udebug缓存: $cache_dir"
            removed=true
        fi
    done
    
    return $removed
}

# 修复方案2: 安装ucode依赖
fix_method_install_ucode() {
    log_info "方案2: 确保ucode包正确安装"
    
    local installed=false
    
    # 检查ucode是否已安装
    local ucode_paths=(
        "package/utils/ucode"
        "package/libs/ucode"
        "feeds/packages/lang/ucode"
        "feeds/packages/utils/ucode"
    )
    
    local ucode_found=false
    for path in "${ucode_paths[@]}"; do
        if [ -d "$path" ]; then
            log_info "找到ucode包: $path"
            ucode_found=true
            break
        fi
    done
    
    if [ "$ucode_found" = false ]; then
        log_info "ucode包未找到，尝试安装..."
        
        # 更新feeds
        ./scripts/feeds update packages
        
        # 安装ucode
        ./scripts/feeds install ucode
        
        if [ $? -eq 0 ]; then
            log_success "ucode包安装成功"
            installed=true
        else
            log_error "ucode包安装失败"
        fi
    else
        log_info "ucode包已存在"
        installed=true
    fi
    
    return $installed
}

# 修复方案3: 修复udebug依赖关系
fix_method_fix_dependencies() {
    log_info "方案3: 修复udebug依赖关系"
    
    local udebug_makefile="package/libs/udebug/Makefile"
    
    if [ -f "$udebug_makefile" ]; then
        backup_file_if_exists "$udebug_makefile"
        
        # 检查是否已有ucode依赖
        if ! grep -q "DEPENDS.*ucode" "$udebug_makefile"; then
            log_info "添加ucode依赖到udebug Makefile"
            
            # 在DEPENDS行添加ucode依赖
            sed -i '/DEPENDS:=/s/$/ +libucode/' "$udebug_makefile"
            
            # 如果没有DEPENDS行，添加一个
            if ! grep -q "DEPENDS:=" "$udebug_makefile"; then
                sed -i '/define Package\/udebug/a\\tDEPENDS:=+libucode' "$udebug_makefile"
            fi
            
            log_success "udebug依赖关系已修复"
            return 0
        else
            log_info "udebug已有ucode依赖"
            return 0
        fi
    else
        log_warning "udebug Makefile不存在"
        return 1
    fi
}

# 修复方案4: 禁用udebug配置
fix_method_disable_udebug() {
    log_info "方案4: 在编译配置中禁用udebug"
    
    if [ -f ".config" ]; then
        backup_file_if_exists ".config"
        
        # 禁用所有udebug相关配置
        local udebug_configs=(
            "PACKAGE_udebug"
            "PACKAGE_libudebug"
            "PACKAGE_udebug_cli"
            "PACKAGE_udebugd"
        )
        
        for config in "${udebug_configs[@]}"; do
            disable_kernel_config "$config" ".config" "$config"
        done
        
        log_success "udebug配置已禁用"
        return 0
    else
        log_warning ".config文件不存在"
        return 1
    fi
}

# 修复方案5: 创建临时ucode头文件
fix_method_create_temp_ucode() {
    log_info "方案5: 创建临时ucode头文件"
    
    local ucode_include_dir="staging_dir/target-*/usr/include/ucode"
    
    # 创建目录结构
    mkdir -p staging_dir/target-*/usr/include/ucode 2>/dev/null || true
    
    # 创建基本的ucode头文件
    cat > staging_dir/target-*/usr/include/ucode/ucode.h 2>/dev/null << 'EOF' || true
#ifndef __UCODE_H__
#define __UCODE_H__

/* 临时ucode头文件，用于解决编译依赖问题 */

typedef struct uc_vm uc_vm_t;
typedef struct uc_value uc_value_t;

#endif /* __UCODE_H__ */
EOF
    
    if [ $? -eq 0 ]; then
        log_success "临时ucode头文件已创建"
        return 0
    else
        log_warning "无法创建临时ucode头文件"
        return 1
    fi
}

# 自动修复udebug问题
auto_fix_udebug() {
    log_info "自动修复udebug/ucode依赖问题..."
    
    local fixes_applied=()
    local success=false
    
    # 按优先级尝试各种修复方案
    
    # 优先尝试删除udebug包（最简单有效）
    if fix_method_remove_udebug; then
        fixes_applied+=("删除udebug包")
        success=true
    fi
    
    # 尝试禁用udebug配置
    if fix_method_disable_udebug; then
        fixes_applied+=("禁用udebug配置")
        success=true
    fi
    
    # 如果用户想保留udebug，尝试修复依赖
    if [ "$success" = false ]; then
        if fix_method_install_ucode; then
            fixes_applied+=("安装ucode依赖")
            
            if fix_method_fix_dependencies; then
                fixes_applied+=("修复udebug依赖关系")
                success=true
            fi
        fi
    fi
    
    # 最后的备用方案
    if [ "$success" = false ]; then
        if fix_method_create_temp_ucode; then
            fixes_applied+=("创建临时ucode头文件")
            success=true
        fi
    fi
    
    # 清理编译缓存
    clean_build_cache "build_dir/target-*/udebug*"
    fixes_applied+=("清理udebug编译缓存")
    
    show_fix_summary "${fixes_applied[@]}"
    
    if [ "$success" = true ]; then
        log_success "udebug问题修复完成"
        return 0
    else
        log_error "udebug问题修复失败"
        return 1
    fi
}

# 验证udebug修复
verify_udebug_fix() {
    log_info "验证udebug修复结果..."
    
    # 检查udebug包是否已删除或禁用
    if [ ! -d "package/libs/udebug" ]; then
        log_success "udebug包已删除"
        return 0
    fi
    
    # 检查配置是否已禁用
    if [ -f ".config" ]; then
        if grep -q "# CONFIG_PACKAGE_udebug is not set" .config; then
            log_success "udebug配置已禁用"
            return 0
        fi
    fi
    
    # 检查ucode依赖是否满足
    local ucode_paths=(
        "package/utils/ucode"
        "feeds/packages/lang/ucode"
        "staging_dir/target-*/usr/include/ucode"
    )
    
    for path in "${ucode_paths[@]}"; do
        if [ -e "$path" ]; then
            log_success "ucode依赖已满足: $path"
            return 0
        fi
    done
    
    log_warning "udebug修复验证未完全通过"
    return 1
}

# 显示修复建议
show_fix_recommendations() {
    echo ""
    log_info "udebug问题修复建议："
    echo "=================================="
    echo "  推荐方案: 删除udebug包（最稳定）"
    echo "  替代方案: 禁用udebug配置"
    echo "  高级方案: 修复ucode依赖关系"
    echo ""
    echo "  后续操作:"
    echo "    1. make clean"
    echo "    2. make defconfig" 
    echo "    3. make -j\$(nproc) || make -j1 V=s"
    echo "=================================="
}

# 主函数
main() {
    local device="${1:-unknown}"
    local mode="${2:-auto}"
    
    log_info "开始udebug错误修复，设备: $device"
    
    case "$mode" in
        "remove")
            fix_method_remove_udebug
            ;;
        "install")
            fix_method_install_ucode
            fix_method_fix_dependencies
            ;;
        "disable")
            fix_method_disable_udebug
            ;;
        "temp")
            fix_method_create_temp_ucode
            ;;
        "auto"|*)
            auto_fix_udebug
            ;;
    esac
    
    # 验证修复结果
    verify_udebug_fix
    
    # 显示修复建议
    show_fix_recommendations
    
    # 生成修复报告
    generate_fix_report "$device" "udebug" "udebug依赖修复" "编译缓存清理"
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi