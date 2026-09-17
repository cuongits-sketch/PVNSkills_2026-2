#!/bin/bash
#
# ==============================================================================
#  verify-prx-vrrp.sh
#  Script KIEM TRA (khong phai cai dat) cho prx-vrrp.dmz.pvnskills.org
#
#  LUU Y QUAN TRONG: prx-vrrp KHONG PHAI mot may chu rieng - day la VIRTUAL
#  IP (VIP) duoc ha-prx01 va ha-prx02 cung quan ly qua Keepalived (VRRP).
#  Khong co he dieu hanh rieng de cai dat/hostname cho "may" nay.
#
#  Script nay CO THE chay tu bat ky may nao co the tiep can duoc DMZ
#  (int-srv01, fw, hoac chinh ha-prx01/02) de xac nhan toan bo chuoi:
#    - DNS tra ve dung ban ghi cho prx-vrrp va www (CNAME)
#    - VIP dang duoc 1 trong 2 may (ha-prx01/ha-prx02) giu
#    - HTTP/HTTPS qua VIP hoat dong dung (redirect, header, chung chi)
#    - Failover: tat nginx tren may dang la MASTER, VIP phai chuyen sang
#      may con lai trong vai giay, dich vu KHONG bi gian doan
#
#  Cach chay:
#     bash verify-prx-vrrp.sh
# ==============================================================================

set -uo pipefail   # KHONG dung set -e o day - muon script chay het tat ca
                    # buoc kiem tra du co buoc nao "that bai" giua chung

VIP4="10.1.20.20"
DMZ_DOMAIN="dmz.pvnskills.org"
HA_PRX01_IP="10.1.20.21"
HA_PRX02_IP="10.1.20.22"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i /root/.ssh/id_ed25519"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [[ "${result}" -eq 0 ]]; then
        echo "  [OK]   ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${desc}"
        FAIL=$((FAIL + 1))
    fi
}


# ==============================================================================
# SECTION 1: KIEM TRA DNS
# ==============================================================================

echo "===== 1. KIEM TRA DNS ====="

dig +short "prx-vrrp.${DMZ_DOMAIN}" A | grep -q "${VIP4}"
check "prx-vrrp.${DMZ_DOMAIN} A -> ${VIP4}" $?

dig +short "www.${DMZ_DOMAIN}" CNAME | grep -q "prx-vrrp.${DMZ_DOMAIN}"
check "www.${DMZ_DOMAIN} CNAME -> prx-vrrp.${DMZ_DOMAIN}" $?


# ==============================================================================
# SECTION 2: XAC DINH MAY NAO DANG GIU VIP (MASTER hien tai)
# ==============================================================================

echo -e "\n===== 2. XAC DINH MASTER HIEN TAI ====="

CURRENT_MASTER=""
if ssh ${SSH_OPTS} "root@${HA_PRX01_IP}" "ip addr show | grep -q ${VIP4}" 2>/dev/null; then
    CURRENT_MASTER="ha-prx01"
elif ssh ${SSH_OPTS} "root@${HA_PRX02_IP}" "ip addr show | grep -q ${VIP4}" 2>/dev/null; then
    CURRENT_MASTER="ha-prx02"
fi

if [[ -n "${CURRENT_MASTER}" ]]; then
    echo "  [OK]   VIP dang duoc giu boi: ${CURRENT_MASTER}"
    PASS=$((PASS + 1))
else
    echo "  [FAIL] Khong may nao dang giu VIP ${VIP4} - kiem tra lai Keepalived tren ca 2 may"
    FAIL=$((FAIL + 1))
fi


# ==============================================================================
# SECTION 3: KIEM TRA HTTP/HTTPS QUA VIP
# ==============================================================================

echo -e "\n===== 3. KIEM TRA HTTP/HTTPS QUA VIP ====="

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "http://${VIP4}/")
[[ "${HTTP_CODE}" == "301" ]]
check "HTTP (80) tra ve 301 redirect sang HTTPS (nhan duoc: ${HTTP_CODE})" $?

VIA_HEADER=$(curl -sk -m 5 -I "https://${VIP4}/" -H "Host: www.${DMZ_DOMAIN}" | grep -i "via-proxy" || true)
[[ -n "${VIA_HEADER}" ]]
check "Header via-proxy xuat hien trong response HTTPS (${VIA_HEADER:-khong thay})" $?

CERT_ISSUER=$(echo | openssl s_client -connect "${VIP4}:443" -servername "www.${DMZ_DOMAIN}" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || true)
echo "  [INFO] Issuer chung chi HTTPS: ${CERT_ISSUER:-khong lay duoc}"


# ==============================================================================
# SECTION 4: KIEM TRA FAILOVER (tat nginx tren MASTER hien tai, cho VIP chuyen)
# ==============================================================================

echo -e "\n===== 4. KIEM TRA FAILOVER (co the mat khoang 5-10 giay) ====="

if [[ -n "${CURRENT_MASTER}" ]]; then
    MASTER_IP="${HA_PRX01_IP}"
    [[ "${CURRENT_MASTER}" == "ha-prx02" ]] && MASTER_IP="${HA_PRX02_IP}"

    echo "  -> Dang tat tam thoi nginx tren ${CURRENT_MASTER} (${MASTER_IP}) de mo phong su co..."
    ssh ${SSH_OPTS} "root@${MASTER_IP}" "systemctl stop nginx" 2>/dev/null

    sleep 6

    NEW_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "http://${VIP4}/")
    [[ "${NEW_HTTP_CODE}" == "301" ]]
    check "Sau khi ${CURRENT_MASTER} bi tat, VIP van phan hoi HTTP binh thuong (nhan duoc: ${NEW_HTTP_CODE})" $?

    echo "  -> Khoi dong lai nginx tren ${CURRENT_MASTER} de tra ve trang thai ban dau..."
    ssh ${SSH_OPTS} "root@${MASTER_IP}" "systemctl start nginx" 2>/dev/null
else
    echo "  [SKIP] Bo qua buoc failover vi khong xac dinh duoc MASTER hien tai o Section 2"
fi


# ==============================================================================
# SECTION 5: TOM TAT KET QUA
# ==============================================================================

echo -e "\n===== TOM TAT ====="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"

if [[ "${FAIL}" -eq 0 ]]; then
    echo "  => TOAN BO kiem tra prx-vrrp (VIP) deu PASS."
    exit 0
else
    echo "  => CO ${FAIL} muc kiem tra FAIL - xem lai ha-prx01-setup.sh / ha-prx02-setup.sh."
    exit 1
fi
