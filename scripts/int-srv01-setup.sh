#!/bin/bash
#
# ==============================================================================
#  int-srv01-setup.sh
#  Cau hinh cac DICH VU CHINH (phuc tap) cho int-srv01.int.pvnskills.org
#  (LDAP, CA - Co quan chung thuc, Samba File Server, DNS noi bo - BIND9)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  YEU CAU: int-srv01.sh phai da chay THANH CONG truoc do (hostname, IP
#  da san sang). File nay tu "source int-srv01.sh" (va qua do source luon
#  common.sh) de tai su dung bien/ham dung chung.
#
#  Cach chay:
#     scp common.sh int-srv01.sh int-srv01-setup.sh root@10.1.10.10:/root/
#     ssh root@10.1.10.10 "bash /root/int-srv01.sh && bash /root/int-srv01-setup.sh"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP BIEN & HAM DUNG CHUNG TU int-srv01.sh (va common.sh)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/int-srv01.sh" ]]; then
    echo "Khong tim thay int-srv01.sh cung thu muc voi int-srv01-setup.sh." >&2
    exit 1
fi

# shellcheck source=int-srv01.sh
source "${SCRIPT_DIR}/int-srv01.sh"
# Luu y: "source" o tren KHONG lam chay main() cua int-srv01.sh,
# vi int-srv01.sh chi tu goi main() khi duoc thuc thi truc tiep


# ==============================================================================
# SECTION 2: LDAP
#   Cai dat slapd (non-interactive qua debconf), tao OU Employees va
#   nguoi dung theo Bang 2 (jamie, peter, admin).
# ==============================================================================

setup_ldap() {
    log "Cai dat LDAP (slapd) - cau hinh non-interactive qua debconf"

    debconf-set-selections << EOF
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PW}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PW}
slapd slapd/password2 password ${LDAP_ADMIN_PW}
slapd slapd/password1 password ${LDAP_ADMIN_PW}
slapd shared/organization string ${LDAP_ORG}
slapd slapd/domain string ${LDAP_DOMAIN}
slapd slapd/backend string MDB
slapd slapd/purge_database boolean false
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
EOF

    DEBIAN_FRONTEND=noninteractive apt-get install -y slapd ldap-utils

    log "Tao OU ${LDAP_OU} (neu chua ton tai)"
    if ! ldapsearch -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}" \
            -b "ou=${LDAP_OU},${LDAP_BASE_DN}" -s base > /dev/null 2>&1; then
        cat << EOF | ldapadd -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}"
dn: ou=${LDAP_OU},${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: ${LDAP_OU}
EOF
    else
        log "OU ${LDAP_OU} da ton tai, bo qua"
    fi

    log "Tao nguoi dung LDAP theo Bang 2 (jamie, peter, admin) - neu chua ton tai"

    # --- jamie ---
    if ! ldapsearch -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}" \
            -b "uid=jamie,ou=${LDAP_OU},${LDAP_BASE_DN}" -s base > /dev/null 2>&1; then
        cat << EOF | ldapadd -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}"
dn: uid=jamie,ou=${LDAP_OU},${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: jamie
cn: Jamie Oliver
sn: Oliver
mail: jamie.oliver@dmz.pvnskills.org
uidNumber: 10001
gidNumber: 10001
homeDirectory: /home/jamie
loginShell: /bin/bash
userPassword: {CRYPT}x
EOF
        ldappasswd -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}" \
            -s "${LDAP_ADMIN_PW}" "uid=jamie,ou=${LDAP_OU},${LDAP_BASE_DN}"
    fi

    # --- peter ---
    if ! ldapsearch -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}" \
            -b "uid=peter,ou=${LDAP_OU},${LDAP_BASE_DN}" -s base > /dev/null 2>&1; then
        cat << EOF | ldapadd -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}"
dn: uid=peter,ou=${LDAP_OU},${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: peter
cn: Peter Fox
sn: Fox
mail: peter.fox@dmz.pvnskills.org
uidNumber: 10002
gidNumber: 10002
homeDirectory: /home/peter
loginShell: /bin/bash
userPassword: {CRYPT}x
EOF
        ldappasswd -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}" \
            -s "${LDAP_ADMIN_PW}" "uid=peter,ou=${LDAP_OU},${LDAP_BASE_DN}"
    fi

    # --- admin (khong thuoc OU Employees) ---
    if ! ldapsearch -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}" \
            -b "uid=admin,${LDAP_BASE_DN}" -s base > /dev/null 2>&1; then
        cat << EOF | ldapadd -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}"
