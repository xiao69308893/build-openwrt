#!/bin/bash
#========================================================================================================================
# OpenWrt Feeds源管理脚本
# 功能: 根据选择的插件动态配置feeds源
# 用法: ./manage-feeds.sh "插件列表"
#========================================================================================================================

# 插件与feeds源的映射关系
declare -A PLUGIN_FEEDS_MAP=(
    # SSR Plus+
    ["luci-app-ssr-plus"]="src-git helloworld https://github.com/fw876/helloworld"
    
    # PassWall
    ["luci-app-passwall"]="src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages;src-git passwall https://github.com/xiaorouji/openwrt-passwall"
    ["luci-app-passwall2"]="src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2"
    
    # OpenClash
    ["luci-app-openclash"]="src-git openclash https://github.com/vernesong/OpenClash"
    
    # 其他常用插件
    ["luci-app-adguardhome"]="src-git adguardhome https://github.com/rufengsuixing/luci-app-adguardhome"
    ["luci-app-argon"]="src-git argon https://github.com/jerrykuku/luci-theme-argon;src-git argon_config https://github.com/jerrykuku/luci-app-argon-config"
    ["luci-app-vssr"]="src-git vssr https://github.com/jerrykuku/lua-maxminddb;src-git vssr_app https://github.com/jerrykuku/luci-app-vssr"
    ["luci-app-bypass"]="src-git bypass https://github.com/kiddin9/openwrt-bypass"
    ["luci-app-pushbot"]="src-git pushbot https://github.com/zzsj0928/luci-app-pushbot"
    ["luci-app-jd-dailybonus"]="src-git dailybonus https://github.com/jerrykuku/luci-app-jd-dailybonus"
)

# 基础feeds配置
BASE_FEEDS=$(cat << 'EOF'
src-git packages https://github.com/coolsnowwolf/packages
src-git luci https://github.com/coolsnowwolf/luci
src-git routing https://github.com/coolsnowwolf/routing
src-git telephony https://github.com/openwrt/telephony.git
EOF
)

# 解析插件列表
parse_plugins() {
    local plugins_str="$1"
    local -a plugins=()
    
    if [ -n "$plugins_str" ]; then
        IFS=',' read -ra plugins <<< "$plugins_str"
    fi
    
    echo "${plugins[@]}"
}

# 获取插件需要的feeds
get_plugin_feeds() {
    local plugin="$1"
    local feeds="${PLUGIN_FEEDS_MAP[$plugin]}"
    
    if [ -n "$feeds" ]; then
        # 分号分隔多个feeds
        IFS=';' read -ra feed_array <<< "$feeds"
        for feed in "${feed_array[@]}"; do
            echo "$feed"
        done
    fi
}

# 生成feeds.conf.default
generate_feeds_conf() {
    local plugins_str="$1"
    local output_file="${2:-feeds.conf.default}"
    
    # 使用关联数组去重
    declare -A feeds_map
    
    # 添加基础feeds
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            feeds_map["$line"]=1
        fi
    done <<< "$BASE_FEEDS"
    
    # 解析插件列表
    local plugins=($(parse_plugins "$plugins_str"))
    
    # 添加插件对应的feeds
    for plugin in "${plugins[@]}"; do
        local plugin_feeds=$(get_plugin_feeds "$plugin")
        while IFS= read -r feed; do
            if [ -n "$feed" ]; then
                feeds_map["$feed"]=1
            fi
        done <<< "$plugin_feeds"
    done
    
    # 写入文件
    > "$output_file"
    for feed in "${!feeds_map[@]}"; do
        echo "$feed" >> "$output_file"
    done
    
    # 排序（保持基础feeds在前）
    local temp_file=$(mktemp)
    grep "^src-git packages\|^src-git luci\|^src-git routing\|^src-git telephony" "$output_file" > "$temp_file"
    grep -v "^src-git packages\|^src-git luci\|^src-git routing\|^src-git telephony" "$output_file" | sort >> "$temp_file"
    mv "$temp_file" "$output_file"
}

# 显示使用帮助
show_usage() {
    echo "使用方法:"
    echo "  $0 <plugins_list> [output_file]"
    echo ""
    echo "参数:"
    echo "  plugins_list  - 逗号分隔的插件列表"
    echo "  output_file   - 输出文件路径（默认: feeds.conf.default）"
    echo ""
    echo "示例:"
    echo "  $0 'luci-app-ssr-plus,luci-app-dockerman'"
    echo "  $0 'luci-app-passwall,luci-app-openclash' custom_feeds.conf"
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        show_usage
        exit 1
    fi
    
    local plugins_list="$1"
    local output_file="${2:-feeds.conf.default}"
    
    echo "📋 插件列表: $plugins_list"
    echo "📄 输出文件: $output_file"
    echo ""
    
    # 生成feeds配置
    generate_feeds_conf "$plugins_list" "$output_file"
    
    echo "✅ Feeds配置生成完成！"
    echo ""
    echo "📋 生成的feeds配置:"
    echo "================================"
    cat "$output_file"
    echo "================================"
}

# 如果直接执行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi