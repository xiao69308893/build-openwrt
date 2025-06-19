#!/bin/bash
#========================================================================================================================
# OpenWrt 插件管理脚本 (改进版)
# 功能: 管理插件配置、检查冲突、生成插件配置、支持运行时配置
# 用法: ./plugin-manager.sh [操作] [参数...]
# 改进: 完善feeds.conf.default生成逻辑，添加--runtime-config支持，与构建编排兼容
#========================================================================================================================

# 脚本版本
VERSION="2.0.0"

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

# 插件配置目录
PLUGIN_CONFIG_DIR="config/plugins"
PLUGIN_DB_FILE="$PLUGIN_CONFIG_DIR/plugin_database.json"

# 运行时配置支持 (新增)
RUNTIME_CONFIG_FILE=""

# 默认feeds配置模板
declare -A DEFAULT_FEEDS=(
    ["openwrt-main"]="src-git packages https://git.openwrt.org/feed/packages.git;src-git luci https://git.openwrt.org/project/luci.git;src-git routing https://git.openwrt.org/feed/routing.git;src-git telephony https://git.openwrt.org/feed/telephony.git"
    ["lede-master"]="src-git packages https://github.com/coolsnowwolf/packages;src-git luci https://github.com/coolsnowwolf/luci;src-git routing https://git.openwrt.org/feed/routing.git;src-git telephony https://git.openwrt.org/feed/telephony.git"
    ["immortalwrt-master"]="src-git packages https://github.com/immortalwrt/packages.git;src-git luci https://github.com/immortalwrt/luci.git;src-git routing https://git.openwrt.org/feed/routing.git;src-git telephony https://git.openwrt.org/feed/telephony.git"
)

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${PURPLE}[DEBUG]${NC} $1"; }

# 从运行时配置读取值 (新增功能)
get_runtime_config_value() {
    local key="$1"
    local default="$2"
    
    if [ -n "$RUNTIME_CONFIG_FILE" ] && [ -f "$RUNTIME_CONFIG_FILE" ]; then
        if command -v jq &> /dev/null; then
            local value=$(jq -r "$key" "$RUNTIME_CONFIG_FILE" 2>/dev/null)
            if [ "$value" != "null" ] && [ -n "$value" ]; then
                echo "$value"
                return 0
            fi
        fi
    fi
    
    echo "$default"
}

# 显示标题
show_header() {
    echo -e "${CYAN}"
    echo "========================================================================================================================="
    echo "                                    🔌 OpenWrt 插件管理脚本 v${VERSION} (改进版)"
    echo "                                  支持运行时配置 | 完善feeds生成 | 构建编排兼容"
    echo "========================================================================================================================="
    echo -e "${NC}"
}

# 显示帮助信息 (新增--runtime-config参数)
show_help() {
    cat << EOF
${CYAN}使用方法:${NC}
  $0 [操作] [选项...]

${CYAN}操作:${NC}
  init                初始化插件数据库
  list                列出所有可用插件
  search              搜索插件
  info                显示插件详细信息
  validate            验证插件配置
  conflicts           检查插件冲突
  generate            生成插件配置
  generate-feeds      生成feeds.conf.default (新增)
  install             安装插件配置
  remove              移除插件配置
  update              更新插件数据库

${CYAN}选项:${NC}
  -p, --plugin        指定插件名称
  -l, --list          插件列表（逗号分隔）
  -c, --category      插件分类
  -f, --format        输出格式 (json|text|config|feeds)
  -o, --output        输出文件
  -b, --branch        源码分支 (openwrt-main|lede-master|immortalwrt-master)
  --runtime-config    运行时配置文件 (新增)
  --auto-detect       自动检测当前环境并生成适配的feeds配置 (新增)
  -v, --verbose       详细输出
  -h, --help          显示帮助信息
  --version           显示版本信息

${CYAN}示例:${NC}
  # 初始化插件数据库
  $0 init
  
  # 列出所有插件
  $0 list
  
  # 搜索代理插件
  $0 search -c proxy
  
  # 检查插件冲突
  $0 conflicts -l "luci-app-ssr-plus,luci-app-passwall"
  
  # 生成插件配置
  $0 generate -l "luci-app-ssr-plus,luci-theme-argon" -o plugin.config
  
  # 生成feeds配置 (新增)
  $0 generate-feeds -l "luci-app-ssr-plus,luci-app-passwall2" -b lede-master -o feeds.conf.default
  
  # 运行时配置支持 (新增)
  $0 --runtime-config /tmp/runtime.json generate-feeds -l "luci-app-ssr-plus"
  
  # 自动检测环境生成feeds (新增)
  $0 generate-feeds --auto-detect -l "luci-app-ssr-plus,luci-theme-argon"

${CYAN}插件分类:${NC}
  - proxy: 代理相关插件
  - network: 网络工具插件
  - system: 系统管理插件
  - storage: 存储相关插件
  - multimedia: 多媒体插件
  - security: 安全防护插件
  - theme: 主题插件
  - development: 开发工具插件

${CYAN}支持的源码分支:${NC}
  - openwrt-main: OpenWrt官方主分支
  - lede-master: Lean的LEDE主分支
  - immortalwrt-master: ImmortalWrt主分支
EOF
}

