#!/bin/bash
#
# ==============================================================================
#  mail.sh
#  Bien RIENG & cau hinh CO BAN cho mail.dmz.pvnskills.org
#  (Hostname, IP tinh DMZ, Cau hinh co so)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  File nay:
#    - "source" common.sh de dung lai log(), require_root(), setup_hostname(),
#      setup_network(), setup_base(), verify_base() - KHONG dinh nghia lai.
#    - Chi khai bao BIEN RIENG cua mail (IP, Mail domain, LDAP, CA nguon,
#      Backup, SSH Certificate...) de mail-setup.sh tai su dung.
#
#  Co the:
#    (1) Chay TRUC TIEP de tu cai dat phan co ban:
#           bash mail.sh
#    (2) Duoc "source" boi mail-setup.sh de tai su dung bien & ham,
#        khong tu dong chay lai cac buoc cai dat (xem SECTION 4 - MAIN)
#
#  YEU CAU: common.sh phai nam CUNG THU MUC voi mail.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP THU VIEN DUNG CHUNG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    echo "Khong tim thay common.sh cung thu muc voi mail.sh." >&2
    exit 1
fi

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"


# ==============================================================================
# SECTION 2: BIEN RIENG CUA mail
#   Cac bien nay se duoc mail-setup.sh tai su dung qua "source mail.sh"
#   => Sua gia tri O DAY LA DU, khong can sua lai o file mail-setup.sh
# ==============================================================================

FQDN="mail.dmz.pvnskills.org"

# --- Interface (1 interface DMZ) ---
declare -a INTERFACES=(
    "ens33|10.1.20.10/24||2001:db8:1001:20::10/64|"
)

# Dia chi cua chinh may nay
IP4="10.1.20.10"
IP6="2001:db8:1001:20::10"
GW4="10.1.20.1"     # fw (DMZ)

# --- May nguon chung chi TLS (int-srv01 da tao o buoc CA) ---
CERT_SOURCE_HOST="10.1.10.10"
CERT_SOURCE_MAILCRT="/root/ca/sub-ca/mail-fullchain.crt"
CERT_SOURCE_MAILKEY="/root/ca/sub-ca/mail.key"
CERT_SOURCE_ROOTCA="/root/ca/root-ca/root-ca.crt"

MAIL_CERT="/etc/ssl/certs/mail-fullchain.pem"
MAIL_KEY="/etc/ssl/private/mail.key"
ROOT_CA_CERT="/etc/ssl/certs/pvnsc-root-ca.pem"

# --- LDAP (xac thuc nguoi dung qua int-srv01) ---
LDAP_URI="ldap://10.1.10.10"
LDAP_BASE_DN="ou=Employees,dc=int,dc=pvnskills,dc=org"
LDAP_ADMIN_DN="cn=admin,dc=int,dc=pvnskills,dc=org"
LDAP_ADMIN_PW="Skill06@pvnsc"

# --- Mail domain ---
MAIL_DOMAIN="dmz.pvnskills.org"
ECHO_ADDRESS="echo@${MAIL_DOMAIN}"

# --- Backup ---
BACKUP_DISK="/dev/sdb1"
BACKUP_MOUNT="/opt/backup"
BACKUP_SCRIPT="/opt/backup.sh"

# --- SSH User Certificate (CA duoc tao tren ha-prx01, mail chi TIN TUONG no) ---
SSH_CA_SOURCE_HOST="10.1.20.21"           # ha-prx01
SSH_CA_SOURCE_PATH="/etc/ssh/ca/user_ca.pub"
SSH_CA_LOCAL_PATH="/etc/ssh/user_ca.pub"


# ==============================================================================
# SECTION 3: HAM DAC TRUNG CUA mail (neu co)
#   Hien tai mail khong can them ham "co ban" nao ngoai cac ham
#   da co san trong common.sh - phan nay de trong, du dat de mo rong sau nay
#   (giu nguyen vi tri Section 3 cho DONG BO cau truc voi fw.sh/int-srv01.sh).
# ==============================================================================


# ==============================================================================
# SECTION 4: MAIN
#   Chi TU DONG chay khi file nay duoc goi TRUC TIEP (bash mail.sh).
#   Khi bi "source" boi mail-setup.sh, khoi lenh nay se KHONG chay,
#   chi cac bien/ham o tren duoc nap vao moi truong cua mail-setup.sh.
# ==============================================================================

main() {
    require_root
    setup_hostname      # tu common.sh
    setup_network        # tu common.sh
    setup_base           # tu common.sh
    verify_base           # tu common.sh
    log "Hoan tat phan co ban cua mail. Tiep tuc chay mail-setup.sh de cau hinh dich vu."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
