#!/bin/bash
#
# ==============================================================================
#  jamie-pvns01-setup.sh
#  Cau hinh cac THANH PHAN CHINH cho jamie-pvns01.ext.pvnskills.org
#  (GNOME Desktop, Local User jamie, WireGuard Client qua NetworkManager,
#   Firefox, Thunderbird)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  YEU CAU:
#    - jamie-pvns01.sh phai da chay THANH CONG truoc do (hostname, IP WAN
#      da san sang).
#    - fw phai da hoan tat fw-setup.sh (co san khoa WireGuard client tai
#      /etc/wireguard/keys/ tren fw).
#    - Chung chi Root CA duoc fetch qua VPN (sau khi wg0 da ket noi) tu
#      int-srv01 - vi vay ham fetch se CHAY SAU khi WireGuard da len.
#
#  Cach chay (thuc hien TAI CHINH may jamie-pvns01, co man hinh/console):
#     scp common.sh jamie-pvns01.sh jamie-pvns01-setup.sh root@1.1.1.20:/root/
#     ssh root@1.1.1.20 "bash /root/jamie-pvns01.sh && bash /root/jamie-pvns01-setup.sh"
#     (khuyen nghi reboot 1 lan sau khi cai GNOME de vao duoc man hinh dang nhap do hoa)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP BIEN & HAM DUNG CHUNG TU jamie-pvns01.sh (va common.sh)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/jamie-pvns01.sh" ]]; then
    echo "Khong tim thay jamie-pvns01.sh cung thu muc voi jamie-pvns01-setup.sh." >&2
    exit 1
fi

# shellcheck source=jamie-pvns01.sh
source "${SCRIPT_DIR}/jamie-pvns01.sh"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i /root/.ssh/id_ed25519"


# ==============================================================================
# SECTION 2: GNOME DESKTOP + OPEN-VM-TOOLS-DESKTOP
#   Cai moi truong do hoa day du theo yeu cau de thi.
# ==============================================================================

setup_gnome_desktop() {
    log "Cai dat GNOME Desktop Environment (co the mat vai phut, goi lon)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y task-gnome-desktop

    log "Cai dat open-vm-tools-desktop (ho tro resize man hinh VMRC, clipboard...)"
    apt-get install -y open-vm-tools-desktop

    systemctl enable gdm3 2>/dev/null || true
}


# ==============================================================================
# SECTION 3: LOCAL USER "jamie" (dang nhap desktop)
# ==============================================================================

setup_local_user() {
    log "Tao local user desktop: ${LOCAL_USER}"

    if ! id "${LOCAL_USER}" > /dev/null 2>&1; then
        useradd -m -s /bin/bash -c "${LOCAL_USER_FULLNAME}" "${LOCAL_USER}"
        usermod -aG sudo,netdev "${LOCAL_USER}"
    fi

    printf '%s:%s\n' "${LOCAL_USER}" "${LOCAL_USER_PW}" | chpasswd
}


# ==============================================================================
# SECTION 4: WIREGUARD CLIENT - QUA NETWORKMANAGER (nmcli)
#   Lay khoa client + khoa cong khai server + PSK tu fw (qua WAN, truoc khi
#   VPN len), roi tao ket noi WireGuard TRONG NetworkManager va ket noi.
#   Day la yeu cau RIENG cua de thi: dung NetworkManager, KHONG dung
#   wg-quick@wg0 nhu tren fw.
# ==============================================================================

fetch_wg_keys_from_fw() {
    log "Lay khoa WireGuard (client private, server public, PSK) tu fw (${WG_SERVER_HOST})"

    mkdir -p /root/wg-client-keys
    scp ${SSH_OPTS} "root@${WG_SERVER_HOST}:${WG_KEYS_REMOTE_DIR}/client_private.key" /root/wg-client-keys/
    scp ${SSH_OPTS} "root@${WG_SERVER_HOST}:${WG_KEYS_REMOTE_DIR}/server_public.key"   /root/wg-client-keys/
    scp ${SSH_OPTS} "root@${WG_SERVER_HOST}:${WG_KEYS_REMOTE_DIR}/psk.key"             /root/wg-client-keys/
    chmod 600 /root/wg-client-keys/*
}

setup_wireguard_client() {
    log "Cai dat cong cu WireGuard + NetworkManager"
    apt-get install -y network-manager wireguard-tools

    fetch_wg_keys_from_fw

    local client_priv server_pub psk
    client_priv=$(cat /root/wg-client-keys/client_private.key)
    server_pub=$(cat /root/wg-client-keys/server_public.key)
    psk=$(cat /root/wg-client-keys/psk.key)

    log "Tao ket noi WireGuard '${WG_CON_NAME}' trong NetworkManager (nmcli)"

    # Xoa ket noi cu neu da ton tai (chay lai script khong bi loi trung ten)
    nmcli connection delete "${WG_CON_NAME}" > /dev/null 2>&1 || true

    nmcli connection add type wireguard ifname "${WG_CON_NAME}" con-name "${WG_CON_NAME}"

    nmcli connection modify "${WG_CON_NAME}" wireguard.private-key "${client_priv}"

    # Dia chi IP cua chinh client tren tunnel + DNS noi bo (yeu cau de thi)
    nmcli connection modify "${WG_CON_NAME}" \
        ipv4.method manual \
        ipv4.addresses "${WG_CLIENT_ADDR4}" \
        ipv4.dns "${WG_DNS4}" \
        ipv4.ignore-auto-dns yes \
        ipv4.never-default no

    nmcli connection modify "${WG_CON_NAME}" \
        ipv6.method manual \
        ipv6.addresses "${WG_CLIENT_ADDR6}" \
        ipv6.dns "${WG_DNS6}" \
        ipv6.ignore-auto-dns yes

    # Peer (fw) - full-tunnel: allowed-ips 0.0.0.0/0 va ::/0 de dinh tuyen
    # TOAN BO truy cap cua client qua VPN (dung yeu cau de thi)
    nmcli connection modify "${WG_CON_NAME}" +wireguard.peers \
        "public-key = ${server_pub}, endpoint = ${WG_SERVER_HOST}:${WG_SERVER_PORT}, preshared-key = ${psk}, allowed-ips = 0.0.0.0/0;::/0;"

    log "Ket noi WireGuard (nmcli connection up)"
    nmcli connection up "${WG_CON_NAME}"

    # Don dep khoa tam sau khi da nap vao NetworkManager (NM da luu rieng, an toan)
    rm -rf /root/wg-client-keys
}


# ==============================================================================
# SECTION 5: FIREFOX
#   Cai dat, nhap chung chi Root CA, dat trang chu - tat ca qua
#   enterprise policy (policies.json) de KHONG CAN thao tac GUI thu cong.
# ==============================================================================

fetch_root_ca() {
    log "Lay chung chi Root CA tu int-srv01 (qua VPN vua ket noi)"

    local tries=0
    until scp ${SSH_OPTS} "root@${ROOT_CA_SOURCE_HOST}:${ROOT_CA_SOURCE_PATH}" "${ROOT_CA_LOCAL_PATH}" 2>/dev/null; do
        tries=$((tries + 1))
        if [[ ${tries} -ge 5 ]]; then
            log "CANH BAO: khong fetch duoc Root CA sau 5 lan thu - kiem tra lai VPN da len chua (nmcli connection show --active)"
            return 1
        fi
        log "VPN co the chua san sang, thu lai sau 3 giay (lan ${tries}/5)..."
        sleep 3
    done

    log "Cap nhat kho chung chi he thong (dung chung cho ca Firefox/Thunderbird qua NSS)"
    update-ca-certificates
}

setup_firefox() {
    log "Cai dat Firefox ESR"
    apt-get install -y firefox-esr

    fetch_root_ca || true

    log "Cau hinh Firefox qua Enterprise Policy (trang chu + tin tuong Root CA)"
    mkdir -p /etc/firefox/policies

    cat > /etc/firefox/policies/policies.json << EOF
{
  "policies": {
    "Homepage": {
      "URL": "${FIREFOX_HOMEPAGE}",
      "Locked": false,
      "StartPage": "homepage"
    },
    "Certificates": {
      "Install": ["${ROOT_CA_LOCAL_PATH}"]
    }
  }
}
EOF
}


# ==============================================================================
# SECTION 6: THUNDERBIRD
#   Cai dat + tin tuong Root CA qua enterprise policy (giong Firefox).
#   Thiet lap TAI KHOAN EMAIL cho jamie can hoan tat qua GUI Account Wizard
#   (xem huong dan in ra o cuoi ham nay) - day la buoc tuong tac ca nhan,
#   khong nen (va kho) tu dong hoa hoan toan vi lien quan mat khau nguoi dung
#   nhap vao giao dien do hoa.
# ==============================================================================

setup_thunderbird() {
    log "Cai dat Thunderbird"
    apt-get install -y thunderbird

    log "Cau hinh Thunderbird tin tuong Root CA qua Enterprise Policy"
    mkdir -p /etc/thunderbird/policies

    cat > /etc/thunderbird/policies/policies.json << EOF
{
  "policies": {
    "Certificates": {
      "Install": ["${ROOT_CA_LOCAL_PATH}"]
    }
  }
}
EOF

    log "========================================================================"
    log " BUOC THU CONG CON LAI - THIET LAP TAI KHOAN EMAIL CHO ${LOCAL_USER}"
    log "========================================================================"
    log " 1. Dang nhap desktop bang user '${LOCAL_USER}' / mat khau da cau hinh"
    log " 2. Mo Thunderbird -> Account Wizard tu dong hien (hoac vao"
    log "    Menu -> Account Settings -> Account Actions -> Add Mail Account)"
    log " 3. Nhap: Ten = ${LOCAL_USER_FULLNAME}, Email = ${JAMIE_EMAIL},"
    log "    Password = Skill06@pvnsc"
    log " 4. Khi Thunderbird tu do server, chinh lai thu cong neu can:"
    log "      IMAP server : ${IMAP_HOST} - Port 993 - SSL/TLS - Xac thuc thuong"
    log "      SMTP server : ${IMAP_HOST} - Port 587 hoac 465 - STARTTLS/SSL"
    log "    (Root CA da duoc tin tuong san o buoc tren nen se KHONG bao loi chung chi)"
    log "========================================================================"
}


# ==============================================================================
# SECTION 7: KIEM TRA TONG QUAT
# ==============================================================================

verify_services() {
    log "===== TOM TAT KIEM TRA ====="

    echo "--- GNOME / gdm3 ---"
    systemctl is-enabled gdm3 2>/dev/null || echo "  CANH BAO: gdm3 chua enable"

    echo -e "\n--- Local user ${LOCAL_USER} ---"
    id "${LOCAL_USER}" || echo "  CANH BAO: user chua duoc tao"

    echo -e "\n--- WireGuard (NetworkManager) ---"
    nmcli connection show "${WG_CON_NAME}" || echo "  CANH BAO: ket noi ${WG_CON_NAME} chua ton tai"
    nmcli connection show --active | grep "${WG_CON_NAME}" || echo "  CANH BAO: ${WG_CON_NAME} chua active"

    echo -e "\n--- Firefox + Thunderbird ---"
    dpkg -l firefox-esr thunderbird 2>/dev/null | grep '^ii' || echo "  CANH BAO: chua cai dat day du"
    [[ -f /etc/firefox/policies/policies.json ]] && echo "  [OK] Firefox policy da co"
    [[ -f /etc/thunderbird/policies/policies.json ]] && echo "  [OK] Thunderbird policy da co"

    log "Hoan tat cau hinh jamie-pvns01. Dang nhap GUI de hoan tat thiet lap Thunderbird (xem SECTION 6)."
}


# ==============================================================================
# SECTION 8: MAIN
# ==============================================================================

main() {
    require_root
    setup_gnome_desktop
    setup_local_user
    setup_wireguard_client
    setup_firefox
    setup_thunderbird
    verify_services
}

main "$@"
