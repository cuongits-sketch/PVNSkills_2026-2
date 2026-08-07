#!/bin/bash
#
# ==============================================================================
#  common.sh
#  Thu vien HAM DUNG CHUNG cho MOI may chu trong project PVNSkills 2026
#  (fw, int-srv01, mail, ha-prx01, ha-prx02, web01, web02, jamie-pvns01...)
#
#  File nay CHI dinh nghia ham, KHONG chua bien rieng (FQDN, IP...) va
#  KHONG tu chay gi ca - luon duoc "source" boi file rieng cua tung may
#  (vi du: fw.sh, int-srv01.sh, mail.sh...).
#
#  Cach dung trong file rieng cua tung may:
#     source "$(dirname "$0")/common.sh"
#     FQDN="int-srv01.int.pvnskills.org"
#     declare -a INTERFACES=( "eth0|10.1.10.10/24||2001:db8:1001:10::10/64|" )
#     setup_hostname
#     setup_network
#     setup_base
# ==============================================================================

# Khong dat "set -euo pipefail" o day - de file goi (fw.sh, int-srv01.sh...)
# tu quyet dinh che do loi cua chinh no, tranh xung dot khi source lan nhau.


# ==============================================================================
# SECTION 1: HAM TIEN ICH (log, kiem tra quyen root)
# ==============================================================================

log() {
    echo -e "\n\033[1;34m==>\033[0m $*"
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Script nay phai chay bang quyen root." >&2
        exit 1
    fi
}


# ==============================================================================
# SECTION 2: HOSTNAME
#   Yeu cau bien: FQDN (vi du "int-srv01.int.pvnskills.org")
# ==============================================================================

setup_hostname() {
    : "${FQDN:?Bien FQDN chua duoc khai bao truoc khi goi setup_hostname}"

    log "Dat hostname: ${FQDN}"
    hostnamectl set-hostname "${FQDN}"
    sed -i "s/^127.0.1.1.*/127.0.1.1\t${FQDN} ${FQDN%%.*}/" /etc/hosts
}


# ==============================================================================
# SECTION 3: CAU HINH MANG - IP TINH (ap dung cho 1 hoac nhieu interface)
#   Yeu cau bien: mang INTERFACES, moi phan tu dang:
#     "iface|ip4/cidr|gateway4|ip6/cidr|gateway6"
#   (gateway4/gateway6 co the de rong "" neu interface khong can default route)
#
#   Vi du may 1 interface (int-srv01):
#     declare -a INTERFACES=(
#         "eth0|10.1.10.10/24||2001:db8:1001:10::10/64|"
#     )
#
#   Vi du may nhieu interface (fw):
#     declare -a INTERFACES=(
#         "eth0|1.1.1.10/24|1.1.1.1|2001:db8:1111::10/64|2001:db8:1111::1"
#         "eth1|10.1.10.1/24||2001:db8:1001:10::1/64|"
#         "eth2|10.1.20.1/24||2001:db8:1001:20::1/64|"
#     )
# ==============================================================================

setup_network() {
    if [[ -z "${INTERFACES+x}" ]] || [[ "${#INTERFACES[@]}" -eq 0 ]]; then
        echo "Mang INTERFACES chua duoc khai bao truoc khi goi setup_network" >&2
        exit 1
    fi

    log "Cau hinh IP tinh cho ${#INTERFACES[@]} interface (dual-stack IPv4 + IPv6)"

    local iface_file="/etc/network/interfaces.d/main"
    : > "${iface_file}"   # lam rong file truoc khi ghi, tranh cau hinh cu chong lan

    for entry in "${INTERFACES[@]}"; do
        IFS='|' read -r IFACE IP4 GW4 IP6 GW6 <<< "${entry}"

        {
            echo "auto ${IFACE}"
            echo "iface ${IFACE} inet static"
            echo "    address ${IP4}"
            [[ -n "${GW4}" ]] && echo "    gateway ${GW4}"
            echo
            echo "iface ${IFACE} inet6 static"
            echo "    address ${IP6}"
            [[ -n "${GW6}" ]] && echo "    gateway ${GW6}"
            echo
        } >> "${iface_file}"
    done

    systemctl restart networking
}


# ==============================================================================
# SECTION 4: CAU HINH CO SO HE THONG
#   (timezone, locale, keymap, goi cong cu kiem tra bat buoc)
#   KHONG can bien rieng - giong het nhau tren MOI may theo yeu cau de thi.
# ==============================================================================

setup_base() {
    log "Cau hinh timezone, locale, keymap"
    timedatectl set-timezone Asia/Ho_Chi_Minh
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
    update-locale LANG=en_US.UTF-8
    localectl set-keymap us

    log "Cai dat bo cong cu kiem tra bat buoc (theo yeu cau de thi)"
    apt update
    apt install -y smbclient curl lynx dnsutils ldap-utils ftp lftp wget \
        openssh-client nfs-common rsync telnet traceroute tcptraceroute tcpdump
}


# ==============================================================================
# SECTION 5: KIEM TRA NHANH PHAN CO BAN
#   Dung chung cho moi may - chi in ra thong tin, khong phu thuoc bien rieng
#   ngoai FQDN (da duoc dat truoc do qua setup_hostname).
# ==============================================================================

verify_base() {
    log "===== KIEM TRA NHANH PHAN CO BAN ====="

    echo "--- Hostname ---"
    hostname -f

    echo -e "\n--- Dia chi IP ---"
    ip -4 addr show | grep -E "inet |^[0-9]+:"
    ip -6 addr show | grep -E "inet6 |^[0-9]+:"

    echo -e "\n--- Timezone ---"
    timedatectl | grep "Time zone"

    log "Hoan tat phan co ban."
}
