#!/bin/bash

# ha-prx02.sh - Chỉ khai báo biến riêng + gọi hàm chung

source "$(dirname "$0")/../lib/common.sh"

HOSTNAME="ha-prx02"
IP_ADDRESS="192.168.1.31"
GATEWAY="192.168.1.1"
TIMEZONE="Asia/Ho_Chi_Minh"

set_hostname "$HOSTNAME"
set_ip "eth0" "$IP_ADDRESS" "$GATEWAY"
set_timezone "$TIMEZONE"
