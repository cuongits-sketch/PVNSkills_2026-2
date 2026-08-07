#!/bin/bash
#
# ==============================================================================
#  int-srv01.sh
#  Bien RIENG & cau hinh CO BAN cho int-srv01.int.pvnskills.org
#  (Hostname, IP tinh INT, Cau hinh co so)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  File nay:
#    - "source" common.sh de dung lai log(), require_root(), setup_hostname(),
#      setup_network(), setup_base(), verify_base() - KHONG dinh nghia lai.
#    - Chi khai bao BIEN RIENG cua int-srv01 (IP, LDAP, CA, Samba, DNS...)
#      de int-srv01-setup.sh tai su dung qua "source int-srv01.sh".
#
#  Co the:
#    (1) Chay TRUC TIEP de tu cai dat phan co ban:
#           bash int-srv01.sh
#    (2) Duoc "source" boi int-srv01-setup.sh de tai su dung bien & ham,
#        khong tu dong chay lai cac buoc cai dat (xem SECTION 4 - MAIN)
#
#  YEU CAU: common.sh phai nam CUNG THU MUC voi int-srv01.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP THU VIEN DUNG CHUNG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    echo "Khong tim thay common.sh cung thu muc voi int-srv01.sh." >&2
    exit 1
fi

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"


# ==============================================================================
# SECTION 2: BIEN RIENG CUA int-srv01
#   Cac bien nay se duoc int-srv01-setup.sh tai su dung qua "source int-srv01.sh"
#   => Sua gia tri O DAY LA DU, khong can sua lai o file int-srv01-setup.sh
# ==============================================================================

FQDN="int-srv01.int.pvnskills.org"

# --- Interface (chi 1 interface duy nhat, khac voi fw co 3) ---
declare -a INTERFACES=(
    "eth0|10.1.10.10/24||2001:db8:1001:10::10/64|"
)

# Dia chi cua chinh may nay - dung lai nhieu noi trong int-srv01-setup.sh
IP4="10.1.10.10"
IP6="2001:db8:1001:10::10"
GW4="10.1.10.1"     # fw (INT)

# --- LDAP - dung lai o int-srv01-setup.sh ---
LDAP_DOMAIN="int.pvnskills.org"
LDAP_BASE_DN="dc=int,dc=pvnskills,dc=org"
LDAP_ADMIN_PW="Skill06@pvnsc"
LDAP_OU="Employees"
LDAP_ORG="PVNSC"

# --- CA (Cơ quan chứng thực) - dung lai o int-srv01-setup.sh ---
CA_DIR="/root/ca"
GRADING_DIR="/opt/grading/ca"
CA_WEB_CN="www.dmz.pvnskills.org"
CA_MAIL_CN="mail.dmz.pvnskills.org"

# --- Samba - dung lai o int-srv01-setup.sh ---
SAMBA_USER="jamie"
SAMBA_PW="Skill06@pvnsc"
SAMBA_PUBLIC_DIR="/srv/samba/public"
SAMBA_INTERNAL_DIR="/srv/samba/internal"

# --- DNS noi bo (BIND9) - dung lai o int-srv01-setup.sh ---
DNS_ZONE_DIR="/etc/bind/zones"
DMZ_DOMAIN="dmz.pvnskills.org"
HA_PRX01_IP4="10.1.20.21"   # DNS Primary cua DMZ - nguon zone transfer secondary


# ==============================================================================
# SECTION 3: HAM DAC TRUNG CUA int-srv01 (neu co)
#   Hien tai int-srv01 khong can them ham "co ban" nao ngoai cac ham
#   da co san trong common.sh - phan nay de trong, du dat de mo rong sau nay
#   (giu nguyen vi tri Section 3 cho DONG BO cau truc voi fw.sh).
# ==============================================================================


# ==============================================================================
# SECTION 4: MAIN
#   Chi TU DONG chay khi file nay duoc goi TRUC TIEP (bash int-srv01.sh).
#   Khi bi "source" boi int-srv01-setup.sh, khoi lenh nay se KHONG chay,
#   chi cac bien/ham o tren duoc nap vao moi truong cua int-srv01-setup.sh.
# ==============================================================================

main() {
    require_root
    setup_hostname      # tu common.sh
    setup_network        # tu common.sh
    setup_base           # tu common.sh
    verify_base           # tu common.sh
    log "Hoan tat phan co ban cua int-srv01. Tiep tuc chay int-srv01-setup.sh de cau hinh dich vu."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