dn: uid=admin,${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: admin
cn: Administrator
sn: Administrator
uidNumber: 10000
gidNumber: 10000
homeDirectory: /home/admin
loginShell: /bin/bash
userPassword: {CRYPT}x
EOF
        ldappasswd -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PW}" \
            -s "${LDAP_ADMIN_PW}" "uid=admin,${LDAP_BASE_DN}"
    fi
}


# ==============================================================================
# SECTION 3: CA - CO QUAN CHUNG THUC
#   Root CA "PVNSC Root CA" -> Sub-CA "Services" -> chung chi web + mail.
#   Bo qua tao lai neu Root CA da ton tai (idempotent).
# ==============================================================================

setup_ca() {
    log "Tao cau truc PKI: Root CA -> Sub-CA Services -> chung chi web/mail"

    mkdir -p "${CA_DIR}/root-ca" "${CA_DIR}/sub-ca" "${GRADING_DIR}"

    if [[ -f "${CA_DIR}/root-ca/root-ca.crt" ]]; then
        log "Root CA da ton tai, bo qua buoc tao CA"
    else
        log "Tao Root CA (PVNSC Root CA)"
        openssl genrsa -out "${CA_DIR}/root-ca/root-ca.key" 4096
        openssl req -x509 -new -nodes -key "${CA_DIR}/root-ca/root-ca.key" -sha256 -days 3650 \
            -out "${CA_DIR}/root-ca/root-ca.crt" \
            -subj "/C=VN/ST=HCM/L=HoChiMinh/O=${LDAP_ORG}/CN=PVNSC Root CA"

        log "Tao Sub-CA Services (ky boi Root CA)"
        openssl genrsa -out "${CA_DIR}/sub-ca/services.key" 4096
        openssl req -new -key "${CA_DIR}/sub-ca/services.key" -out "${CA_DIR}/sub-ca/services.csr" \
            -subj "/C=VN/ST=HCM/L=HoChiMinh/O=${LDAP_ORG}/CN=PVNSC Services Sub-CA"

        cat > "${CA_DIR}/sub-ca/services_ext.cnf" << 'EOF'
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

        openssl x509 -req -in "${CA_DIR}/sub-ca/services.csr" \
            -CA "${CA_DIR}/root-ca/root-ca.crt" -CAkey "${CA_DIR}/root-ca/root-ca.key" -CAcreateserial \
            -out "${CA_DIR}/sub-ca/services.crt" -days 1825 -sha256 \
            -extfile "${CA_DIR}/sub-ca/services_ext.cnf"

        log "Cap chung chi cho Web Server (${CA_WEB_CN})"
        openssl genrsa -out "${CA_DIR}/sub-ca/web.key" 2048
        openssl req -new -key "${CA_DIR}/sub-ca/web.key" -out "${CA_DIR}/sub-ca/web.csr" \
            -subj "/C=VN/ST=HCM/O=${LDAP_ORG}/CN=${CA_WEB_CN}"
        cat > "${CA_DIR}/sub-ca/web_ext.cnf" << EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${CA_WEB_CN}
EOF
        openssl x509 -req -in "${CA_DIR}/sub-ca/web.csr" \
            -CA "${CA_DIR}/sub-ca/services.crt" -CAkey "${CA_DIR}/sub-ca/services.key" -CAcreateserial \
            -out "${CA_DIR}/sub-ca/web.crt" -days 825 -sha256 \
            -extfile "${CA_DIR}/sub-ca/web_ext.cnf"

        log "Cap chung chi cho Mail Server (${CA_MAIL_CN})"
        openssl genrsa -out "${CA_DIR}/sub-ca/mail.key" 2048
        openssl req -new -key "${CA_DIR}/sub-ca/mail.key" -out "${CA_DIR}/sub-ca/mail.csr" \
            -subj "/C=VN/ST=HCM/O=${LDAP_ORG}/CN=${CA_MAIL_CN}"
        cat > "${CA_DIR}/sub-ca/mail_ext.cnf" << EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${CA_MAIL_CN}
EOF
        openssl x509 -req -in "${CA_DIR}/sub-ca/mail.csr" \
            -CA "${CA_DIR}/sub-ca/services.crt" -CAkey "${CA_DIR}/sub-ca/services.key" -CAcreateserial \
            -out "${CA_DIR}/sub-ca/mail.crt" -days 825 -sha256 \
            -extfile "${CA_DIR}/sub-ca/mail_ext.cnf"

        # Fullchain de dung khi cau hinh TLS cho web/mail/reverse-proxy o cac may khac
        cat "${CA_DIR}/sub-ca/web.crt" "${CA_DIR}/sub-ca/services.crt" > "${CA_DIR}/sub-ca/web-fullchain.crt"
        cat "${CA_DIR}/sub-ca/mail.crt" "${CA_DIR}/sub-ca/services.crt" > "${CA_DIR}/sub-ca/mail-fullchain.crt"
    fi

    log "Sao chep chung chi vao ${GRADING_DIR} (dung ten file theo yeu cau de thi)"
    cp "${CA_DIR}/root-ca/root-ca.crt" "${GRADING_DIR}/ca.pem"
    cp "${CA_DIR}/sub-ca/services.crt" "${GRADING_DIR}/services.pem"
    cp "${CA_DIR}/sub-ca/web.crt"      "${GRADING_DIR}/web.pem"
    cp "${CA_DIR}/sub-ca/mail.crt"     "${GRADING_DIR}/mail.pem"
}


