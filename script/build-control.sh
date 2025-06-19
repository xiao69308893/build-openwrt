#!/bin/bash
#========================================================================================================================
# OpenWrt 智能编译控制脚本
# 功能: 根据传入的配置参数决定执行哪个编译工作流
# 用法: ./build-control.sh [编译模式] [其他参数...]
#========================================================================================================================

# 脚本版本
VERSION="1.0.0"

# 颜色定义（用于美化输出）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${PURPLE}[DEBUG]${NC} $1"
}

# 显示脚本标题
show_header() {
    echo -e "${CYAN}"
    echo "========================================================================================================================="
    echo "                                    🛠️ OpenWrt 智能编译控制脚本 v${VERSION}"
    echo "========================================================================================================================="
    echo -e "${NC}"
}

# 显示帮助信息
show_help() {
    cat << EOF
${CYAN}使用方法:${NC}
  $0 [编译模式] [选项...]

${CYAN}编译模式:${NC}
  smart               使用智能编译工作流 (smart-build.yml) - 推荐
  universal           使用通用设备编译工作流 (通用设备编译固件.yml)
  auto                自动选择合适的编译工作流 (默认)

${CYAN}选项:${NC}
  -s, --source        源码分支 (lede-master|openwrt-main|immortalwrt-master|Lienol-master)
  -d, --device        目标设备 (x86_64|xiaomi_4a_gigabit|newifi_d2|rpi_4b|nanopi_r2s)
  -p, --plugins       插件列表 (用逗号分隔)
  -c, --config        配置文件路径
  -t, --token         GitHub Token
  --dry-run           仅显示配置，不实际执行编译
  --force             强制执行，跳过安全检查
  -h, --help          显示此帮助信息
  -v, --version       显示版本信息

${CYAN}示例:${NC}
  # 使用智能编译模式编译X86设备
  $0 smart -s lede-master -d x86_64 -p "luci-app-ssr-plus,luci-app-passwall"
  
  # 自动选择编译模式
  $0 auto -s openwrt-main -d xiaomi_4a_gigabit
  
  # 仅预览配置，不实际编译
  $0 smart --dry-run -s lede-master -d x86_64

${CYAN}注意事项:${NC}
  - 智能编译模式支持Web界面触发和更精细的配置控制
  - 通用编译模式适用于传统的批量编译需求
  - 建议使用智能编译模式以获得更好的用户体验
EOF
}

# 显示版本信息
show_version() {
    echo "OpenWrt 智能编译控制脚本 版本 ${VERSION}"
    echo "Copyright (c) 2025 OpenWrt智能编译项目"
}

# 检查必要的环境
check_environment() {
    log_info "检查编译环境..."
    
    # 检查是否在Git仓库中
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "当前目录不是Git仓库，请确保在项目根目录下运行此脚本"
        exit 1
    fi
    
    # 检查工作流文件是否存在
    if [ ! -f ".github/workflows/smart-build.yml" ]; then
        log_error "smart-build.yml 工作流文件不存在"
        exit 1
    fi
    
    if [ ! -f ".github/workflows/通用设备编译固件.yml" ]; then
        log_warning "通用设备编译固件.yml 工作流文件不存在"
    fi
    
    # 检查GitHub CLI是否安装
    if ! command -v gh &> /dev/null; then
        log_warning "GitHub CLI (gh) 未安装，将使用API方式触发编译"
    fi
    
    log_success "环境检查完成"
}

# 验证输入参数
validate_parameters() {
    local source_branch="$1"
    local target_device="$2"
    local plugins_list="$3"
    
    # 验证源码分支
    case "$source_branch" in
        "lede-master"|"openwrt-main"|"immortalwrt-master"|"Lienol-master")
            log_debug "源码分支验证通过: $source_branch"
            ;;
        "")
            log_warning "未指定源码分支，将使用默认值: lede-master"
            source_branch="lede-master"
            ;;
        *)
            log_error "不支持的源码分支: $source_branch"
            log_error "支持的分支: lede-master, openwrt-main, immortalwrt-master, Lienol-master"
            exit 1
            ;;
    esac
    
    # 验证目标设备
    case "$target_device" in
        "x86_64"|"xiaomi_4a_gigabit"|"newifi_d2"|"rpi_4b"|"nanopi_r2s")
            log_debug "目标设备验证通过: $target_device"
            ;;
        "")
            log_warning "未指定目标设备，将使用默认值: x86_64"
            target_device="x86_64"
            ;;
        *)
            log_error "不支持的目标设备: $target_device"
            log_error "支持的设备: x86_64, xiaomi_4a_gigabit, newifi_d2, rpi_4b, nanopi_r2s"
            exit 1
            ;;
    esac
    
    # 输出验证后的参数
    echo "$source_branch|$target_device|$plugins_list"
}

