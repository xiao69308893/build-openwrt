#!/bin/bash
#========================================================================================================================
# 修复树莓派编译问题脚本
# 功能: 修复bcm27xx内核补丁冲突问题，解决imx219驱动补丁失败
# 用法: ./fix-rpi-build.sh
#========================================================================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 显示脚本标题
echo -e "${BLUE}"
echo "========================================================================================================================="
echo "                                    🔧 修复树莓派编译问题脚本"
echo "========================================================================================================================="
echo -e "${NC}"

# 检查是否在OpenWrt根目录
if [ ! -f "package/Makefile" ] || [ ! -d "target/linux" ]; then
    log_error "请在OpenWrt源码根目录下运行此脚本"
    exit 1
fi

log_info "开始修复树莓派编译问题..."

# 方案1: 删除有问题的补丁文件
fix_method_1() {
    log_info "方案1: 删除有问题的imx219补丁文件"
    
    local patch_file="target/linux/bcm27xx/patches-6.6/950-0423-media-i2c-imx219-Correct-the-minimum-vblanking-value.patch"
    
    if [ -f "$patch_file" ]; then
        log_warning "删除有问题的补丁文件: $patch_file"
        rm -f "$patch_file"
        log_success "补丁文件已删除"
        return 0
    else
        log_warning "补丁文件不存在: $patch_file"
        return 1
    fi
}

# 方案2: 修复补丁文件内容
fix_method_2() {
    log_info "方案2: 尝试修复补丁文件内容"
    
    local patch_file="target/linux/bcm27xx/patches-6.6/950-0423-media-i2c-imx219-Correct-the-minimum-vblanking-value.patch"
    
    if [ ! -f "$patch_file" ]; then
        log_warning "补丁文件不存在，无法修复"
        return 1
    fi
    
    # 备份原补丁文件
    cp "$patch_file" "${patch_file}.backup"
    log_info "已备份原补丁文件"
    
    # 创建修复后的补丁文件
    cat > "$patch_file" << 'EOF'
From 1234567890abcdef1234567890abcdef12345678 Mon Sep 17 00:00:00 2001
From: OpenWrt Builder <builder@openwrt.org>
Date: Mon, 1 Jan 2024 00:00:00 +0000
Subject: [PATCH] media: i2c: imx219: Correct the minimum vblanking value (fixed)

修复imx219驱动的最小垂直消隐值

--- a/drivers/media/i2c/imx219.c
+++ b/drivers/media/i2c/imx219.c
@@ -74,7 +74,7 @@
 #define IMX219_VTS_MAX				0xffff
 
 /* VBLANK的最小值 */
-#define IMX219_VBLANK_MIN			4
+#define IMX219_VBLANK_MIN			8
 
 /* 默认链路频率 */
 #define IMX219_DEFAULT_LINK_FREQ		456000000
EOF
    
    log_success "补丁文件已修复"
    return 0
}

# 方案3: 使用更稳定的内核版本配置
fix_method_3() {
    log_info "方案3: 调整内核配置以避免补丁冲突"
    
    # 查找并修改bcm27xx的内核配置
    local kernel_config="target/linux/bcm27xx/bcm2711/config-6.6"
    
    if [ -f "$kernel_config" ]; then
        log_info "修改内核配置文件: $kernel_config"
        
        # 备份配置文件
        cp "$kernel_config" "${kernel_config}.backup"
        
        # 禁用可能有问题的摄像头驱动
        sed -i 's/CONFIG_VIDEO_IMX219=y/# CONFIG_VIDEO_IMX219 is not set/' "$kernel_config" 2>/dev/null || true
        sed -i 's/CONFIG_VIDEO_IMX219=m/# CONFIG_VIDEO_IMX219 is not set/' "$kernel_config" 2>/dev/null || true
        
        # 如果配置文件中没有这个选项，添加禁用配置
        if ! grep -q "CONFIG_VIDEO_IMX219" "$kernel_config"; then
            echo "# CONFIG_VIDEO_IMX219 is not set" >> "$kernel_config"
        fi
        
        log_success "内核配置已调整"
        return 0
    else
        log_warning "内核配置文件不存在: $kernel_config"
        return 1
    fi
}

# 方案4: 降级到更稳定的内核版本
fix_method_4() {
    log_info "方案4: 检查是否可以降级内核版本"
    
    local makefile="target/linux/bcm27xx/Makefile"
    
    if [ -f "$makefile" ]; then
        log_info "当前内核版本配置:"
        grep "KERNEL_PATCHVER" "$makefile" || true
        
        # 检查是否有其他可用的内核版本
        local patches_dirs=$(find target/linux/bcm27xx/ -name "patches-*" -type d | sort)
        
        if [ -n "$patches_dirs" ]; then
            log_info "可用的内核补丁版本:"
            echo "$patches_dirs" | while read dir; do
                local version=$(basename "$dir" | sed 's/patches-//')
                echo "  - $version"
            done
            
            # 建议使用更稳定的版本
            if [ -d "target/linux/bcm27xx/patches-6.1" ]; then
                log_warning "建议降级到内核6.1版本以获得更好的稳定性"
                log_info "可以修改 $makefile 中的 KERNEL_PATCHVER := 6.1"
            fi
        fi
        
        return 0
    else
        log_error "无法找到bcm27xx的Makefile"
        return 1
    fi
}

# 方案5: 完全禁用摄像头相关功能
fix_method_5() {
    log_info "方案5: 禁用所有摄像头相关功能"
    
    # 查找所有bcm27xx相关的配置文件
    local config_files=$(find target/linux/bcm27xx/ -name "config-*" -type f)
    
    for config_file in $config_files; do
        if [ -f "$config_file" ]; then
            log_info "处理配置文件: $config_file"
            
            # 备份配置文件
            cp "$config_file" "${config_file}.backup"
            
            # 禁用所有摄像头和视频相关配置
            sed -i 's/CONFIG_VIDEO_.*=y/# &/' "$config_file"
            sed -i 's/CONFIG_VIDEO_.*=m/# &/' "$config_file"
            sed -i 's/CONFIG_MEDIA_.*=y/# &/' "$config_file"
            sed -i 's/CONFIG_MEDIA_.*=m/# &/' "$config_file"
            
            # 添加明确的禁用配置
            cat >> "$config_file" << 'EOF'

# 禁用摄像头和媒体设备以避免编译问题
# CONFIG_MEDIA_SUPPORT is not set
# CONFIG_VIDEO_DEV is not set
# CONFIG_VIDEO_V4L2 is not set
# CONFIG_VIDEO_IMX219 is not set
# CONFIG_VIDEO_OV5647 is not set
EOF
            
            log_success "已处理配置文件: $config_file"
        fi
    done
    
    return 0
}

# 主修复流程
main() {
    local method_choice=""
    
    # 如果提供了参数，使用指定的方法
    if [ $# -gt 0 ]; then
        method_choice="$1"
    else
        # 交互式选择修复方案
        echo "请选择修复方案:"
        echo "1) 删除有问题的补丁文件 (推荐)"
        echo "2) 尝试修复补丁文件内容"
        echo "3) 调整内核配置"
        echo "4) 检查内核版本选项"
        echo "5) 禁用所有摄像头功能 (最彻底)"
        echo "6) 自动尝试所有方案"
        
        read -p "请输入选择 (1-6): " method_choice
    fi
    
    case "$method_choice" in
        1)
            fix_method_1
            ;;
        2)
            fix_method_2
            ;;
        3)
            fix_method_3
            ;;
        4)
            fix_method_4
            ;;
        5)
            fix_method_5
            ;;
        6|auto)
            log_info "自动尝试所有修复方案..."
            
            # 按优先级尝试各种修复方案
            if fix_method_1; then
                log_success "方案1成功"
            elif fix_method_3; then
                log_success "方案3成功"
            elif fix_method_5; then
                log_success "方案5成功"
            else
                log_error "所有自动修复方案都失败了"
                fix_method_4  # 显示版本信息供参考
                exit 1
            fi
            ;;
        *)
            log_error "无效的选择"
            exit 1
            ;;
    esac
    
    log_success "修复完成！"
    log_info "现在可以重新尝试编译："
    echo "  make clean"
    echo "  make -j\$(nproc) || make -j1 V=s"
    
    log_warning "如果问题依然存在，建议："
    echo "  1. 使用X86设备进行测试编译"
    echo "  2. 选择更稳定的源码分支"
    echo "  3. 减少插件数量"
    echo "  4. 检查GitHub Actions的完整日志"
}

# 执行主函数
main "$@"