# ==============================================================================
# SECTION 4: SAMBA FILE SERVER
#   Local user "jamie", 2 share: /public (doc chung, ghi khi da dang nhap)
#   va /internal (chi user da xac thuc).
# ==============================================================================

setup_samba() {
    log "Cai dat Samba"
    apt-get install -y samba

    log "Tao local user Samba: ${SAMBA_USER} (neu chua ton tai)"
    if ! id "${SAMBA_USER}" > /dev/null 2>&1; then
        useradd -m -s /usr/sbin/nologin "${SAMBA_USER}"
    fi

    # Dat mat khau Samba khong can nhap tay (pipe 2 lan qua stdin)
    printf '%s\n%s\n' "${SAMBA_PW}" "${SAMBA_PW}" | smbpasswd -a -s "${SAMBA_USER}"
    smbpasswd -e "${SAMBA_USER}"

    log "Tao thu muc chia se /public va /internal"
    mkdir -p "${SAMBA_PUBLIC_DIR}" "${SAMBA_INTERNAL_DIR}"
    chmod 1777 "${SAMBA_PUBLIC_DIR}"
    chown "${SAMBA_USER}:${SAMBA_USER}" "${SAMBA_INTERNAL_DIR}"
    chmod 0770 "${SAMBA_INTERNAL_DIR}"

    log "Ghi cau hinh /etc/samba/smb.conf"
    # Backup cau hinh mac dinh neu chua backup
    [[ -f /etc/samba/smb.conf.orig ]] || cp /etc/samba/smb.conf /etc/samba/smb.conf.orig

    cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = PVNSKILLS
   server string = int-srv01 File Server
   security = user
   map to guest = Bad User

[public]
   path = ${SAMBA_PUBLIC_DIR}
   browsable = yes
   guest ok = yes
   guest only = no
   read only = no
   valid users = ${SAMBA_USER}
   write list = ${SAMBA_USER}
   force group = ${SAMBA_USER}
   create mask = 0664
   directory mask = 0775

[internal]
   path = ${SAMBA_INTERNAL_DIR}
   browsable = yes
   guest ok = no
   read only = no
   valid users = ${SAMBA_USER}
   create mask = 0660
   directory mask = 0770
EOF

    systemctl restart smbd nmbd
    systemctl enable smbd nmbd
}


# ==============================================================================
# SECTION 5: DNS NOI BO - BIND9
#   Primary cho int.pvnskills.org (forward + reverse + SRV LDAP),
#   Secondary cho dmz.pvnskills.org (zone transfer tu ha-prx01),
#   bat recursion cho mang INT.
# ==============================================================================

