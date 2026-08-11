#!/bin/bash
#
# ==============================================================================
#  web02.sh
#  Bien RIENG & cau hinh CO BAN cho web02.dmz.pvnskills.org
#  (Hostname, IP tinh DMZ, Cau hinh co so)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  QUAN TRONG - DOC KY:
#  Ban giam khao se KHOI PHUC TRANG THAI BAN DAU cua web02 roi chay:
#      ansible-playbook /opt/ansible/configure-web02.yml
#  tu ha-prx01 de cham diem. Vi vay:
#    - File nay CHI duoc phep chua cau hinh CO SO (hostname/IP) - dung
#      chinh xac dinh nghia "trang thai ban dau" ma giam khao se khoi phuc.
#    - TUYET DOI KHONG tao them file "web02-setup.sh" cai Nginx/noi dung
#      cuc bo tai day - vi giam khao se XOA moi thay doi thu cong ngoai
#      playbook, chi con lai dung nhung gi playbong Ansible tao ra.
#
#  File nay:
#    - "source" common.sh de dung lai log(), require_root(), setup_hostname(),
#      setup_network(), setup_base(), verify_base().
#
#  Cach chay:
#     scp common.sh web02.sh root@10.1.20.32:/root/
#     ssh root@10.1.20.32 "bash /root/web02.sh"
#     (sau do chay: ansible-playbook /opt/ansible/configure-web02.yml TU ha-prx01)
#
#  YEU CAU: common.sh phai nam CUNG THU MUC voi web02.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP THU VIEN DUNG CHUNG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    echo "Khong tim thay common.sh cung thu muc voi web02.sh." >&2
    exit 1
fi

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"


# ==============================================================================
# SECTION 2: BIEN RIENG CUA web02
# ==============================================================================

FQDN="web02.dmz.pvnskills.org"

declare -a INTERFACES=(
    "eth0|10.1.20.32/24||2001:db8:1001:20::32/64|"
)

IP4="10.1.20.32"
IP6="2001:db8:1001:20::32"
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
    log "Hoan tat phan co ban cua web02 (day chinh la 'trang thai ban dau')."
    log "Tiep theo: chay 'ansible-playbook /opt/ansible/configure-web02.yml' TU ha-prx01."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
