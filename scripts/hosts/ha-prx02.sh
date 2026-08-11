#!/bin/bash
#
# ==============================================================================
#  ha-prx02.sh
#  Bien RIENG & cau hinh CO BAN cho ha-prx02.dmz.pvnskills.org
#  (Hostname, IP tinh DMZ, Cau hinh co so)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  Vai tro cua may nay: HA Reverse Proxy (BACKUP) + DNS Secondary cho DMZ.
#  Khac voi ha-prx01: KHONG sinh SSH CA (chi ha-prx01 giu CA goc).
#
#  File nay:
#    - "source" common.sh de dung lai log(), require_root(), setup_hostname(),
#      setup_network(), setup_base(), verify_base() - KHONG dinh nghia lai.
#    - Chi khai bao BIEN RIENG cua ha-prx02 de ha-prx02-setup.sh tai su dung.
#
#  Co the:
#    (1) Chay TRUC TIEP de tu cai dat phan co ban:
#           bash ha-prx02.sh
#    (2) Duoc "source" boi ha-prx02-setup.sh de tai su dung bien & ham,
#        khong tu dong chay lai cac buoc cai dat (xem SECTION 4 - MAIN)
#
#  YEU CAU: common.sh phai nam CUNG THU MUC voi ha-prx02.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP THU VIEN DUNG CHUNG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    echo "Khong tim thay common.sh cung thu muc voi ha-prx02.sh." >&2
    exit 1
fi

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"


# ==============================================================================
# SECTION 2: BIEN RIENG CUA ha-prx02
#   Cac bien nay se duoc ha-prx02-setup.sh tai su dung qua "source ha-prx02.sh"
#   => Sua gia tri O DAY LA DU, khong can sua lai o file ha-prx02-setup.sh
# ==============================================================================

FQDN="ha-prx02.dmz.pvnskills.org"

# --- Interface (1 interface DMZ) ---
declare -a INTERFACES=(
    "ens33|10.1.20.22/24||2001:db8:1001:20::22/64|"
)

# Dia chi cua chinh may nay
IP4="10.1.20.22"
IP6="2001:db8:1001:20::22"
GW4="10.1.20.1"     # fw (DMZ)

# --- Virtual IP (VIP) cua HA Reverse Proxy - dung chung voi ha-prx01 ---
VIP4="10.1.20.20"
VIP6="2001:db8:1001:20::20"

# --- Danh sach Web server phia sau (upstream) - giong het ha-prx01 ---
WEB01_IP4="10.1.20.31"
WEB02_IP4="10.1.20.32"
WEB_SERVER_NAME="www.dmz.pvnskills.org"

# --- May nguon chung chi TLS Web (int-srv01 da tao o buoc CA) ---
CERT_SOURCE_HOST="10.1.10.10"
CERT_SOURCE_WEBCRT="/root/ca/sub-ca/web-fullchain.crt"
CERT_SOURCE_WEBKEY="/root/ca/sub-ca/web.key"

WEB_CERT="/etc/ssl/certs/web-fullchain.pem"
WEB_KEY="/etc/ssl/private/web.key"

# --- Keepalived (VRRP) - ha-prx02 la BACKUP (priority thap hon ha-prx01) ---
VRRP_STATE="BACKUP"
VRRP_PRIORITY="100"
VRRP_ROUTER_ID="51"            # PHAI GIONG ha-prx01 de cung 1 nhom VRRP
VRRP_AUTH_PASS="pvnsc2026"     # PHAI GIONG ha-prx01
VRRP_IFACE="eth0"

# --- DNS DMZ (BIND9) - ha-prx02 la Secondary, dong bo tu ha-prx01 ---
DNS_ZONE_DIR="/etc/bind/zones"
DMZ_DOMAIN="dmz.pvnskills.org"
HA_PRX01_IP4="10.1.20.21"      # Primary DNS - nguon zone transfer


# ==============================================================================
# SECTION 3: HAM DAC TRUNG CUA ha-prx02 (neu co)
#   Hien tai ha-prx02 khong can them ham "co ban" nao ngoai cac ham
#   da co san trong common.sh - phan nay de trong, du dat de mo rong sau nay.
# ==============================================================================


# ==============================================================================
# SECTION 4: MAIN
#   Chi TU DONG chay khi file nay duoc goi TRUC TIEP (bash ha-prx02.sh).
#   Khi bi "source" boi ha-prx02-setup.sh, khoi lenh nay se KHONG chay,
#   chi cac bien/ham o tren duoc nap vao moi truong cua ha-prx02-setup.sh.
# ==============================================================================

main() {
    require_root
    setup_hostname      # tu common.sh
    setup_network        # tu common.sh
    setup_base           # tu common.sh
    verify_base           # tu common.sh
    log "Hoan tat phan co ban cua ha-prx02. Tiep tuc chay ha-prx02-setup.sh de cau hinh dich vu."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