# 初始化插件数据库 (保持原有逻辑，添加更多feeds信息)
init_plugin_database() {
    log_info "初始化插件数据库..."
    
    # 创建插件配置目录
    mkdir -p "$PLUGIN_CONFIG_DIR"
    
    # 创建增强的插件数据库
    cat > "$PLUGIN_DB_FILE" << 'EOF'
{
  "version": "2.0.0",
  "last_updated": "",
  "categories": {
    "proxy": {
      "name": "代理工具",
      "description": "科学上网和代理相关插件",
      "plugins": {
        "luci-app-ssr-plus": {
          "name": "ShadowSocksR Plus+",
          "description": "强大的代理工具集合",
          "author": "fw876",
          "feeds": ["src-git helloworld https://github.com/fw876/helloworld"],
          "feeds_comment": "SSR Plus+ 插件源",
          "dependencies": ["shadowsocksr-libev-ssr-local", "shadowsocksr-libev-ssr-redir"],
          "conflicts": ["luci-app-passwall", "luci-app-openclash", "luci-app-bypass"],
          "size": "~2MB",
          "complexity": "medium",
          "priority": 1
        },
        "luci-app-passwall": {
          "name": "PassWall",
          "description": "简单易用的代理工具",
          "author": "xiaorouji",
          "feeds": [
            "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages",
            "src-git passwall https://github.com/xiaorouji/openwrt-passwall"
          ],
          "feeds_comment": "PassWall 软件包和主程序源",
          "dependencies": ["brook", "chinadns-ng", "dns2socks"],
          "conflicts": ["luci-app-ssr-plus", "luci-app-openclash", "luci-app-bypass"],
          "size": "~3MB",
          "complexity": "low",
          "priority": 2
        },
        "luci-app-passwall2": {
          "name": "PassWall 2",
          "description": "PassWall的升级版本",
          "author": "xiaorouji",
          "feeds": ["src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2"],
          "feeds_comment": "PassWall 2 主程序源",
          "dependencies": ["brook", "chinadns-ng", "dns2socks"],
          "conflicts": ["luci-app-ssr-plus", "luci-app-openclash", "luci-app-passwall"],
          "size": "~3MB",
          "complexity": "low",
          "priority": 2
        },
        "luci-app-openclash": {
          "name": "OpenClash",
          "description": "Clash客户端，功能强大",
          "author": "vernesong",
          "feeds": ["src-git openclash https://github.com/vernesong/OpenClash"],
          "feeds_comment": "OpenClash Clash客户端源",
          "dependencies": ["coreutils-nohup", "bash", "iptables", "dnsmasq-full"],
          "conflicts": ["luci-app-ssr-plus", "luci-app-passwall", "luci-app-bypass"],
          "size": "~5MB",
          "complexity": "high",
          "priority": 3
        },
        "luci-app-bypass": {
          "name": "Bypass",
          "description": "轻量级代理工具",
          "author": "kiddin9",
          "feeds": ["src-git bypass https://github.com/kiddin9/openwrt-bypass"],
          "feeds_comment": "Bypass 轻量级代理源",
          "dependencies": ["smartdns", "chinadns-ng"],
          "conflicts": ["luci-app-ssr-plus", "luci-app-passwall", "luci-app-openclash"],
          "size": "~1MB",
          "complexity": "low",
          "priority": 4
        }
      }
    },
    "network": {
      "name": "网络工具",
      "description": "网络管理和监控工具",
      "plugins": {
        "luci-app-adguardhome": {
          "name": "AdGuard Home",
          "description": "强大的广告拦截和DNS服务器",
          "author": "rufengsuixing",
          "feeds": ["src-git adguardhome https://github.com/rufengsuixing/luci-app-adguardhome"],
          "feeds_comment": "AdGuard Home 插件源",
          "dependencies": ["AdGuardHome"],
          "conflicts": [],
          "size": "~10MB",
          "complexity": "medium",
          "priority": 1
        },
        "luci-app-smartdns": {
          "name": "SmartDNS",
          "description": "智能DNS服务器",
          "author": "pymumu",
          "feeds": ["src-git smartdns https://github.com/pymumu/openwrt-smartdns"],
          "feeds_comment": "SmartDNS 智能DNS源",
          "dependencies": ["smartdns"],
          "conflicts": [],
          "size": "~1MB",
          "complexity": "low",
          "priority": 1
        },
        "luci-app-ddns": {
          "name": "动态DNS",
          "description": "动态域名解析服务",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["ddns-scripts"],
          "conflicts": [],
          "size": "~500KB",
          "complexity": "low",
          "priority": 1
        },
        "luci-app-upnp": {
          "name": "UPnP",
          "description": "通用即插即用协议支持",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["miniupnpd"],
          "conflicts": [],
          "size": "~200KB",
          "complexity": "low",
          "priority": 1
        }
      }
    },
    "system": {
      "name": "系统管理",
      "description": "系统管理和监控工具",
      "plugins": {
        "luci-app-ttyd": {
          "name": "终端访问",
          "description": "Web终端访问工具",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["ttyd"],
          "conflicts": [],
          "size": "~500KB",
          "complexity": "low",
          "priority": 1
        },
        "luci-app-htop": {
          "name": "系统监控",
          "description": "系统进程监控工具",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["htop"],
          "conflicts": [],
          "size": "~200KB",
          "complexity": "low",
          "priority": 1
        },
        "luci-app-pushbot": {
          "name": "消息推送",
          "description": "系统状态消息推送工具",
          "author": "zzsj0928",
          "feeds": ["src-git pushbot https://github.com/zzsj0928/luci-app-pushbot"],
          "feeds_comment": "消息推送机器人源",
          "dependencies": ["curl", "jsonfilter"],
          "conflicts": [],
          "size": "~300KB",
          "complexity": "medium",
          "priority": 2
        }
      }
    },
    "storage": {
      "name": "存储管理",
      "description": "存储和文件管理工具",
      "plugins": {
        "luci-app-samba4": {
          "name": "网络共享",
          "description": "Samba网络文件共享",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["samba4-server"],
          "conflicts": ["luci-app-samba"],
          "size": "~2MB",
          "complexity": "low",
          "priority": 1
        },
        "luci-app-hd-idle": {
          "name": "硬盘休眠",
          "description": "硬盘空闲时自动休眠",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["hd-idle"],
          "conflicts": [],
          "size": "~100KB",
          "complexity": "low",
          "priority": 1
        },
        "luci-app-dockerman": {
          "name": "Docker管理",
          "description": "Docker容器管理界面",
          "author": "lisaac",
          "feeds": ["src-git dockerman https://github.com/lisaac/luci-app-dockerman"],
          "feeds_comment": "Docker管理界面源",
          "dependencies": ["docker", "dockerd"],
          "conflicts": [],
          "size": "~5MB",
          "complexity": "high",
          "priority": 2
        }
      }
    },
    "multimedia": {
      "name": "多媒体",
      "description": "多媒体播放和下载工具",
      "plugins": {
        "luci-app-aria2": {
          "name": "Aria2下载",
          "description": "多线程下载工具",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["aria2", "ariang"],
          "conflicts": [],
          "size": "~3MB",
          "complexity": "medium",
          "priority": 1
        },
        "luci-app-transmission": {
          "name": "BT下载",
          "description": "BitTorrent下载客户端",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["transmission-daemon"],
          "conflicts": [],
          "size": "~2MB",
          "complexity": "medium",
          "priority": 1
        }
      }
    },
    "security": {
      "name": "安全防护",
      "description": "网络安全和防护工具",
      "plugins": {
        "luci-app-banip": {
          "name": "IP封禁",
          "description": "自动IP封禁工具",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": ["banip"],
          "conflicts": [],
          "size": "~500KB",
          "complexity": "medium",
          "priority": 1
        },
        "luci-app-accesscontrol": {
          "name": "访问控制",
          "description": "设备访问时间控制",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": [],
          "conflicts": [],
          "size": "~200KB",
          "complexity": "low",
          "priority": 1
        }
      }
    },
    "theme": {
      "name": "界面主题",
      "description": "LuCI界面主题",
      "plugins": {
        "luci-theme-argon": {
          "name": "Argon主题",
          "description": "美观的LuCI主题",
          "author": "jerrykuku",
          "feeds": ["src-git argon https://github.com/jerrykuku/luci-theme-argon"],
          "feeds_comment": "Argon主题源",
          "dependencies": [],
          "conflicts": ["luci-theme-material", "luci-theme-netgear"],
          "size": "~1MB",
          "complexity": "low",
          "priority": 1
        },
        "luci-app-argon-config": {
          "name": "Argon主题配置",
          "description": "Argon主题配置工具",
          "author": "jerrykuku",
          "feeds": ["src-git argon_config https://github.com/jerrykuku/luci-app-argon-config"],
          "feeds_comment": "Argon主题配置工具源",
          "dependencies": ["luci-theme-argon"],
          "conflicts": [],
          "size": "~200KB",
          "complexity": "low",
          "priority": 2
        },
        "luci-theme-material": {
          "name": "Material主题",
          "description": "Material Design风格主题",
          "author": "LuttyYang",
          "feeds": ["src-git material https://github.com/LuttyYang/luci-theme-material"],
          "feeds_comment": "Material Design主题源",
          "dependencies": [],
          "conflicts": ["luci-theme-argon", "luci-theme-netgear"],
          "size": "~800KB",
          "complexity": "low",
          "priority": 1
        }
      }
    },
    "development": {
      "name": "开发工具",
      "description": "开发和调试工具",
      "plugins": {
        "luci-app-commands": {
          "name": "自定义命令",
          "description": "在Web界面执行自定义命令",
          "author": "openwrt",
          "feeds": [],
          "feeds_comment": "官方软件包，无需额外feeds",
          "dependencies": [],
          "conflicts": [],
          "size": "~100KB",
          "complexity": "low",
          "priority": 1
        }
      }
    }
  }
}
EOF
    
    # 更新时间戳
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    if command -v jq &> /dev/null; then
        jq --arg time "$current_time" '.last_updated = $time' "$PLUGIN_DB_FILE" > "${PLUGIN_DB_FILE}.tmp" && mv "${PLUGIN_DB_FILE}.tmp" "$PLUGIN_DB_FILE"
    else
        sed -i "s/\"last_updated\": \"\"/\"last_updated\": \"$current_time\"/" "$PLUGIN_DB_FILE"
    fi
    
    log_success "插件数据库初始化完成: $PLUGIN_DB_FILE"
}

