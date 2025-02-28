#!/bin/bash
# 用法：./patch_mycode.sh /path/to/openwrt /path/to/your/scripts [amd64|arm64]

set -e

# 检查参数
if [ $# -lt 2 ]; then
  echo "用法: $0 /path/to/openwrt /path/to/your/scripts [amd64|arm64]"
  exit 1
fi

OPENWRT_PATH="$1"
SCRIPTS_PATH="$2"
ARCH="${3:-amd64}" # 默认架构为 amd64
PACKAGE_NAME="custom-scripts"
PACKAGE_DIR="$OPENWRT_PATH/package/$PACKAGE_NAME"

# 检查路径是否存在
if [ ! -d "$OPENWRT_PATH" ]; then
  echo "错误: OpenWrt路径不存在: $OPENWRT_PATH"
  exit 1
fi

if [ ! -d "$SCRIPTS_PATH" ]; then
  echo "错误: 脚本文件夹不存在: $SCRIPTS_PATH"
  exit 1
fi

# 检查架构参数
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "arm64" ]; then
  echo "错误: 不支持的架构参数，仅支持 [amd64|arm64]"
  exit 1
fi

# 获取 sing-box 最新稳定版本的下载URL（通过重定向）
REDIRECT_URL=$(curl -s -I -L -o /dev/null -w '%{url_effective}' "https://github.com/SagerNet/sing-box/releases/latest")
LATEST_VERSION=$(echo "$REDIRECT_URL" | grep -o '[^/]*$' | sed 's/^v//')

if [ -z "$LATEST_VERSION" ]; then
  echo "错误: 无法获取 sing-box 最新版本号"
  exit 1
fi

echo "检测到 sing-box 最新版本: $LATEST_VERSION"

# 根据架构选择下载文件
DOWNLOAD_FILE="sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/${DOWNLOAD_FILE}"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
mkdir -p "$TEMP_DIR/sb"
cd "$TEMP_DIR"

# 下载文件
echo "正在下载 $DOWNLOAD_FILE ..."
wget -q "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
  echo "错误: 下载 $DOWNLOAD_FILE 失败"
  rm -rf "$TEMP_DIR"
  exit 1
fi

# 解压文件
echo "正在解压 $DOWNLOAD_FILE ..."
tar -xzf "$DOWNLOAD_FILE" -C sb
if [ $? -ne 0 ]; then
  echo "错误: 解压 $DOWNLOAD_FILE 失败"
  rm -rf "$TEMP_DIR"
  exit 1
fi

# 复制 sing-box 到脚本目录
echo "正在复制 sing-box 到 $SCRIPTS_PATH ..."
cp sb/sing-box-*/sing-box "$SCRIPTS_PATH/"
if [ $? -ne 0 ]; then
  echo "错误: 复制 sing-box 到 $SCRIPTS_PATH 失败"
  rm -rf "$TEMP_DIR"
  exit 1
fi

# 设置可执行权限
chmod +x "$SCRIPTS_PATH/sing-box"

# 清理临时目录
rm -rf "$TEMP_DIR"
echo "操作完成，sing-box 已成功复制到 $SCRIPTS_PATH"

# 创建包目录结构
echo "创建包目录结构..."
mkdir -p "$PACKAGE_DIR/files/etc/init.d"
mkdir -p "$PACKAGE_DIR/files/usr/bin"
mkdir -p "$PACKAGE_DIR/files/etc/sing-box"

# 定义映射关系
declare -A file_mapping
file_mapping["auto_update.sh"]="/usr/bin/"
file_mapping["check_sb.sh"]="/usr/bin/"
file_mapping["singbox"]="/etc/init.d/"
file_mapping["start_singbox.sh"]="/usr/bin/"
file_mapping["stop_singbox.sh"]="/usr/bin/"
file_mapping["config.json"]="/etc/sing-box/"
file_mapping["nft_custom"]="/etc/init.d/"
file_mapping["sec_block.nft"]="/etc/sing-box/"
file_mapping["quic_filter.nft"]="/etc/sing-box/"
file_mapping["sing-box"]="/usr/bin/"

# 初始化一个数组来保存需要启用的init脚本
declare -a init_scripts

# 复制脚本文件
echo "复制脚本文件..."
found_scripts=0

for script in "${!file_mapping[@]}"; do
    source_file="$SCRIPTS_PATH/$script"
    target_dir="$PACKAGE_DIR/files${file_mapping[$script]}"
    
    if [ -f "$source_file" ]; then
        cp "$source_file" "$target_dir"
        
        # 如果目标是/etc/init.d/，则设置为可执行并添加到待启用列表
        if [[ "${file_mapping[$script]}" == "/etc/init.d/" ]]; then
            chmod +x "$target_dir/$script"
            init_scripts+=("$script")
            echo "复制init脚本: $script (将被自动启用)"
        else
            # 如果目标是/usr/bin/，也设置为可执行
            if [[ "${file_mapping[$script]}" == "/usr/bin/" ]]; then
                chmod +x "$target_dir/$script"
            fi
            echo "复制文件: $script 到 ${file_mapping[$script]}"
        fi
        
        found_scripts=1
    else
        echo "警告: 文件不存在: $source_file"
    fi
done

if [ $found_scripts -eq 0 ]; then
    echo "错误: 未找到任何脚本文件"
    exit 1
fi

# 生成Makefile
echo "生成Makefile..."
cat > "$PACKAGE_DIR/Makefile" << 'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=custom-scripts
PKG_VERSION:=1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/custom-scripts
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Custom Scripts
	DEPENDS:=+busybox
endef

define Package/custom-scripts/description
	This package provides custom scripts for sing-box and network filtering.
endef

define Build/Compile
	# 无需编译，直接跳过
endef

define Package/custom-scripts/install
	# 将文件复制到固件中的目标路径
	$(INSTALL_DIR) $(1)/etc/init.d
	[ -n "$(wildcard ./files/etc/init.d/*)" ] && \
		$(INSTALL_BIN) ./files/etc/init.d/* $(1)/etc/init.d/ || true

	$(INSTALL_DIR) $(1)/usr/bin
	[ -n "$(wildcard ./files/usr/bin/*)" ] && \
		$(INSTALL_BIN) ./files/usr/bin/* $(1)/usr/bin/ || true

	$(INSTALL_DIR) $(1)/etc/sing-box
	[ -n "$(wildcard ./files/etc/sing-box/*)" ] && \
		$(CP) ./files/etc/sing-box/* $(1)/etc/sing-box/ || true
endef
EOF

# 添加自动启用init脚本的命令
if [ ${#init_scripts[@]} -gt 0 ]; then
    cat >> "$PACKAGE_DIR/Makefile" << EOF

define Package/custom-scripts/postinst
#!/bin/sh
[ -n "\$\${IPKG_INSTROOT}" ] || {
EOF

    for script in "${init_scripts[@]}"; do
        cat >> "$PACKAGE_DIR/Makefile" << EOF
	/etc/init.d/$script enable
	/etc/init.d/$script start
EOF
    done

    cat >> "$PACKAGE_DIR/Makefile" << EOF
}
exit 0
endef
EOF
fi

# 添加结尾
cat >> "$PACKAGE_DIR/Makefile" << 'EOF'

$(eval $(call BuildPackage,custom-scripts))
EOF

echo "======== 设置完成 =========="
echo "自定义脚本包已创建: $PACKAGE_DIR"
echo ""
echo "以下init脚本将被自动启用:"
for script in "${init_scripts[@]}"; do
    echo "- $script"
done
echo ""
echo "下一步操作:"
echo "1. 进入 OpenWrt 目录: cd $OPENWRT_PATH"
echo "2. 配置并启用自定义包: make menuconfig"
echo "   (在 Utilities -> custom-scripts 中选择该包)"
echo "3. 编译固件: make -j\$(nproc)"
echo ""
echo "注意事项:"
echo "- init.d脚本会在固件首次启动时自动启用和启动"
echo "- 如果你的脚本依赖其他软件包，请修改 $PACKAGE_DIR/Makefile 中的 DEPENDS 行"
echo "============================="
