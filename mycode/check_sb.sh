#!/bin/sh

while true; do
    if ! pgrep sing-box > /dev/null; then
        echo "$(date): Restarting sing-box" >> /tmp/singbox_monitor.log
        /usr/bin/start_singbox.sh
    fi
    sleep 60
done