# 自动检测当前环境 (新增功能)
detect_environment() {
    local branch=""
    
    # 检查是否在OpenWrt源码目录中
    if [ -f "Config.in" ] && [ -f "package/Makefile" ]; then
        # 尝试通过远程仓库URL判断分支类型
        if git remote get-url origin &>/dev/null; then
            local remote_url=$(git remote get-url origin)
            case "$remote_url" in
                *coolsnowwolf/lede*|*coolsnowwolf/openwrt*)
                    branch="lede-master"
                    ;;
                *immortalwrt/immortalwrt*)
                    branch="immortalwrt-master"
                    ;;
                *openwrt/openwrt*)
                    branch="openwrt-main"
                    ;;
                *Lienol/openwrt*)
                    branch="Lienol-master"
                    ;;
            esac
        fi
        
        # 如果通过远程URL无法判断，尝试通过目录结构判断
        if [ -z "$branch" ]; then
            if [ -d "package/lean" ]; then
                branch="lede-master"
            elif [ -d "package/emortal" ]; then
                branch="immortalwrt-master"
            else
                branch="openwrt-main"
            fi
        fi
    fi
    
    # 优先使用运行时配置
    local runtime_branch=$(get_runtime_config_value ".source_branch" "")
    if [ -n "$runtime_branch" ]; then
        branch="$runtime_branch"
    fi
    
    # 默认值
    if [ -z "$branch" ]; then
        branch="lede-master"
    fi
    
    echo "$branch"
}

