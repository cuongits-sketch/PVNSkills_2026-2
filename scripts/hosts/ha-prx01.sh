#!/bin/bash
#
# ==============================================================================
#  ha-prx01.sh
#  Bien RIENG & cau hinh CO BAN cho ha-prx01.dmz.pvnskills.org
#  (Hostname, IP tinh DMZ, Cau hinh co so)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  Vai tro cua may nay: HA Reverse Proxy (MASTER) + DNS Primary cho DMZ +
#  SSH CA (sinh khoa CA de mail.dmz.pvnskills.org tin tuong).
#
#  File nay:
#    - "source" common.sh de dung lai log(), require_root(), setup_hostname(),
#      setup_network(), setup_base(), verify_base() - KHONG dinh nghia lai.
#    - Chi khai bao BIEN RIENG cua ha-prx01 de ha-prx01-setup.sh tai su dung.
#
#  Co the:
#    (1) Chay TRUC TIEP de tu cai dat phan co ban:
#           bash ha-prx01.sh
#    (2) Duoc "source" boi ha-prx01-setup.sh de tai su dung bien & ham,
#        khong tu dong chay lai cac buoc cai dat (xem SECTION 4 - MAIN)
#
#  YEU CAU: common.sh phai nam CUNG THU MUC voi ha-prx01.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP THU VIEN DUNG CHUNG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    echo "Khong tim thay common.sh cung thu muc voi ha-prx01.sh." >&2
    exit 1
fi

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"


# ==============================================================================
# SECTION 2: BIEN RIENG CUA ha-prx01
#   Cac bien nay se duoc ha-prx01-setup.sh tai su dung qua "source ha-prx01.sh"
#   => Sua gia tri O DAY LA DU, khong can sua lai o file ha-prx01-setup.sh
# ==============================================================================

FQDN="ha-prx01.dmz.pvnskills.org"

# --- Interface (1 interface DMZ) ---
declare -a INTERFACES=(
    "ens192|10.1.20.21/24||2001:db8:1001:20::21/64|"
)

# Dia chi cua chinh may nay
IP4="10.1.20.21"
IP6="2001:db8:1001:20::21"
GW4="10.1.20.1"     # fw (DMZ)

# --- Virtual IP (VIP) cua HA Reverse Proxy - dung chung voi ha-prx02 ---
VIP4="10.1.20.20"
VIP6="2001:db8:1001:20::20"

# --- Danh sach Web server phia sau (upstream) ---
WEB01_IP4="10.1.20.31"
WEB02_IP4="10.1.20.32"
WEB_SERVER_NAME="www.dmz.pvnskills.org"

# --- May nguon chung chi TLS Web (int-srv01 da tao o buoc CA) ---
CERT_SOURCE_HOST="10.1.10.10"
CERT_SOURCE_WEBCRT="/root/ca/sub-ca/web-fullchain.crt"
CERT_SOURCE_WEBKEY="/root/ca/sub-ca/web.key"

WEB_CERT="/etc/ssl/certs/web-fullchain.pem"
WEB_KEY="/etc/ssl/private/web.key"

# --- Keepalived (VRRP) - ha-prx01 la MASTER (priority cao hon ha-prx02) ---
VRRP_STATE="MASTER"
VRRP_PRIORITY="150"
VRRP_ROUTER_ID="51"
VRRP_AUTH_PASS="pvnsc2026"
VRRP_IFACE="ens192"

# --- DNS DMZ (BIND9) - ha-prx01 la Primary ---
DNS_ZONE_DIR="/etc/bind/zones"
DMZ_DOMAIN="dmz.pvnskills.org"
HA_PRX02_IP4="10.1.20.22"      # Secondary DNS #1 (nhan zone transfer)
INT_SRV01_IP4="10.1.10.10"     # Secondary DNS #2 (nhan zone transfer)

# --- SSH CA (proof-of-concept: chi dung de SSH toi mail server) ---
SSH_CA_DIR="/etc/ssh/ca"
MAIL_HOST_IP="10.1.20.10"


# ==============================================================================
# SECTION 3: HAM DAC TRUNG CUA ha-prx01 (neu co)
#   Hien tai ha-prx01 khong can them ham "co ban" nao ngoai cac ham
#   da co san trong common.sh - phan nay de trong, du dat de mo rong sau nay.
# ==============================================================================


# ==============================================================================
# SECTION 4: MAIN
#   Chi TU DONG chay khi file nay duoc goi TRUC TIEP (bash ha-prx01.sh).
#   Khi bi "source" boi ha-prx01-setup.sh, khoi lenh nay se KHONG chay,
#   chi cac bien/ham o tren duoc nap vao moi truong cua ha-prx01-setup.sh.
# ==============================================================================

main() {
    require_root
    setup_hostname      # tu common.sh
    setup_network        # tu common.sh
    setup_base           # tu common.sh
    verify_base           # tu common.sh
    log "Hoan tat phan co ban cua ha-prx01. Tiep tuc chay ha-prx01-setup.sh de cau hinh dich vu."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
