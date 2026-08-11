#!/bin/bash
#
# ==============================================================================
#  web01.sh
#  Bien RIENG & cau hinh CO BAN cho web01.dmz.pvnskills.org
#  (Hostname, IP tinh DMZ, Cau hinh co so)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  QUAN TRONG: File nay CHI cau hinh phan co so (hostname/IP/goi kiem tra).
#  Nginx + noi dung web (/opt/wwwroot) KHONG duoc cau hinh boi script nay -
#  toan bo duoc trien khai boi ANSIBLE chay tu ha-prx01 (dung yeu cau de thi:
#  "can su dung cong cu Ansible de cau hinh cac may chu web").
#  Xem: /opt/ansible/site.yml (tren ha-prx01) sau khi may nay da co IP/hostname.
#
#  File nay:
#    - "source" common.sh de dung lai log(), require_root(), setup_hostname(),
#      setup_network(), setup_base(), verify_base().
#    - KHONG co file "web01-setup.sh" di kem - vi khong co dich vu phuc tap
#      nao can cau hinh CUC BO tren chinh may nay.
#
#  Cach chay:
#     scp common.sh web01.sh root@10.1.20.31:/root/
#     ssh root@10.1.20.31 "bash /root/web01.sh"
#     (sau do chay Ansible tu ha-prx01, xem ansible/site.yml)
#
#  YEU CAU: common.sh phai nam CUNG THU MUC voi web01.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP THU VIEN DUNG CHUNG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    echo "Khong tim thay common.sh cung thu muc voi web01.sh." >&2
    exit 1
fi

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"


# ==============================================================================
# SECTION 2: BIEN RIENG CUA web01
# ==============================================================================

FQDN="web01.dmz.pvnskills.org"

declare -a INTERFACES=(
    "eth0|10.1.20.31/24||2001:db8:1001:20::31/64|"
)

IP4="10.1.20.31"
IP6="2001:db8:1001:20::31"
GW4="10.1.20.1"     # fw (DMZ)


# ==============================================================================
# SECTION 3: (De trong - khong co ham dac trung, xem ghi chu dau file)
# ==============================================================================


# ==============================================================================
# SECTION 4: MAIN
# ==============================================================================

main() {
    require_root
    setup_hostname
    setup_network
    setup_base
    verify_base
    log "Hoan tat phan co ban cua web01."
    log "Tiep theo: chay Ansible playbook TU ha-prx01 de cai Nginx + trien khai noi dung."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