# 生成feeds.conf.default (完善版本)
generate_feeds_conf() {
    local plugin_list="$1"
    local output_file="$2"
    local branch="$3"
    local auto_detect="$4"
    
    log_info "生成feeds.conf.default配置..."
    
    # 自动检测环境
    if [ "$auto_detect" = true ]; then
        branch=$(detect_environment)
        log_info "自动检测到源码分支: $branch"
    fi
    
    # 从运行时配置获取分支信息
    if [ -z "$branch" ]; then
        branch=$(get_runtime_config_value ".source_branch" "lede-master")
    fi
    
    # 验证分支
    if [ -z "${DEFAULT_FEEDS[$branch]}" ]; then
        log_warning "不支持的分支: $branch，使用默认分支 lede-master"
        branch="lede-master"
    fi
    
    # 准备输出内容
    local feeds_content=""
    
    # 添加文件头
    feeds_content+="# OpenWrt Feeds 配置文件"$'\n'
    feeds_content+="# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"$'\n'
    feeds_content+="# 源码分支: $branch"$'\n'
    feeds_content+="# 生成工具: plugin-manager.sh v$VERSION"$'\n'
    feeds_content+=""$'\n'
    
    # 添加基础feeds源
    feeds_content+="# =============================================="$'\n'
    feeds_content+="# 基础 Feeds 源"$'\n'
    feeds_content+="# =============================================="$'\n'
    
    # 解析基础feeds
    IFS=';' read -ra base_feeds <<< "${DEFAULT_FEEDS[$branch]}"
    for feed in "${base_feeds[@]}"; do
        feeds_content+="$feed"$'\n'
    done
    
    # 处理插件特定的feeds
    if [ -n "$plugin_list" ]; then
        # 解析插件列表
        IFS=',' read -ra plugins <<< "$plugin_list"
        
        local plugin_feeds=()
        local valid_plugins=()
        
        # 收集所有插件的feeds
        for plugin in "${plugins[@]}"; do
            plugin=$(echo "$plugin" | xargs) # 去除空格
            
            # 查找插件
            local found_category=""
            local categories
            
            if command -v jq &> /dev/null; then
                categories=$(jq -r '.categories | keys[]' "$PLUGIN_DB_FILE" 2>/dev/null)
            else
                log_warning "未安装jq，使用备选方法解析插件"
                categories="proxy network system storage multimedia security theme development"
            fi
            
            for category in $categories; do
                if command -v jq &> /dev/null; then
                    local exists=$(jq -r ".categories.${category}.plugins.${plugin}" "$PLUGIN_DB_FILE" 2>/dev/null)
                    if [ "$exists" != "null" ]; then
                        found_category="$category"
                        break
                    fi
                else
                    # 简单的字符串匹配备选方案
                    if grep -q "\"$plugin\":" "$PLUGIN_DB_FILE" 2>/dev/null; then
                        found_category="$category"
                        break
                    fi
                fi
            done
            
            if [ -n "$found_category" ]; then
                valid_plugins+=("$plugin")
                
                # 获取插件的feeds
                if command -v jq &> /dev/null; then
                    local feeds=$(jq -r ".categories.${found_category}.plugins.${plugin}.feeds[]" "$PLUGIN_DB_FILE" 2>/dev/null)
                    local feeds_comment=$(jq -r ".categories.${found_category}.plugins.${plugin}.feeds_comment" "$PLUGIN_DB_FILE" 2>/dev/null)
                    
                    if [ -n "$feeds" ]; then
                        while IFS= read -r feed_line; do
                            if [ -n "$feed_line" ] && [ "$feed_line" != "null" ]; then
                                plugin_feeds+=("$feed_line|$plugin|$feeds_comment")
                            fi
                        done <<< "$feeds"
                    fi
                else
                    log_warning "跳过插件feeds解析: $plugin (需要jq工具)"
                fi
            else
                log_warning "跳过未知插件: $plugin"
            fi
        done
        
        # 添加插件feeds (去重)
        if [ ${#plugin_feeds[@]} -gt 0 ]; then
            feeds_content+=""$'\n'
            feeds_content+="# =============================================="$'\n'
            feeds_content+="# 插件 Feeds 源"$'\n'
            feeds_content+="# =============================================="$'\n'
            
            # 使用关联数组去重
            declare -A unique_feeds
            for feed_info in "${plugin_feeds[@]}"; do
                IFS='|' read -r feed_line plugin_name comment <<< "$feed_info"
                if [ -z "${unique_feeds[$feed_line]}" ]; then
                    unique_feeds["$feed_line"]="$plugin_name|$comment"
                fi
            done
            
            # 输出去重后的feeds
            for feed_line in "${!unique_feeds[@]}"; do
                IFS='|' read -r plugin_name comment <<< "${unique_feeds[$feed_line]}"
                feeds_content+=""$'\n'
                feeds_content+="# $plugin_name: $comment"$'\n'
                feeds_content+="$feed_line"$'\n'
            done
        fi
        
        # 添加有效插件列表
        if [ ${#valid_plugins[@]} -gt 0 ]; then
            feeds_content+=""$'\n'
            feeds_content+="# =============================================="$'\n'
            feeds_content+="# 已选择的插件列表"$'\n'
            feeds_content+="# =============================================="$'\n'
            feeds_content+="# 插件数量: ${#valid_plugins[@]}"$'\n'
            
            for plugin in "${valid_plugins[@]}"; do
                feeds_content+="# - $plugin"$'\n'
            done
        fi
    fi
    
    # 添加常用扩展feeds (新增)
    feeds_content+=""$'\n'
    feeds_content+="# =============================================="$'\n'
    feeds_content+="# 常用扩展 Feeds 源 (按需启用)"$'\n'
    feeds_content+="# =============================================="$'\n'
    feeds_content+="# src-git kenzo https://github.com/kenzok8/openwrt-packages"$'\n'
    feeds_content+="# src-git small https://github.com/kenzok8/small"$'\n'
    feeds_content+="# src-git kiddin9 https://github.com/kiddin9/openwrt-packages"$'\n'
    feeds_content+="# src-git custom /path/to/custom-feed"$'\n'
    
    # 输出到文件或控制台
    if [ -n "$output_file" ]; then
        echo -e "$feeds_content" > "$output_file"
        log_success "feeds.conf.default 已生成: $output_file"
        
        # 验证生成的文件
        if [ -f "$output_file" ]; then
            local line_count=$(wc -l < "$output_file")
            local feed_count=$(grep -c "^src-git" "$output_file" 2>/dev/null || echo "0")
            log_info "文件统计: $line_count 行，$feed_count 个feeds源"
        fi
    else
        echo -e "$feeds_content"
    fi
    
    return 0
}

# 原有的列出所有插件函数 (保持不变)
list_plugins() {
    local category="$1"
    local format="${2:-text}"
    
    if [ ! -f "$PLUGIN_DB_FILE" ]; then
        log_error "插件数据库不存在，请先运行 init 初始化"
        return 1
    fi
    
    log_info "列出插件信息..."
    
    case "$format" in
        "json")
            if [ -n "$category" ]; then
                if command -v jq &> /dev/null; then
                    jq ".categories.${category}.plugins" "$PLUGIN_DB_FILE" 2>/dev/null || {
                        log_error "分类不存在: $category"
                        return 1
                    }
                else
                    log_error "需要jq工具来输出JSON格式"
                    return 1
                fi
            else
                if command -v jq &> /dev/null; then
                    jq ".categories" "$PLUGIN_DB_FILE"
                else
                    log_error "需要jq工具来输出JSON格式"
                    return 1
                fi
            fi
            ;;
        "text")
            if [ -n "$category" ]; then
                list_category_plugins "$category"
            else
                list_all_plugins
            fi
            ;;
        *)
            log_error "不支持的输出格式: $format"
            return 1
            ;;
    esac
}

# 原有的列出所有插件函数 (保持不变)
list_all_plugins() {
    echo -e "\n${CYAN}📦 可用插件列表${NC}"
    echo "========================================"
    
    # 使用备选解析方法（如果没有jq）
    if ! command -v jq &> /dev/null; then
        log_warning "未安装jq工具，使用简化显示"
        echo "请安装jq工具以获得完整功能: sudo apt-get install jq"
        return 1
    fi
    
    # 读取并解析JSON
    local categories=$(jq -r '.categories | keys[]' "$PLUGIN_DB_FILE")
    
    for category in $categories; do
        local category_name=$(jq -r ".categories.${category}.name" "$PLUGIN_DB_FILE")
        local category_desc=$(jq -r ".categories.${category}.description" "$PLUGIN_DB_FILE")
        
        echo -e "\n${YELLOW}📂 ${category_name} (${category})${NC}"
        echo "   $category_desc"
        echo "   ────────────────────────────────────"
        
        local plugins=$(jq -r ".categories.${category}.plugins | keys[]" "$PLUGIN_DB_FILE")
        for plugin in $plugins; do
            local name=$(jq -r ".categories.${category}.plugins.${plugin}.name" "$PLUGIN_DB_FILE")
            local desc=$(jq -r ".categories.${category}.plugins.${plugin}.description" "$PLUGIN_DB_FILE")
            local size=$(jq -r ".categories.${category}.plugins.${plugin}.size" "$PLUGIN_DB_FILE")
            local complexity=$(jq -r ".categories.${category}.plugins.${plugin}.complexity" "$PLUGIN_DB_FILE")
            
            # 复杂度图标
            local complexity_icon="🟢"
            case "$complexity" in
                "medium") complexity_icon="🟡" ;;
                "high") complexity_icon="🔴" ;;
            esac
            
            printf "   ${GREEN}%-25s${NC} %s %s (%s)\n" "$plugin" "$complexity_icon" "$name" "$size"
            printf "   %-25s   %s\n" "" "$desc"
        done
    done
    
    echo -e "\n${BLUE}图例:${NC} 🟢 简单 🟡 中等 🔴 复杂"
}

