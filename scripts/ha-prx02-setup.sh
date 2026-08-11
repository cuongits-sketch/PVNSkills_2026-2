#!/bin/bash
#
# ==============================================================================
#  ha-prx02-setup.sh
#  Cau hinh cac DICH VU CHINH (phuc tap) cho ha-prx02.dmz.pvnskills.org
#  (HA Reverse Proxy - Keepalived BACKUP + Nginx, DNS DMZ Secondary - BIND9)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  YEU CAU:
#    - ha-prx02.sh phai da chay THANH CONG truoc do (hostname, IP da san sang).
#    - int-srv01 phai da hoan tat buoc CA (de co /root/ca/sub-ca/web*.{crt,key}).
#    - ha-prx01 nen da hoan tat truoc (de co du lieu zone dmz.pvnskills.org
#      cho ha-prx02 dong bo qua zone transfer). Neu chua, BIND9 se log loi
#      "transfer failed" nhung KHONG lam hong service - se tu dong retry
#      va dong bo thanh cong ngay khi ha-prx01 san sang.
#
#  Cach chay:
#     scp common.sh ha-prx02.sh ha-prx02-setup.sh root@10.1.20.22:/root/
#     ssh root@10.1.20.22 "bash /root/ha-prx02.sh && bash /root/ha-prx02-setup.sh"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP BIEN & HAM DUNG CHUNG TU ha-prx02.sh (va common.sh)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/hosts/ha-prx02.sh" ]]; then
    echo "Khong tim thay ha-prx02.sh cung thu muc voi ha-prx02-setup.sh." >&2
    exit 1
fi

# shellcheck source=ha-prx02.sh
source "${SCRIPT_DIR}/hosts/ha-prx02.sh"
# Luu y: "source" o tren KHONG lam chay main() cua ha-prx02.sh,
# vi ha-prx02.sh chi tu goi main() khi duoc thuc thi truc tiep

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i /root/.ssh/id_ed25519"


# ==============================================================================
# SECTION 2: HA REVERSE PROXY - KEEPALIVED (BACKUP) + NGINX
#   Cau hinh giong het ha-prx01 ve mat Nginx (cung upstream, cung chung chi),
#   chi khac trang thai Keepalived (BACKUP thay vi MASTER, priority thap hon).
# ==============================================================================

fetch_web_cert_from_int_srv01() {
    log "Lay chung chi Web TLS tu int-srv01 (${CERT_SOURCE_HOST})"

    mkdir -p /etc/ssl/private
    chmod 700 /etc/ssl/private

    scp ${SSH_OPTS} "root@${CERT_SOURCE_HOST}:${CERT_SOURCE_WEBCRT}" "${WEB_CERT}"
    scp ${SSH_OPTS} "root@${CERT_SOURCE_HOST}:${CERT_SOURCE_WEBKEY}" "${WEB_KEY}"

    chmod 600 "${WEB_KEY}"
    chown root:root "${WEB_KEY}"
}

setup_reverse_proxy() {
    log "Cai dat Nginx"
    apt-get install -y nginx

    fetch_web_cert_from_int_srv01

    log "Ghi cau hinh Nginx reverse proxy (header via-proxy: ${FQDN%%.*})"
    rm -f /etc/nginx/sites-enabled/default

    cat > /etc/nginx/sites-available/reverse-proxy << EOF
upstream backend_web {
    server ${WEB01_IP4}:80;
    server ${WEB02_IP4}:80;
}

# Redirect toan bo HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${WEB_SERVER_NAME};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${WEB_SERVER_NAME};

    ssl_certificate     ${WEB_CERT};
    ssl_certificate_key ${WEB_KEY};

    location / {
        proxy_pass http://backend_web;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        add_header via-proxy "${FQDN%%.*}" always;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/reverse-proxy /etc/nginx/sites-enabled/reverse-proxy

    nginx -t
    systemctl restart nginx
    systemctl enable nginx
}

setup_keepalived() {
    log "Cai dat Keepalived (VRRP - trang thai ${VRRP_STATE}, priority ${VRRP_PRIORITY})"
    apt-get install -y keepalived

    cat > /etc/keepalived/keepalived.conf << EOF
vrrp_script chk_nginx {
    script "/usr/bin/pgrep nginx"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state ${VRRP_STATE}
    interface ${VRRP_IFACE}
    virtual_router_id ${VRRP_ROUTER_ID}
    priority ${VRRP_PRIORITY}
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass ${VRRP_AUTH_PASS}
    }

    virtual_ipaddress {
        ${VIP4}/24
    }
    virtual_ipaddress_excl {
        ${VIP6}/64
    }

    track_script {
        chk_nginx
    }
}
EOF

    systemctl restart keepalived
    systemctl enable keepalived
}


