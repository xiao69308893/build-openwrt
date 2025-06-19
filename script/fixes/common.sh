#!/bin/bash
#========================================================================================================================
# 公共函数库
# 功能: 提供所有修复脚本共用的函数
#========================================================================================================================

# 检查文件是否存在并备份
backup_file_if_exists() {
    local file="$1"
    local backup_suffix="${2:-.backup}"
    
    if [ -f "$file" ]; then
        cp "$file" "${file}${backup_suffix}"
        log_info "已备份文件: $file -> ${file}${backup_suffix}"
        return 0
    fi
    return 1
}

# 安全删除文件或目录
safe_remove() {
    local target="$1"
    local description="$2"
    
    if [ -e "$target" ]; then
        log_warning "删除 $description: $target"
        rm -rf "$target"
        return 0
    else
        log_info "$description 不存在: $target"
        return 1
    fi
}

# 安全替换文件内容
safe_sed() {
    local pattern="$1"
    local replacement="$2"
    local file="$3"
    local description="$4"
    
    if [ -f "$file" ]; then
        log_info "修改 $description: $file"
        sed -i "$pattern" "$file" || {
            log_error "修改失败: $file"
            return 1
        }
        return 0
    else
        log_warning "文件不存在: $file"
        return 1
    fi
}

# 检查并添加配置项
add_config_if_missing() {
    local config_line="$1"
    local config_file="$2"
    local description="$3"
    
    if [ -f "$config_file" ]; then
        if ! grep -q "^${config_line%%=*}" "$config_file"; then
            echo "$config_line" >> "$config_file"
            log_info "添加配置 $description: $config_line"
            return 0
        else
            log_info "配置 $description 已存在"
            return 0
        fi
    else
        log_warning "配置文件不存在: $config_file"
        return 1
    fi
}

# 禁用内核配置项
disable_kernel_config() {
    local config_name="$1"
    local config_file="$2"
    local description="$3"
    
    if [ -f "$config_file" ]; then
        # 将已启用的配置禁用
        safe_sed "s/^CONFIG_${config_name}=y/# CONFIG_${config_name} is not set/" "$config_file" "$description"
        safe_sed "s/^CONFIG_${config_name}=m/# CONFIG_${config_name} is not set/" "$config_file" "$description"
        
        # 如果配置不存在，添加禁用配置
        if ! grep -q "CONFIG_${config_name}" "$config_file"; then
            echo "# CONFIG_${config_name} is not set" >> "$config_file"
            log_info "添加禁用配置: CONFIG_${config_name}"
        fi
        return 0
    else
        log_warning "配置文件不存在: $config_file"
        return 1
    fi
}

# 清理编译缓存
clean_build_cache() {
    local target_dir="$1"
    
    log_info "清理编译缓存..."
    
    # 清理常见的缓存目录
    local cache_dirs=(
        "tmp"
        "staging_dir/host*/stamp"
        "build_dir/host*"
        "dl/*.hash"
    )
    
    for dir in "${cache_dirs[@]}"; do
        if [ -e "$dir" ]; then
            log_info "清理: $dir"
            rm -rf "$dir"
        fi
    done
    
    # 清理特定目标的缓存
    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
        log_info "清理目标特定缓存: $target_dir"
        rm -rf "$target_dir"
    fi
}

# 检查feeds状态
check_feeds_status() {
    log_info "检查feeds状态..."
    
    if [ -f "feeds.conf.default" ]; then
        log_info "当前feeds配置:"
        cat feeds.conf.default | head -10
    else
        log_warning "feeds.conf.default不存在"
        return 1
    fi
    
    # 检查feeds目录
    if [ -d "feeds" ]; then
        local feed_count=$(ls -1 feeds/ | wc -l)
        log_info "已安装的feeds数量: $feed_count"
    else
        log_warning "feeds目录不存在"
        return 1
    fi
    
    return 0
}

# 更新feeds
update_feeds() {
    log_info "更新feeds..."
    
    ./scripts/feeds clean
    ./scripts/feeds update -a
    
    if [ $? -eq 0 ]; then
        log_success "feeds更新成功"
        return 0
    else
        log_error "feeds更新失败"
        return 1
    fi
}

# 重新安装feeds
reinstall_feeds() {
    log_info "重新安装feeds..."
    
    ./scripts/feeds uninstall -a
    ./scripts/feeds install -a
    
    if [ $? -eq 0 ]; then
        log_success "feeds安装成功"
        return 0
    else
        log_error "feeds安装失败"
        return 1
    fi
}

# 验证修复结果
verify_fix() {
    local fix_name="$1"
    local check_command="$2"
    
    log_info "验证修复: $fix_name"
    
    if eval "$check_command"; then
        log_success "修复验证成功: $fix_name"
        return 0
    else
        log_error "修复验证失败: $fix_name"
        return 1
    fi
}

# 显示修复摘要
show_fix_summary() {
    local fixes_applied=("$@")
    
    echo ""
    log_info "修复摘要:"
    echo "=================================="
    
    if [ ${#fixes_applied[@]} -gt 0 ]; then
        for fix in "${fixes_applied[@]}"; do
            echo "  ✅ $fix"
        done
    else
        echo "  ℹ️  未应用任何修复"
    fi
    
    echo "=================================="
}

# 检测编译错误类型
detect_build_error() {
    local log_content="$1"
    local detected_errors=()
    
    # 检测udebug错误
    if echo "$log_content" | grep -q "ucode_include_dir.*NOTFOUND"; then
        detected_errors+=("udebug")
    fi
    
    # 检测补丁错误
    if echo "$log_content" | grep -q "Patch failed"; then
        detected_errors+=("patch")
    fi
    
    # 检测依赖错误
    if echo "$log_content" | grep -q "dependency.*not found"; then
        detected_errors+=("dependency")
    fi
    
    # 检测内核配置错误
    if echo "$log_content" | grep -q "CONFIG.*not set"; then
        detected_errors+=("config")
    fi
    
    echo "${detected_errors[@]}"
}

# 生成修复报告
generate_fix_report() {
    local device="$1"
    local error_type="$2"
    local fixes_applied=("${@:3}")
    
    local report_file="fix_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "OpenWrt编译问题修复报告"
        echo "========================"
        echo "时间: $(date)"
        echo "设备: $device"
        echo "错误类型: $error_type"
        echo ""
        echo "应用的修复:"
        for fix in "${fixes_applied[@]}"; do
            echo "  - $fix"
        done
        echo ""
        echo "建议的后续操作:"
        echo "  1. make clean"
        echo "  2. make defconfig"
        echo "  3. make -j\$(nproc) || make -j1 V=s"
    } > "$report_file"
    
    log_info "修复报告已生成: $report_file"
}

# 导出函数供其他脚本使用
export -f backup_file_if_exists
export -f safe_remove
export -f safe_sed
export -f add_config_if_missing
export -f disable_kernel_config
export -f clean_build_cache
export -f check_feeds_status
export -f update_feeds
export -f reinstall_feeds
export -f verify_fix
export -f show_fix_summary
export -f detect_build_error
export -f generate_fix_report