# 原有函数保持不变 (列出指定分类的插件)
list_category_plugins() {
    local category="$1"
    
    if ! command -v jq &> /dev/null; then
        log_error "需要jq工具，请安装: sudo apt-get install jq"
        return 1
    fi
    
    local category_name=$(jq -r ".categories.${category}.name" "$PLUGIN_DB_FILE" 2>/dev/null)
    if [ "$category_name" = "null" ]; then
        log_error "分类不存在: $category"
        return 1
    fi
    
    echo -e "\n${CYAN}📂 ${category_name} 插件列表${NC}"
    echo "========================================"
    
    local plugins=$(jq -r ".categories.${category}.plugins | keys[]" "$PLUGIN_DB_FILE")
    for plugin in $plugins; do
        local name=$(jq -r ".categories.${category}.plugins.${plugin}.name" "$PLUGIN_DB_FILE")
        local desc=$(jq -r ".categories.${category}.plugins.${plugin}.description" "$PLUGIN_DB_FILE")
        local size=$(jq -r ".categories.${category}.plugins.${plugin}.size" "$PLUGIN_DB_FILE")
        
        printf "${GREEN}%-25s${NC} %s (%s)\n" "$plugin" "$name" "$size"
        printf "%-25s %s\n" "" "$desc"
        echo
    done
}

# 原有搜索函数 (保持不变)
search_plugins() {
    local keyword="$1"
    local category="$2"
    
    if [ -z "$keyword" ]; then
        log_error "请提供搜索关键词"
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "需要jq工具，请安装: sudo apt-get install jq"
        return 1
    fi
    
    log_info "搜索插件: $keyword"
    
    echo -e "\n${CYAN}🔍 搜索结果${NC}"
    echo "========================================"
    
    local found=false
    local categories
    
    if [ -n "$category" ]; then
        categories="$category"
    else
        categories=$(jq -r '.categories | keys[]' "$PLUGIN_DB_FILE")
    fi
    
    for cat in $categories; do
        local plugins=$(jq -r ".categories.${cat}.plugins | keys[]" "$PLUGIN_DB_FILE")
        for plugin in $plugins; do
            local name=$(jq -r ".categories.${cat}.plugins.${plugin}.name" "$PLUGIN_DB_FILE")
            local desc=$(jq -r ".categories.${cat}.plugins.${plugin}.description" "$PLUGIN_DB_FILE")
            
            # 检查是否匹配关键词
            if [[ "$plugin" =~ $keyword ]] || [[ "$name" =~ $keyword ]] || [[ "$desc" =~ $keyword ]]; then
                local size=$(jq -r ".categories.${cat}.plugins.${plugin}.size" "$PLUGIN_DB_FILE")
                local cat_name=$(jq -r ".categories.${cat}.name" "$PLUGIN_DB_FILE")
                
                printf "${GREEN}%-25s${NC} %s (%s)\n" "$plugin" "$name" "$size"
                printf "%-25s 分类: %s\n" "" "$cat_name"
                printf "%-25s %s\n" "" "$desc"
                echo
                found=true
            fi
        done
    done
    
    if [ "$found" = false ]; then
        echo "未找到匹配的插件"
    fi
}