# ==============================================================================
# SECTION 3: DNS DMZ - BIND9 (SECONDARY)
#   Dong bo TU DONG (zone transfer) tu ha-prx01 - KHONG duoc chuyen thu cong
#   theo dung yeu cau de thi. TU CHOI truy van de quy, giong ha-prx01.
# ==============================================================================

setup_dns_secondary() {
    log "Cai dat BIND9 (DNS Secondary cho DMZ, dong bo tu ha-prx01)"
    apt-get install -y bind9 bind9utils bind9-dnsutils

    log "Khai bao vung dmz.pvnskills.org (Secondary) trong named.conf.local"
    cat > /etc/bind/named.conf.local << EOF
zone "${DMZ_DOMAIN}" {
    type secondary;
    primaries { ${HA_PRX01_IP4}; };
    file "/var/cache/bind/db.dmz.pvnskills.org";
};

zone "20.1.10.in-addr.arpa" {
    type secondary;
    primaries { ${HA_PRX01_IP4}; };
    file "/var/cache/bind/db.20.1.10";
};

zone "0.0.0.0.0.0.0.0.0.0.0.0.0.2.0.0.1.0.0.1.0.8.b.d.0.1.0.0.2.ip6.arpa" {
    type secondary;
    primaries { ${HA_PRX01_IP4}; };
    file "/var/cache/bind/db.dmz-ipv6";
};
EOF

    log "Cau hinh named.conf.options: TU CHOI truy van de quy (authoritative only)"
    cat > /etc/bind/named.conf.options << 'EOF'
options {
    directory "/var/cache/bind";

    recursion no;
    allow-query { any; };

    listen-on { any; };
    listen-on-v6 { any; };

    dnssec-validation auto;
};
EOF

    log "Kiem tra cu phap va khoi dong lai BIND9"
    named-checkconf

    systemctl restart bind9
    systemctl enable bind9

    log "Ep dong bo zone lan dau (retransfer) - chi la trigger co che tu dong,"
    log "KHONG phai chuyen thu cong (van dung dung nghia zone transfer tu dong)"
    sleep 2
    rndc retransfer "${DMZ_DOMAIN}" 2>/dev/null || true
}


# ==============================================================================
# SECTION 4: KIEM TRA TONG QUAT SAU KHI CAU HINH DICH VU
# ==============================================================================

verify_services() {
    log "===== TOM TAT KIEM TRA DICH VU ====="

    echo "--- Nginx + Keepalived: trang thai dich vu ---"
    systemctl is-active nginx
    systemctl is-active keepalived

    echo -e "\n--- VIP dang active tren may nay khong? ---"
    ip addr show | grep "${VIP4}" || echo "  (VIP dang o ha-prx01 - binh thuong neu ha-prx01 dang la MASTER)"

    echo -e "\n--- BIND9: trang thai + kiem tra da dong bo zone tu ha-prx01 chua ---"
    systemctl is-active bind9
    dig @127.0.0.1 "${DMZ_DOMAIN}" SOA +short || echo "  CANH BAO: chua dong bo duoc, kiem tra lai ha-prx01 da san sang chua"

    log "Hoan tat cau hinh dich vu cho ha-prx02.dmz.pvnskills.org"
}


# ==============================================================================
# SECTION 5: MAIN
# ==============================================================================

main() {
    require_root
    setup_reverse_proxy
    setup_keepalived
    setup_dns_secondary
    verify_services
}

main "$@"
