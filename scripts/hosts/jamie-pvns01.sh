#!/bin/bash
#
# ==============================================================================
#  jamie-pvns01.sh
#  Bien RIENG & cau hinh CO BAN cho jamie-pvns01.ext.pvnskills.org
#  (Hostname, IP tinh WAN, Cau hinh co so)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  Vai tro cua may nay: May tram truy cap tu xa cho PVNSC CEO (GNOME,
#  WireGuard Client qua NetworkManager, Firefox, Thunderbird).
#
#  LUU Y: May nay CHI cau hinh 1 interface vat ly (WAN). Interface VPN (wg0)
#  KHONG duoc khai bao qua /etc/network/interfaces (khac voi fw) - vi de thi
#  yeu cau ro "thiet lap ket noi WireGuard trong NetworkManager", nen wg0
#  se duoc NetworkManager tu quan ly hoan toan qua nmcli o jamie-pvns01-setup.sh.
#
#  File nay:
#    - "source" common.sh de dung lai log(), require_root(), setup_hostname(),
#      setup_network(), setup_base(), verify_base().
#    - Chi khai bao BIEN RIENG de jamie-pvns01-setup.sh tai su dung.
#
#  Co the:
#    (1) Chay TRUC TIEP de tu cai dat phan co ban:
#           bash jamie-pvns01.sh
#    (2) Duoc "source" boi jamie-pvns01-setup.sh (xem SECTION 4 - MAIN)
#
#  YEU CAU: common.sh phai nam CUNG THU MUC voi jamie-pvns01.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP THU VIEN DUNG CHUNG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    echo "Khong tim thay common.sh cung thu muc voi jamie-pvns01.sh." >&2
    exit 1
fi

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"


# ==============================================================================
# SECTION 2: BIEN RIENG CUA jamie-pvns01
#   Cac bien nay se duoc jamie-pvns01-setup.sh tai su dung
#   => Sua gia tri O DAY LA DU, khong can sua lai o file setup
# ==============================================================================

FQDN="jamie-pvns01.ext.pvnskills.org"

# --- Interface (chi WAN - wg0 do NetworkManager quan ly, khong khai bao o day) ---
declare -a INTERFACES=(
    "ens33|1.1.1.20/24|1.1.1.1|2001:db8:1111::20/64|2001:db8:1111::1"
)

IP4="1.1.1.20"
IP6="2001:db8:1111::20"

# --- Local user desktop (theo yeu cau de thi, Phan 4) ---
LOCAL_USER="jamie"
LOCAL_USER_FULLNAME="Jamie Oliver"
LOCAL_USER_PW="Skill06@pvnsc"

# --- WireGuard Client - lay khoa tu fw qua WAN (fw da sinh san o fw-setup.sh) ---
WG_SERVER_HOST="1.1.1.10"          # fw, dia chi WAN (truoc khi co VPN)
WG_SERVER_PORT="51820"
WG_KEYS_REMOTE_DIR="/etc/wireguard/keys"
WG_CLIENT_ADDR4="10.1.30.2/24"
WG_CLIENT_ADDR6="2001:db8:1001:30::2/64"
WG_DNS4="10.1.10.10"                # int-srv01 - DNS noi bo
WG_DNS6="2001:db8:1001:10::10"
WG_CON_NAME="wg0"

# --- Trinh duyet & Mail client ---
FIREFOX_HOMEPAGE="https://www.dmz.pvnskills.org"
ROOT_CA_SOURCE_HOST="10.1.10.10"           # int-srv01 (qua VPN, sau khi wg0 da len)
ROOT_CA_SOURCE_PATH="/opt/grading/ca/ca.pem"
ROOT_CA_LOCAL_PATH="/usr/local/share/ca-certificates/pvnsc-root-ca.crt"

IMAP_HOST="mail.dmz.pvnskills.org"
JAMIE_EMAIL="jamie.oliver@dmz.pvnskills.org"


# ==============================================================================
# SECTION 3: (De trong - khong co ham dac trung o file bien, xem setup.sh)
# ==============================================================================


# ==============================================================================
# SECTION 4: MAIN
#   Chi TU DONG chay khi file nay duoc goi TRUC TIEP.
# ==============================================================================

main() {
    require_root
    setup_hostname
    setup_network
    setup_base
    verify_base
    log "Hoan tat phan co ban cua jamie-pvns01. Tiep tuc chay jamie-pvns01-setup.sh."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