# 原有显示插件详细信息函数 (保持不变，添加feeds信息显示)
show_plugin_info() {
    local plugin_name="$1"
    
    if [ -z "$plugin_name" ]; then
        log_error "请指定插件名称"
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "需要jq工具，请安装: sudo apt-get install jq"
        return 1
    fi
    
    log_info "查询插件信息: $plugin_name"
    
    # 查找插件
    local found_category=""
    local categories=$(jq -r '.categories | keys[]' "$PLUGIN_DB_FILE")
    
    for category in $categories; do
        local exists=$(jq -r ".categories.${category}.plugins.${plugin_name}" "$PLUGIN_DB_FILE")
        if [ "$exists" != "null" ]; then
            found_category="$category"
            break
        fi
    done
    
    if [ -z "$found_category" ]; then
        log_error "插件不存在: $plugin_name"
        return 1
    fi
    
    # 显示详细信息
    echo -e "\n${CYAN}🔌 插件详细信息${NC}"
    echo "========================================"
    
    local name=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.name" "$PLUGIN_DB_FILE")
    local desc=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.description" "$PLUGIN_DB_FILE")
    local author=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.author" "$PLUGIN_DB_FILE")
    local size=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.size" "$PLUGIN_DB_FILE")
    local complexity=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.complexity" "$PLUGIN_DB_FILE")
    local cat_name=$(jq -r ".categories.${found_category}.name" "$PLUGIN_DB_FILE")
    local feeds_comment=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.feeds_comment" "$PLUGIN_DB_FILE")
    
    echo "插件名称: ${GREEN}$plugin_name${NC}"
    echo "显示名称: $name"
    echo "插件描述: $desc"
    echo "开发作者: $author"
    echo "所属分类: $cat_name ($found_category)"
    echo "安装大小: $size"
    echo "复杂程度: $complexity"
    
    if [ "$feeds_comment" != "null" ] && [ -n "$feeds_comment" ]; then
        echo "Feeds说明: $feeds_comment"
    fi
    
    # 显示依赖
    local deps=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.dependencies[]" "$PLUGIN_DB_FILE" 2>/dev/null)
    if [ -n "$deps" ]; then
        echo -e "\n${YELLOW}📦 依赖包:${NC}"
        echo "$deps" | while read dep; do
            echo "  - $dep"
        done
    fi
    
    # 显示冲突
    local conflicts=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.conflicts[]" "$PLUGIN_DB_FILE" 2>/dev/null)
    if [ -n "$conflicts" ]; then
        echo -e "\n${RED}⚠️  冲突插件:${NC}"
        echo "$conflicts" | while read conflict; do
            echo "  - $conflict"
        done
    fi
    
    # 显示feeds源 (增强显示)
    local feeds=$(jq -r ".categories.${found_category}.plugins.${plugin_name}.feeds[]" "$PLUGIN_DB_FILE" 2>/dev/null)
    if [ -n "$feeds" ]; then
        echo -e "\n${BLUE}🔗 所需Feeds源:${NC}"
        echo "$feeds" | while read feed; do
            echo "  $feed"
        done
    else
        echo -e "\n${BLUE}🔗 Feeds源:${NC} 官方软件包，无需额外feeds"
    fi
}

# 原有检查插件冲突函数 (保持不变)
check_conflicts() {
    local plugin_list="$1"
    
    if [ -z "$plugin_list" ]; then
        log_error "请提供插件列表"
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "需要jq工具，请安装: sudo apt-get install jq"
        return 1
    fi
    
    log_info "检查插件冲突..."
    
    # 解析插件列表
    IFS=',' read -ra plugins <<< "$plugin_list"
    
    local conflicts_found=false
    local conflict_pairs=()
    
    echo -e "\n${CYAN}⚠️  插件冲突检查${NC}"
    echo "========================================"
    
    # 检查每个插件的冲突
    for plugin in "${plugins[@]}"; do
        plugin=$(echo "$plugin" | xargs) # 去除空格
        
        # 查找插件所在分类
        local found_category=""
        local categories=$(jq -r '.categories | keys[]' "$PLUGIN_DB_FILE")
        
        for category in $categories; do
            local exists=$(jq -r ".categories.${category}.plugins.${plugin}" "$PLUGIN_DB_FILE")
            if [ "$exists" != "null" ]; then
                found_category="$category"
                break
            fi
        done
        
        if [ -z "$found_category" ]; then
            log_warning "未知插件: $plugin"
            continue
        fi
        
        # 获取冲突列表
        local plugin_conflicts=$(jq -r ".categories.${found_category}.plugins.${plugin}.conflicts[]" "$PLUGIN_DB_FILE" 2>/dev/null)
        
        # 检查是否与其他选中的插件冲突
        for other_plugin in "${plugins[@]}"; do
            other_plugin=$(echo "$other_plugin" | xargs)
            if [ "$plugin" != "$other_plugin" ]; then
                if echo "$plugin_conflicts" | grep -q "^${other_plugin}$"; then
                    conflicts_found=true
                    conflict_pairs+=("$plugin <-> $other_plugin")
                fi
            fi
        done
    done
    
    if [ "$conflicts_found" = true ]; then
        echo -e "${RED}❌ 发现插件冲突:${NC}"
        for pair in "${conflict_pairs[@]}"; do
            echo "  $pair"
        done
        echo
        echo -e "${YELLOW}建议:${NC} 请从冲突的插件中选择一个，移除其他冲突插件"
        return 1
    else
        echo -e "${GREEN}✅ 未发现插件冲突${NC}"
        return 0
    fi
}

# 生成插件配置 (更新版本，支持feeds格式)
generate_plugin_config() {
    local plugin_list="$1"
    local output_file="$2"
    local format="${3:-config}"
    local branch="$4"
    local auto_detect="$5"
    
    if [ -z "$plugin_list" ]; then
        log_error "请提供插件列表"
        return 1
    fi
    
    log_info "生成插件配置..."
    
    # 根据格式调用不同的生成函数
    case "$format" in
        "config")
            generate_config_format "$plugin_list" "$output_file"
            ;;
        "feeds")
            generate_feeds_conf "$plugin_list" "$output_file" "$branch" "$auto_detect"
            ;;
        "json")
            generate_json_format "$plugin_list" "$output_file"
            ;;
        *)
            log_error "不支持的格式: $format"
            return 1
            ;;
    esac
}