# 检测插件冲突
check_plugin_conflicts() {
    local plugins_list="$1"
    
    if [ -z "$plugins_list" ]; then
        return 0
    fi
    
    log_info "检测插件冲突..."
    
    # 定义冲突插件组
    declare -A conflicts=(
        ["luci-app-ssr-plus,luci-app-passwall"]="SSR Plus+ 与 PassWall 冲突"
        ["luci-app-ssr-plus,luci-app-openclash"]="SSR Plus+ 与 OpenClash 可能冲突"
        ["luci-app-passwall,luci-app-openclash"]="PassWall 与 OpenClash 可能冲突"
        ["luci-app-adguardhome,luci-app-adblock"]="AdGuard Home 与 AdBlock 冲突"
    )
    
    # 检查冲突
    local has_conflict=false
    for conflict_pair in "${!conflicts[@]}"; do
        IFS=',' read -ra conflict_plugins <<< "$conflict_pair"
        local found_count=0
        
        for conflict_plugin in "${conflict_plugins[@]}"; do
            if [[ ",$plugins_list," == *",$conflict_plugin,"* ]]; then
                ((found_count++))
            fi
        done
        
        if [ $found_count -gt 1 ]; then
            log_warning "检测到插件冲突: ${conflicts[$conflict_pair]}"
            has_conflict=true
        fi
    done
    
    if [ "$has_conflict" = true ]; then
        log_warning "检测到插件冲突，建议检查配置"
        return 1
    else
        log_success "插件冲突检查通过"
        return 0
    fi
}

# 选择编译工作流
select_workflow() {
    local mode="$1"
    local source_branch="$2"
    local target_device="$3"
    
    case "$mode" in
        "smart")
            echo "smart-build.yml"
            ;;
        "universal")
            echo "通用设备编译固件.yml"
            ;;
        "auto")
            # 自动选择逻辑
            # 如果是Web界面触发或有特定配置需求，选择智能编译
            # 否则根据设备类型选择
            if [ "$target_device" = "x86_64" ] || [ -n "$PLUGINS_LIST" ]; then
                echo "smart-build.yml"
            else
                echo "smart-build.yml"  # 默认使用智能编译
            fi
            ;;
        *)
            log_error "未知的编译模式: $mode"
            exit 1
            ;;
    esac
}

# 生成编译配置
generate_build_config() {
    local workflow="$1"
    local source_branch="$2"
    local target_device="$3"
    local plugins_list="$4"
    local description="$5"
    
    cat << EOF
{
  "workflow": "$workflow",
  "source_branch": "$source_branch",
  "target_device": "$target_device",
  "plugins_list": "$plugins_list",
  "build_description": "$description",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "trigger_method": "script"
}
EOF
}

# 触发GitHub Actions编译
trigger_github_actions() {
    local workflow="$1"
    local source_branch="$2"
    local target_device="$3"
    local plugins_list="$4"
    local description="$5"
    local github_token="$6"
    
    log_info "准备触发GitHub Actions编译..."
    
    # 准备API请求数据
    local payload
    if [ "$workflow" = "smart-build.yml" ]; then
        payload=$(cat << EOF
{
  "event_type": "web_build",
  "client_payload": {
    "source_branch": "$source_branch",
    "target_device": "$target_device",
    "plugins": "$plugins_list",
    "description": "$description"
  }
}
EOF
)
    else
        payload=$(cat << EOF
{
  "ref": "main",
  "inputs": {
    "source_branch": "$source_branch"
  }
}
EOF
)
    fi
    
    # 获取仓库信息
    local repo_owner=$(git config --get remote.origin.url | sed -n 's#.*/\([^/]*\)/\([^/]*\)\.git#\1#p')
    local repo_name=$(git config --get remote.origin.url | sed -n 's#.*/\([^/]*\)/\([^/]*\)\.git#\2#p')
    
    if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
        log_error "无法获取仓库信息，请检查Git远程配置"
        exit 1
    fi
    
    log_debug "仓库: $repo_owner/$repo_name"
    log_debug "工作流: $workflow"
    
    # 选择API端点
    local api_endpoint
    if [ "$workflow" = "smart-build.yml" ]; then
        api_endpoint="https://api.github.com/repos/$repo_owner/$repo_name/dispatches"
    else
        api_endpoint="https://api.github.com/repos/$repo_owner/$repo_name/actions/workflows/$workflow/dispatches"
    fi
    
    # 发送API请求
    local response
    if [ -n "$github_token" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Authorization: token $github_token" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$api_endpoint")
    else
        log_error "需要GitHub Token才能触发编译，请使用 -t 参数提供Token"
        exit 1
    fi
    
    # 解析响应
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        log_success "编译任务已成功提交到GitHub Actions"
        log_info "请访问 https://github.com/$repo_owner/$repo_name/actions 查看编译进度"
    else
        log_error "编译任务提交失败 (HTTP $http_code)"
        log_error "响应内容: $response_body"
        exit 1
    fi
}

# 禁用通用编译工作流
disable_universal_workflow() {
    local workflow_file=".github/workflows/通用设备编译固件.yml"
    
    if [ -f "$workflow_file" ]; then
        log_info "临时禁用通用设备编译工作流..."
        
        # 创建备份
        cp "$workflow_file" "${workflow_file}.backup"
        
        # 在工作流文件开头添加禁用条件
        sed -i '1i# 工作流已临时禁用 - 请使用智能编译模式' "$workflow_file"
        sed -i '/^on:/a\  # 临时禁用此工作流，使用 smart-build.yml 代替\n  workflow_call:\n    inputs:\n      disabled:\n        type: boolean\n        default: true' "$workflow_file"
        
        log_warning "通用设备编译工作流已临时禁用"
        log_info "如需恢复，请运行: mv ${workflow_file}.backup $workflow_file"
    fi
}

# 恢复通用编译工作流
restore_universal_workflow() {
    local workflow_file=".github/workflows/通用设备编译固件.yml"
    local backup_file="${workflow_file}.backup"
    
    if [ -f "$backup_file" ]; then
        log_info "恢复通用设备编译工作流..."
        mv "$backup_file" "$workflow_file"
        log_success "通用设备编译工作流已恢复"
    fi
}

# 主函数
main() {
    # 默认参数
    local mode="auto"
    local source_branch=""
    local target_device=""
    local plugins_list=""
    local description="脚本触发编译"
    local config_file=""
    local github_token=""
    local dry_run=false
    local force=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            smart|universal|auto)
                mode="$1"
                shift
                ;;
            -s|--source)
                source_branch="$2"
                shift 2
                ;;
            -d|--device)
                target_device="$2"
                shift 2
                ;;
            -p|--plugins)
                plugins_list="$2"
                shift 2
                ;;
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -t|--token)
                github_token="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
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
    
    # 检查环境
    check_environment
    
    # 验证参数
    local validated_params=$(validate_parameters "$source_branch" "$target_device" "$plugins_list")
    IFS='|' read -r source_branch target_device plugins_list <<< "$validated_params"
    
    # 检查插件冲突
    if ! check_plugin_conflicts "$plugins_list" && [ "$force" = false ]; then
        log_error "检测到插件冲突，请解决后重试，或使用 --force 强制执行"
        exit 1
    fi
    
    # 选择工作流
    local workflow=$(select_workflow "$mode" "$source_branch" "$target_device")
    log_info "选择的工作流: $workflow"
    
    # 生成编译配置
    local build_config=$(generate_build_config "$workflow" "$source_branch" "$target_device" "$plugins_list" "$description")
    
    # 显示配置信息
    echo -e "${CYAN}编译配置:${NC}"
    echo "$build_config" | jq . 2>/dev/null || echo "$build_config"
    echo
    
    # 如果是dry-run模式，只显示配置
    if [ "$dry_run" = true ]; then
        log_info "Dry-run 模式，仅显示配置，不执行实际编译"
        exit 0
    fi
    
    # 禁用通用编译工作流（如果选择智能编译）
    if [ "$workflow" = "smart-build.yml" ]; then
        disable_universal_workflow
    fi
    
    # 触发编译
    trigger_github_actions "$workflow" "$source_branch" "$target_device" "$plugins_list" "$description" "$github_token"
    
    log_success "编译控制脚本执行完成"
}

# 脚本退出时的清理函数
cleanup() {
    if [ $? -ne 0 ]; then
        log_error "脚本执行过程中发生错误"
        restore_universal_workflow
    fi
}

# 设置退出时的清理
trap cleanup EXIT

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi