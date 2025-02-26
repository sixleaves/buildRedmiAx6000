#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# Custom for REDMI AX6000
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate
ls target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7986a-xiaomi-redmi-router-ax6000.dtsi
cp $GITHUB_WORKSPACE/hanwckf/Redmi-AX6000/data/mt7986a-xiaomi-redmi-router-ax6000.dtsi target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/
cat > package/base-files/files/etc/banner << EOF
  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__| W I R E L E S S   F R E E D O M
 -----------------------------------------------------
 %D %V, %C
 -----------------------------------------------------
EOF