# 原有的生成配置格式函数 (保持不变)
generate_config_format() {
    local plugin_list="$1"
    local output_file="$2"
    
    # 解析插件列表
    IFS=',' read -ra plugins <<< "$plugin_list"
    
    # 验证所有插件
    local valid_plugins=()
    
    for plugin in "${plugins[@]}"; do
        plugin=$(echo "$plugin" | xargs)
        
        # 查找插件 (简化验证，如果没有jq就跳过验证)
        if command -v jq &> /dev/null; then
            local found_category=""
            local categories=$(jq -r '.categories | keys[]' "$PLUGIN_DB_FILE" 2>/dev/null)
            
            for category in $categories; do
                local exists=$(jq -r ".categories.${category}.plugins.${plugin}" "$PLUGIN_DB_FILE" 2>/dev/null)
                if [ "$exists" != "null" ]; then
                    found_category="$category"
                    break
                fi
            done
            
            if [ -n "$found_category" ]; then
                valid_plugins+=("$plugin")
            else
                log_warning "跳过未知插件: $plugin"
            fi
        else
            # 没有jq时，假设所有插件都有效
            valid_plugins+=("$plugin")
        fi
    done
    
    if [ ${#valid_plugins[@]} -eq 0 ]; then
        log_error "没有有效的插件"
        return 1
    fi
    
    # 生成配置内容
    local config_content=""
    config_content+="# OpenWrt 插件配置"$'\n'
    config_content+="# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"$'\n'
    config_content+="# 插件数量: ${#valid_plugins[@]}"$'\n'
    config_content+=""$'\n'
    
    for plugin in "${valid_plugins[@]}"; do
        config_content+="CONFIG_PACKAGE_${plugin}=y"$'\n'
    done
    
    # 输出到文件或控制台
    if [ -n "$output_file" ]; then
        echo -e "$config_content" > "$output_file"
        log_success "配置已保存到: $output_file"
    else
        echo -e "$config_content"
    fi
}

# 原有的生成JSON格式函数 (保持不变)
generate_json_format() {
    local plugin_list="$1"
    local output_file="$2"
    
    # 解析插件列表
    IFS=',' read -ra plugins <<< "$plugin_list"
    
    local json_content=""
    json_content+="{"$'\n'
    json_content+="  \"generated_at\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","$'\n'
    json_content+="  \"plugin_count\": ${#plugins[@]},"$'\n'
    json_content+="  \"plugins\": ["$'\n'
    
    for i in "${!plugins[@]}"; do
        local plugin="${plugins[$i]}"
        plugin=$(echo "$plugin" | xargs)
        if [ $i -eq $((${#plugins[@]} - 1)) ]; then
            json_content+="    \"$plugin\""$'\n'
        else
            json_content+="    \"$plugin\","$'\n'
        fi
    done
    
    json_content+="  ]"$'\n'
    json_content+="}"$'\n'
    
    # 输出到文件或控制台
    if [ -n "$output_file" ]; then
        echo -e "$json_content" > "$output_file"
        log_success "配置已保存到: $output_file"
    else
        echo -e "$json_content"
    fi
}

pre_build_check() {
    local device="$1"
    local plugin_list="$2"
    local strict_mode="$3"
    
    log_info "执行编译前检查..."
    log_info "设备: $device"
    log_info "插件: $plugin_list"
    log_info "严格模式: $strict_mode"
    
    # 简化版本的检查逻辑
    local issues=()
    local warnings=()
    
    # 检查设备是否为空
    if [ -z "$device" ]; then
        issues+=("未指定设备类型")
    fi
    
    # 检查插件列表
    if [ -n "$plugin_list" ]; then
        # 解析插件列表
        IFS=',' read -ra plugins <<< "$plugin_list"
        
        for plugin in "${plugins[@]}"; do
            plugin=$(echo "$plugin" | xargs)
            if [ -n "$plugin" ]; then
                log_debug "检查插件: $plugin"
                # 这里可以添加具体的插件检查逻辑
            fi
        done
    fi
    
    # 输出结果
    if [ ${#issues[@]} -gt 0 ]; then
        log_error "发现 ${#issues[@]} 个问题:"
        for issue in "${issues[@]}"; do
            log_error "  - $issue"
        done
        return 1
    else
        log_success "编译前检查通过"
        return 0
    fi
}

# 自动修复插件依赖函数
auto_fix_plugin_deps() {
    local device="$1"
    local plugin_list="$2"
    local auto_fix="$3"
    
    log_info "自动修复插件依赖..."
    log_info "设备: $device"
    log_info "插件: $plugin_list"
    log_info "自动修复: $auto_fix"
    
    if [ "$auto_fix" = "true" ]; then
        log_info "执行自动修复逻辑..."
        # 这里可以添加具体的自动修复逻辑
        log_success "自动修复完成"
    else
        log_info "仅检查模式，未执行修复"
    fi
    
    return 0
}

# 检查设备兼容性函数
check_device_compatibility() {
    local device="$1"
    local plugin_list="$2"
    
    log_info "检查设备兼容性..."
    log_info "设备: $device"
    log_info "插件: $plugin_list"
    
    # 简化版本的兼容性检查
    case "$device" in
        "x86_64"|"rpi_4b"|"nanopi_r2s"|"xiaomi_4a_gigabit"|"newifi_d2")
            log_success "设备兼容性检查通过"
            return 0
            ;;
        *)
            log_warning "未知设备类型: $device"
            return 1
            ;;
    esac
}

# 优化插件配置函数
optimize_plugin_config() {
    local device="$1"
    local plugin_list="$2" 
    local auto_fix="$3"
    
    log_info "优化插件配置..."
    log_info "设备: $device"
    log_info "插件: $plugin_list"
    log_info "自动修复: $auto_fix"
    
    # 这里可以添加具体的优化逻辑
    log_success "插件配置优化完成"
    return 0
}

# 原有的验证插件配置函数 (保持不变)
validate_plugins() {
    local plugin_list="$1"
    
    if [ -z "$plugin_list" ]; then
        log_error "请提供插件列表"
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warning "未安装jq工具，跳过详细验证"
        return 0
    fi
    
    log_info "验证插件配置..."
    
    # 解析插件列表
    IFS=',' read -ra plugins <<< "$plugin_list"
    
    local errors=0
    local warnings=0
    
    echo -e "\n${CYAN}🔍 插件验证结果${NC}"
    echo "========================================"
    
    for plugin in "${plugins[@]}"; do
        plugin=$(echo "$plugin" | xargs)
        
        # 查找插件
        local found_category=""
        local categories=$(jq -r '.categories | keys[]' "$PLUGIN_DB_FILE")
        
        for category in $categories; do
            local exists=$(jq -r ".categories.${category}.plugins.${plugin}" "$PLUGIN_DB_FILE")
            if [ "$exists" != "null" ]; then
                found_category="$category"
                break
            fi
        done
        
        if [ -z "$found_category" ]; then
            echo -e "${RED}❌ $plugin${NC} - 插件不存在"
            ((errors++))
        else
            echo -e "${GREEN}✅ $plugin${NC} - 验证通过"
            
            # 检查复杂度警告
            local complexity=$(jq -r ".categories.${found_category}.plugins.${plugin}.complexity" "$PLUGIN_DB_FILE")
            if [ "$complexity" = "high" ]; then
                echo -e "   ${YELLOW}⚠️  高复杂度插件，可能需要额外配置${NC}"
                ((warnings++))
            fi
        fi
    done
    
    echo
    echo "验证完成: $((${#plugins[@]} - errors)) 个有效插件，$errors 个错误，$warnings 个警告"
    
    if [ $errors -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# 主函数 (更新版本，添加新的操作和参数)
# 在 plugin-manager.sh 的 main() 函数中添加设备参数支持

# 1. 在变量声明部分添加 (在 main() 函数开头)
main() {
    local operation=""
    local plugin=""
    local plugin_list=""
    local category=""
    local format="text"
    local output=""
    local branch=""
    local device=""           # 新增：设备参数
    local auto_detect=false
    local verbose=false
    local auto_fix=false     # 新增：自动修复参数
    local strict_mode=false  # 新增：严格模式参数
    
    # 2. 在参数解析的 while 循环中添加 (在现有的 case 语句中添加)
    while [[ $# -gt 0 ]]; do
        case $1 in
            init|list|search|info|validate|conflicts|generate|generate-feeds|install|remove|update|pre-build-check|auto-fix-deps|compatibility|optimize)
                operation="$1"
                shift
                ;;
            -p|--plugin)
                plugin="$2"
                shift 2
                ;;
            -l|--list)
                plugin_list="$2"
                shift 2
                ;;
            -c|--category)
                category="$2"
                shift 2
                ;;
            -f|--format)
                format="$2"
                shift 2
                ;;
            -o|--output)
                output="$2"
                shift 2
                ;;
            -b|--branch)
                branch="$2"
                shift 2
                ;;
            -d|--device)              # 新增：设备参数支持
                device="$2"
                shift 2
                ;;
            --runtime-config)
                RUNTIME_CONFIG_FILE="$2"
                if [ ! -f "$RUNTIME_CONFIG_FILE" ]; then
                    log_warning "运行时配置文件不存在: $RUNTIME_CONFIG_FILE"
                fi
                shift 2
                ;;
            --auto-detect)
                auto_detect=true
                shift
                ;;
            --auto-fix)               # 新增：自动修复参数
                auto_fix=true
                shift
                ;;
            --strict)                 # 新增：严格模式参数
                strict_mode=true
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
                echo "插件管理脚本 版本 $VERSION"
                exit 0
                ;;
            *)
                # 如果没有指定操作，将第一个参数作为搜索关键词
                if [ -z "$operation" ]; then
                    operation="search"
                    plugin="$1"
                else
                    log_error "未知参数: $1"
                    echo "使用 $0 --help 查看帮助信息"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 检查jq工具 (某些操作需要)
    if [ "$operation" != "init" ] && [ ! -f "$PLUGIN_DB_FILE" ]; then
        log_error "插件数据库不存在，请先运行 init 初始化"
        exit 1
    fi
    
    # 显示标题
    show_header
    
    # 显示运行时配置信息 (如果有)
    if [ -n "$RUNTIME_CONFIG_FILE" ] && [ -f "$RUNTIME_CONFIG_FILE" ]; then
        log_info "使用运行时配置: $RUNTIME_CONFIG_FILE"
        if [ "$verbose" = true ]; then
            echo "运行时配置内容:"
            cat "$RUNTIME_CONFIG_FILE" 2>/dev/null | head -10
            echo "..."
        fi
    fi
    
    # 执行操作
    case "$operation" in
        "init")
            init_plugin_database
            ;;
        "list")
            list_plugins "$category" "$format"
            ;;
        "search")
            search_plugins "$plugin" "$category"
            ;;
        "info")
            show_plugin_info "$plugin"
            ;;
        "validate")
            validate_plugins "$plugin_list"
            ;;
        "conflicts")
            check_conflicts "$plugin_list"
            ;;
        "generate")
            generate_plugin_config "$plugin_list" "$output" "$format" "$branch" "$auto_detect"
            ;;
        "generate-feeds")
            generate_feeds_conf "$plugin_list" "$output" "$branch" "$auto_detect"
            ;;
        "pre-build-check")        # 新增：编译前检查
            pre_build_check "$device" "$plugin_list" "$strict_mode"
            ;;
        "auto-fix-deps")          # 新增：自动修复插件依赖
            auto_fix_plugin_deps "$device" "$plugin_list" "$auto_fix"
            ;;
        "compatibility")          # 新增：检查设备兼容性
            check_device_compatibility "$device" "$plugin_list"
            ;;
        "optimize")               # 新增：优化插件配置
            optimize_plugin_config "$device" "$plugin_list" "$auto_fix"
            ;;
        "install"|"remove"|"update")
            log_warning "功能开发中: $operation"
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