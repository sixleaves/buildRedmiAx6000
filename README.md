# buildOP4Six
### 一、特性
- 继承sing-box
- 自启动脚本
- 默认的局域网IP断为192.168.31.1/24

### 二、屏蔽恶意IP段
**黑名单**
```bash
nft add element inet security blocklist_ip4_forever { \
  167.94.138.0/24, \
  167.94.145.0/24, \
  167.94.146.0/24, \
  198.235.24.0/24, \
  205.210.31.0/24, \
  64.62.197.0/24,  \
  64.62.156.0/24, \
  80.82.77.0/24, \
  89.248.0.0/16, \
  193.163.125.0/24 \
}
```

```bash
nft add element inet security blocklist_ip4_forever { 185.224.128.0/24}
nft add element inet security blocklist_ip4_forever { 154.213.184.0/24}
nft add element inet security blocklist_ip4_forever { 79.124.58.0/24}
nft add element inet security blocklist_ip4_forever { 79.124.60.0/24}

nft add element inet security blocklist_ip4_forever { 95.214.27.0/24}
nft add element inet security blocklist_ip4_forever { 94.156.66.0/24}
nft add element inet security blocklist_ip4_forever { 94.156.71.0/24}
nft add element inet security blocklist_ip4_forever { 90.151.171.0/24}
nft add element inet security blocklist_ip4_forever { 78.128.114.0/24}
nft add element inet security blocklist_ip4_forever { 91.148.190.166/32}

nft add element inet security blocklist_ip4_forever { 1.63.153.0/24 }
nft add element inet security blocklist_ip4_forever { 1.70.8.0/24 }
nft add element inet security blocklist_ip4_forever { 1.70.126.0/24 }
nft add element inet security blocklist_ip4_forever { 1.70.140.0/24 }
nft add element inet security blocklist_ip4_forever { 1.70.173.0/24 }
nft add element inet security blocklist_ip4_forever { 1.179.220.0/24 }
nft add element inet security blocklist_ip4_forever { 1.215.40.0/24 }
nft add element inet security blocklist_ip4_forever { 4.151.219.0/24 }
nft add element inet security blocklist_ip4_forever { 4.156.237.0/24 }
nft add element inet security blocklist_ip4_forever { 5.8.11.0/24 }
nft add element inet security blocklist_ip4_forever { 5.10.250.0/24 }

nft add element inet security blocklist_ip4_forever { 14.32.68.0/24 }
nft add element inet security blocklist_ip4_forever { 14.103.40.0/24 }
nft add element inet security blocklist_ip4_forever { 15.204.37.0/24 }

```
**白名单**
```bash
nft add element inet security whitelist_ip { 112.26.33.106 }
```
