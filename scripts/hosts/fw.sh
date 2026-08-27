#!/bin/bash
#
# ==============================================================================
#  fw.sh
#  Bien RIENG & cau hinh DAC TRUNG cho fw.pvnskills.org
#  (Hostname, IP tinh WAN/INT/DMZ, Cau hinh co so, IP Forwarding)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  File nay:
#    - "source" common.sh de dung lai log(), require_root(), setup_hostname(),
#      setup_network(), setup_base(), verify_base() - KHONG dinh nghia lai.
#    - Chi khai bao BIEN RIENG cua fw (IP, VIP, WireGuard, Squid...) va
#      HAM DAC TRUNG khong may nao khac can (setup_forwarding).
#
#  Co the:
#    (1) Chay TRUC TIEP de tu cai dat phan co ban cua fw:
#           bash fw.sh
#    (2) Duoc "source" boi fw-setup.sh de tai su dung bien & ham,
#        khong tu dong chay lai cac buoc cai dat (xem SECTION 4 - MAIN)
#
#  YEU CAU: common.sh phai nam CUNG THU MUC voi fw.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP THU VIEN DUNG CHUNG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    echo "Khong tim thay common.sh cung thu muc voi fw.sh." >&2
    exit 1
fi

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"


# ==============================================================================
# SECTION 2: BIEN RIENG CUA fw
#   Cac bien nay se duoc fw-setup.sh tai su dung qua lenh "source fw.sh"
#   => Sua gia tri O DAY LA DU, khong can sua lai o file fw-setup.sh
# ==============================================================================

FQDN="fw.pvnskills.org"

# --- Interface vat ly (3 interface - khac voi cac may khac chi co 1) ---
# Dinh dang moi phan tu: "iface|ip4/cidr|gateway4|ip6/cidr|gateway6"
# Chi WAN co gateway (default route) - INT/DMZ de trong de tranh xung dot route.
declare -a INTERFACES=(
    "ens33|1.1.1.10/24|1.1.1.1|2001:db8:1111::10/64|2001:db8:1111::1"   # WAN
    "ens37|10.1.10.1/24||2001:db8:1001:10::1/64|"                        # INT
    "ens38|10.1.20.1/24||2001:db8:1001:20::1/64|"                        # DMZ
)

# Ten interface dung lai trong fw-setup.sh (nftables/wireguard)
IF_WAN="ens33"
IF_INT="ens37"
IF_DMZ="ens38"
IF_VPN="wg0"

# --- Virtual IP (VIP) cua HA Reverse Proxy trong DMZ - dung lai o fw-setup.sh ---
VIP4="10.1.20.20"
VIP6="2001:db8:1001:20::20"

# --- Thong so WireGuard - dung lai o fw-setup.sh ---
WG_PORT="51820"
WG_ADDR4="10.1.30.1/24"
WG_ADDR6="2001:db8:1001:30::1/64"
WG_CLIENT_ADDR4="10.1.30.2/32"
WG_CLIENT_ADDR6="2001:db8:1001:30::2/128"

# --- Thong so Transparent Proxy - dung lai o fw-setup.sh ---
SQUID_INTERCEPT_PORT="3129"


# ==============================================================================
# SECTION 3: HAM DAC TRUNG CUA fw (KHONG co trong common.sh)
#   IP Forwarding chi can thiet tren fw (vai tro router) - cac may con lai
#   (int-srv01, mail, ha-prx01/02, web01/02) KHONG can bat forwarding,
#   nen ham nay dat o day, khong dua vao common.sh.
# ==============================================================================

setup_forwarding() {
    log "Bat IP Forwarding (IPv4 & IPv6), luu vinh vien qua sysctl"

    cat > /etc/sysctl.d/99-forwarding.conf << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

    sysctl --system
}

verify_forwarding() {
    echo -e "\n--- IP Forwarding ---"
    sysctl net.ipv4.ip_forward
    sysctl net.ipv6.conf.all.forwarding
}


# ==============================================================================
# SECTION 4: MAIN
#   Chi TU DONG chay khi file nay duoc goi TRUC TIEP (bash fw.sh).
#   Khi bi "source" boi fw-setup.sh, khoi lenh nay se KHONG chay,
#   chi cac bien/ham o tren duoc nap vao moi truong cua fw-setup.sh.
# ==============================================================================

main() {
    require_root
    setup_hostname      # tu common.sh
    setup_network       # tu common.sh
    setup_base          # tu common.sh
    setup_forwarding    # rieng cua fw.sh
    verify_base         # tu common.sh
    verify_forwarding   # rieng cua fw.sh
    log "Hoan tat phan co ban cua fw. Tiep tuc chay fw-setup.sh de cau hinh dich vu."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