setup_dns() {
    log "Cai dat BIND9"
    apt-get install -y bind9 bind9utils bind9-dnsutils

    mkdir -p "${DNS_ZONE_DIR}"

    log "Khai bao cac vung (zones) trong named.conf.local"
    cat > /etc/bind/named.conf.local << EOF
// ===== Vung noi bo (int.pvnskills.org) - Primary =====
zone "${LDAP_DOMAIN}" {
    type primary;
    file "${DNS_ZONE_DIR}/db.int.pvnskills.org";
    allow-transfer { none; };
};

zone "10.1.10.in-addr.arpa" {
    type primary;
    file "${DNS_ZONE_DIR}/db.10.1.10";
    allow-transfer { none; };
};

zone "0.0.0.0.0.0.0.0.0.0.0.0.0.1.0.0.1.0.0.1.0.8.b.d.0.1.0.0.2.ip6.arpa" {
    type primary;
    file "${DNS_ZONE_DIR}/db.int-ipv6";
    allow-transfer { none; };
};

// ===== Vung DMZ (dmz.pvnskills.org) - Secondary tu ha-prx01 =====
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

    log "Tao forward zone file cho ${LDAP_DOMAIN}"
    cat > "${DNS_ZONE_DIR}/db.int.pvnskills.org" << EOF
\$TTL    604800
@       IN      SOA     int-srv01.${LDAP_DOMAIN}. admin.${LDAP_DOMAIN}. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@                   IN NS   int-srv01.${LDAP_DOMAIN}.

int-srv01           IN A     ${IP4}
int-srv01           IN AAAA  ${IP6}
fw                   IN A     ${GW4}

; SRV record cho LDAP: auth.int.pvnskills.org -> int-srv01, TCP/389, priority 10, weight 50
_ldap._tcp.auth      IN SRV  10 50 389 int-srv01.${LDAP_DOMAIN}.
EOF

    log "Tao reverse zone file IPv4"
    cat > "${DNS_ZONE_DIR}/db.10.1.10" << EOF
\$TTL    604800
@       IN      SOA     int-srv01.${LDAP_DOMAIN}. admin.${LDAP_DOMAIN}. (
                              3
                         604800
                          86400
                        2419200
                         604800 )
;
@       IN NS   int-srv01.${LDAP_DOMAIN}.

10      IN PTR  int-srv01.${LDAP_DOMAIN}.
1       IN PTR  fw.pvnskills.org.
EOF

    log "Tao reverse zone file IPv6"
    cat > "${DNS_ZONE_DIR}/db.int-ipv6" << EOF
\$TTL    604800
@       IN      SOA     int-srv01.${LDAP_DOMAIN}. admin.${LDAP_DOMAIN}. (
                              3
                         604800
                          86400
                        2419200
                         604800 )
;
@       IN NS   int-srv01.${LDAP_DOMAIN}.

\$ORIGIN 0.1.0.0.1.0.0.1.0.8.b.d.0.1.0.0.2.ip6.arpa.
0.1.0.0.0.0.0.0.0.0.0.0.0.0.0.0  IN PTR  int-srv01.${LDAP_DOMAIN}.
1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0  IN PTR  fw.pvnskills.org.
EOF

    log "Bat recursion cho mang INT trong named.conf.options"
    cat > /etc/bind/named.conf.options << 'EOF'
options {
    directory "/var/cache/bind";

    recursion yes;
    allow-recursion { 10.1.10.0/24; 2001:db8:1001:10::/64; localhost; };

    listen-on { any; };
    listen-on-v6 { any; };

    dnssec-validation auto;
};
EOF

    log "Kiem tra cu phap va khoi dong lai BIND9"
    named-checkconf
    named-checkzone "${LDAP_DOMAIN}" "${DNS_ZONE_DIR}/db.int.pvnskills.org"
    named-checkzone "10.1.10.in-addr.arpa" "${DNS_ZONE_DIR}/db.10.1.10"

    systemctl restart bind9
    systemctl enable bind9

    log "Tro resolver cua chinh may nay ve DNS local"
    cat > /etc/resolv.conf << EOF
nameserver 127.0.0.1
nameserver ::1
search ${LDAP_DOMAIN}
EOF
}


# ==============================================================================
# SECTION 6: KIEM TRA TONG QUAT SAU KHI CAU HINH DICH VU
# ==============================================================================

verify_services() {
    log "===== TOM TAT KIEM TRA DICH VU ====="

    echo "--- LDAP: bind thu jamie/peter/admin ---"
    for u in jamie peter admin; do
        if [[ "${u}" == "admin" ]]; then
            dn="uid=admin,${LDAP_BASE_DN}"
        else
            dn="uid=${u},ou=${LDAP_OU},${LDAP_BASE_DN}"
        fi
        ldapwhoami -x -D "${dn}" -w "${LDAP_ADMIN_PW}" > /dev/null 2>&1 \
            && echo "  [OK] ${u} bind thanh cong" \
            || echo "  [FAIL] ${u} bind that bai"
    done

    echo -e "\n--- CA: kiem tra chuoi chung thuc ---"
    cat "${GRADING_DIR}/services.pem" "${GRADING_DIR}/ca.pem" > /tmp/chain.pem
    openssl verify -CAfile /tmp/chain.pem "${GRADING_DIR}/web.pem" || true
    openssl verify -CAfile /tmp/chain.pem "${GRADING_DIR}/mail.pem" || true

    echo -e "\n--- Samba: trang thai dich vu ---"
    systemctl is-active smbd

    echo -e "\n--- DNS: A/AAAA/SRV cho int-srv01 ---"
    dig @127.0.0.1 int-srv01.${LDAP_DOMAIN} A +short
    dig @127.0.0.1 _ldap._tcp.auth.${LDAP_DOMAIN} SRV +short

    log "Hoan tat cau hinh dich vu cho int-srv01.int.pvnskills.org"
}


# ==============================================================================
# SECTION 7: MAIN
# ==============================================================================

main() {
    require_root
    setup_ldap
    setup_ca
    setup_samba
    setup_dns
    verify_services
}

main "$@"
