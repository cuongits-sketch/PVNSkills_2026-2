#!/bin/bash
#
# ==============================================================================
#  ha-prx01-setup.sh
#  Cau hinh cac DICH VU CHINH (phuc tap) cho ha-prx01.dmz.pvnskills.org
#  (HA Reverse Proxy - Keepalived+Nginx, DNS DMZ Primary - BIND9, SSH CA)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  YEU CAU:
#    - ha-prx01.sh phai da chay THANH CONG truoc do (hostname, IP da san sang).
#    - int-srv01 phai da hoan tat buoc CA (de co /root/ca/sub-ca/web*.{crt,key}).
#
#  LUU Y QUAN TRONG VE THU TU:
#    Sau khi file nay chay xong, PHAI chay tiep mail-setup.sh (hoac ham
#    setup_ssh_certificate rieng le trong do) tren mail.dmz.pvnskills.org
#    de fetch khoa CA vua sinh o day (SECTION 4).
#
#  Cach chay:
#     scp common.sh ha-prx01.sh ha-prx01-setup.sh root@10.1.20.21:/root/
#     ssh root@10.1.20.21 "bash /root/ha-prx01.sh && bash /root/ha-prx01-setup.sh"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP BIEN & HAM DUNG CHUNG TU ha-prx01.sh (va common.sh)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/hosts/ha-prx01.sh" ]]; then
    echo "Khong tim thay ha-prx01.sh cung thu muc voi ha-prx01-setup.sh." >&2
    exit 1
fi

# shellcheck source=ha-prx01.sh
source "${SCRIPT_DIR}/hosts/ha-prx01.sh"
# Luu y: "source" o tren KHONG lam chay main() cua ha-prx01.sh,
# vi ha-prx01.sh chi tu goi main() khi duoc thuc thi truc tiep

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i /root/.ssh/id_ed25519"


# ==============================================================================
# SECTION 2: HA REVERSE PROXY - KEEPALIVED + NGINX
#   Lay chung chi Web tu int-srv01, cau hinh Nginx (redirect HTTP->HTTPS,
#   proxy toi web01/web02, header via-proxy), cau hinh Keepalived VRRP MASTER.
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

    log "Ghi cau hinh Nginx reverse proxy: ${SCRIPT_DIR##*/}"
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
# SECTION 3: DNS DMZ - BIND9 (PRIMARY)
#   Authoritative cho dmz.pvnskills.org (forward + reverse IPv4/IPv6),
#   cho phep zone-transfer toi ha-prx02 + int-srv01 (secondary),
#   TU CHOI truy van de quy (recursion no) vi day la DNS cong khai cho DMZ.
# ==============================================================================

setup_dns_primary() {
    log "Cai dat BIND9 (DNS Primary cho DMZ)"
    apt-get install -y bind9 bind9utils bind9-dnsutils

    mkdir -p "${DNS_ZONE_DIR}"

    log "Khai bao vung dmz.pvnskills.org (Primary) trong named.conf.local"
    cat > /etc/bind/named.conf.local << EOF
zone "${DMZ_DOMAIN}" {
    type primary;
    file "${DNS_ZONE_DIR}/db.dmz.pvnskills.org";
    allow-transfer { ${HA_PRX02_IP4}; ${INT_SRV01_IP4}; };
};

zone "20.1.10.in-addr.arpa" {
    type primary;
    file "${DNS_ZONE_DIR}/db.20.1.10";
    allow-transfer { ${HA_PRX02_IP4}; ${INT_SRV01_IP4}; };
};

zone "0.0.0.0.0.0.0.0.0.0.0.0.0.2.0.0.1.0.0.1.0.8.b.d.0.1.0.0.2.ip6.arpa" {
    type primary;
    file "${DNS_ZONE_DIR}/db.dmz-ipv6";
    allow-transfer { ${HA_PRX02_IP4}; ${INT_SRV01_IP4}; };
};
EOF

    log "Tao forward zone file cho ${DMZ_DOMAIN}"
    cat > "${DNS_ZONE_DIR}/db.dmz.pvnskills.org" << EOF
\$TTL    604800
@       IN      SOA     ha-prx01.${DMZ_DOMAIN}. admin.${DMZ_DOMAIN}. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@              IN NS   ha-prx01.${DMZ_DOMAIN}.
@              IN NS   ha-prx02.${DMZ_DOMAIN}.

mail           IN A     10.1.20.10
mail           IN AAAA  2001:db8:1001:20::10
prx-vrrp       IN A     ${VIP4}
prx-vrrp       IN AAAA  ${VIP6}
ha-prx01       IN A     10.1.20.21
ha-prx01       IN AAAA  2001:db8:1001:20::21
ha-prx02       IN A     10.1.20.22
ha-prx02       IN AAAA  2001:db8:1001:20::22
web01          IN A     ${WEB01_IP4}
web01          IN AAAA  2001:db8:1001:20::31
web02          IN A     ${WEB02_IP4}
web02          IN AAAA  2001:db8:1001:20::32

; CNAME: www.dmz.pvnskills.org -> prx-vrrp.dmz.pvnskills.org (KHONG tao ban ghi A rieng)
www            IN CNAME prx-vrrp.${DMZ_DOMAIN}.
EOF

    log "Tao reverse zone file IPv4"
    cat > "${DNS_ZONE_DIR}/db.20.1.10" << EOF
\$TTL    604800
@       IN      SOA     ha-prx01.${DMZ_DOMAIN}. admin.${DMZ_DOMAIN}. (
                              3
                         604800
                          86400
                        2419200
                         604800 )
;
@       IN NS   ha-prx01.${DMZ_DOMAIN}.
@       IN NS   ha-prx02.${DMZ_DOMAIN}.

10      IN PTR  mail.${DMZ_DOMAIN}.
20      IN PTR  prx-vrrp.${DMZ_DOMAIN}.
21      IN PTR  ha-prx01.${DMZ_DOMAIN}.
22      IN PTR  ha-prx02.${DMZ_DOMAIN}.
31      IN PTR  web01.${DMZ_DOMAIN}.
32      IN PTR  web02.${DMZ_DOMAIN}.
EOF

    log "Tao reverse zone file IPv6"
    cat > "${DNS_ZONE_DIR}/db.dmz-ipv6" << EOF
\$TTL    604800
@       IN      SOA     ha-prx01.${DMZ_DOMAIN}. admin.${DMZ_DOMAIN}. (
                              3
                         604800
                          86400
                        2419200
                         604800 )
;
@       IN NS   ha-prx01.${DMZ_DOMAIN}.
@       IN NS   ha-prx02.${DMZ_DOMAIN}.

\$ORIGIN 0.2.0.0.1.0.0.1.0.8.b.d.0.1.0.0.2.ip6.arpa.
0.1.0.0.0.0.0.0.0.0.0.0.0.0.0.0  IN PTR  mail.${DMZ_DOMAIN}.
0.2.0.0.0.0.0.0.0.0.0.0.0.0.0.0  IN PTR  prx-vrrp.${DMZ_DOMAIN}.
1.2.0.0.0.0.0.0.0.0.0.0.0.0.0.0  IN PTR  ha-prx01.${DMZ_DOMAIN}.
2.2.0.0.0.0.0.0.0.0.0.0.0.0.0.0  IN PTR  ha-prx02.${DMZ_DOMAIN}.
1.3.0.0.0.0.0.0.0.0.0.0.0.0.0.0  IN PTR  web01.${DMZ_DOMAIN}.
2.3.0.0.0.0.0.0.0.0.0.0.0.0.0.0  IN PTR  web02.${DMZ_DOMAIN}.
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
    named-checkzone "${DMZ_DOMAIN}" "${DNS_ZONE_DIR}/db.dmz.pvnskills.org"
    named-checkzone "20.1.10.in-addr.arpa" "${DNS_ZONE_DIR}/db.20.1.10"

    systemctl restart bind9
    systemctl enable bind9
}


# ==============================================================================
# SECTION 4: SSH CA - SINH KHOA CHUNG THUC NGUOI DUNG SSH
#   Tao CA key (chi tren ha-prx01), ky public key cua root@ha-prx01 thanh
#   certificate, cau hinh SSH client dung certificate khi ket noi toi mail.
#   mail.dmz.pvnskills.org se FETCH file user_ca.pub nay ve de TIN TUONG.
# ==============================================================================

setup_ssh_ca() {
    log "Sinh cap khoa CA cho SSH User Certificate (chi chay 1 lan)"

    mkdir -p "${SSH_CA_DIR}"

    if [[ ! -f "${SSH_CA_DIR}/user_ca" ]]; then
        ssh-keygen -t ed25519 -f "${SSH_CA_DIR}/user_ca" -C "PVNSC SSH User CA" -N ""
    else
        log "CA key da ton tai, bo qua buoc sinh khoa"
    fi

    log "Ky public key cua root@ha-prx01 thanh certificate (principal: root)"
    ssh-keygen -s "${SSH_CA_DIR}/user_ca" \
        -I "root-ha-prx01" \
        -n root \
        -V +52w \
        /root/.ssh/id_ed25519.pub

    log "Cau hinh SSH client dung certificate khi ket noi toi mail"
    mkdir -p /root/.ssh
    if ! grep -q "^Host mail$" /root/.ssh/config 2>/dev/null; then
        cat >> /root/.ssh/config << EOF

Host mail mail.dmz.pvnskills.org ${MAIL_HOST_IP}
    HostName ${MAIL_HOST_IP}
    User root
    IdentityFile /root/.ssh/id_ed25519
    CertificateFile /root/.ssh/id_ed25519-cert.pub
EOF
    fi
    chmod 600 /root/.ssh/config

    log "SSH CA da san sang. Tren mail.dmz.pvnskills.org, chay lai buoc"
    log "setup_ssh_certificate (trong mail-setup.sh) de fetch ${SSH_CA_DIR}/user_ca.pub ve."
}


# ==============================================================================
# SECTION 5: KIEM TRA TONG QUAT SAU KHI CAU HINH DICH VU
# ==============================================================================

verify_services() {
    log "===== TOM TAT KIEM TRA DICH VU ====="

    echo "--- Nginx + Keepalived: trang thai dich vu ---"
    systemctl is-active nginx
    systemctl is-active keepalived

    echo -e "\n--- VIP dang active tren may nay khong? ---"
    ip addr show | grep "${VIP4}" || echo "  (VIP dang o ha-prx02 - binh thuong neu ha-prx02 dang la MASTER)"

    echo -e "\n--- BIND9: trang thai + zone dmz.pvnskills.org ---"
    systemctl is-active bind9
    dig @127.0.0.1 "${DMZ_DOMAIN}" SOA +short
    dig @127.0.0.1 www."${DMZ_DOMAIN}" CNAME +short

    echo -e "\n--- SSH CA: certificate cua root ---"
    ssh-keygen -L -f /root/.ssh/id_ed25519-cert.pub | head -5

    log "Hoan tat cau hinh dich vu cho ha-prx01.dmz.pvnskills.org"
    log "NHAC LAI: chay tiep tren mail de fetch SSH CA (xem SECTION 4)."
}


# ==============================================================================
# SECTION 6: MAIN
# ==============================================================================

main() {
    require_root
    setup_reverse_proxy
    setup_keepalived
    setup_dns_primary
    setup_ssh_ca
    verify_services
}

main "$@"
