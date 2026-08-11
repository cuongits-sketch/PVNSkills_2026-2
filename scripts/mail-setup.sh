#!/bin/bash
#
# ==============================================================================
#  mail-setup.sh
#  Cau hinh cac DICH VU CHINH (phuc tap) cho mail.dmz.pvnskills.org
#  (Mail Server - Postfix/Dovecot, Sao luu - Backup, SSH User Certificate)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  YEU CAU:
#    - mail.sh phai da chay THANH CONG truoc do (hostname, IP da san sang).
#    - int-srv01 phai da hoan tat buoc CA (de co /root/ca/sub-ca/mail*.{crt,key})
#      va co the SSH toi duoc (dung khoa mac dinh /root/.ssh/id_ed25519).
#    - ha-prx01 (neu da cau hinh SSH CA) de fetch user_ca.pub - neu chua co,
#      buoc SSH Certificate se CANH BAO va BO QUA, khong lam dung script.
#
#  Cach chay:
#     scp common.sh mail.sh mail-setup.sh root@10.1.20.10:/root/
#     ssh root@10.1.20.10 "bash /root/mail.sh && bash /root/mail-setup.sh"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP BIEN & HAM DUNG CHUNG TU mail.sh (va common.sh)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/hosts/mail.sh" ]]; then
    echo "Khong tim thay mail.sh cung thu muc voi mail-setup.sh." >&2
    exit 1
fi

# shellcheck source=mail.sh
source "${SCRIPT_DIR}/hosts/mail.sh"
# Luu y: "source" o tren KHONG lam chay main() cua mail.sh,
# vi mail.sh chi tu goi main() khi duoc thuc thi truc tiep

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i /root/.ssh/id_ed25519"


# ==============================================================================
# SECTION 2: MAIL SERVER - POSTFIX + DOVECOT
#   Lay chung chi TLS tu int-srv01, cau hinh Postfix (SMTP) + Dovecot
#   (IMAP/IMAPS, xac thuc qua LDAP), tao auto-reply cho echo@dmz.pvnskills.org.
# ==============================================================================

fetch_tls_cert_from_int_srv01() {
    log "Lay chung chi TLS tu int-srv01 (${CERT_SOURCE_HOST})"

    mkdir -p /etc/ssl/private
    chmod 700 /etc/ssl/private

    scp ${SSH_OPTS} "root@${CERT_SOURCE_HOST}:${CERT_SOURCE_MAILCRT}" "${MAIL_CERT}"
    scp ${SSH_OPTS} "root@${CERT_SOURCE_HOST}:${CERT_SOURCE_MAILKEY}" "${MAIL_KEY}"
    scp ${SSH_OPTS} "root@${CERT_SOURCE_HOST}:${CERT_SOURCE_ROOTCA}" "${ROOT_CA_CERT}"

    chmod 600 "${MAIL_KEY}"
    chown root:root "${MAIL_KEY}"
}

setup_mail_server() {
    log "Cai dat Postfix + Dovecot"
    debconf-set-selections << EOF
postfix postfix/mailname string ${MAIL_DOMAIN}
postfix postfix/main_mailer_type select Internet Site
EOF
    DEBIAN_FRONTEND=noninteractive apt-get install -y postfix dovecot-core dovecot-imapd dovecot-ldap

    fetch_tls_cert_from_int_srv01

    log "Cau hinh Postfix (SMTP)"
    postconf -e "myhostname = ${FQDN}"
    postconf -e "mydomain = ${MAIL_DOMAIN}"
    postconf -e "myorigin = \$mydomain"
    postconf -e "inet_interfaces = all"
    postconf -e "inet_protocols = ipv4, ipv6"
    postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"

    postconf -e "smtpd_tls_cert_file = ${MAIL_CERT}"
    postconf -e "smtpd_tls_key_file = ${MAIL_KEY}"
    postconf -e "smtpd_use_tls = yes"
    postconf -e "smtpd_tls_security_level =nan may"
    postconf -e "smtp_tls_CAfile = ${ROOT_CA_CERT}"

    postconf -e "smtpd_sasl_type = dovecot"
    postconf -e "smtpd_sasl_path = private/auth"
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_relay_restrictions = permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination"
    postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"

    log "Cau hinh alias echo@ -> transport rieng (auto-reply)"
    mkdir -p /opt/mail
    cat > /opt/mail/echo-reply.sh << 'EOF'
#!/bin/bash
# Doc toan bo noi dung email goc tu stdin roi gui tra lai (echo) cho nguoi gui
SENDER="$1"
cat | /usr/sbin/sendmail -f "echo@dmz.pvnskills.org" "${SENDER}"
EOF
    chmod +x /opt/mail/echo-reply.sh

    if ! grep -q "^echoreply" /etc/postfix/master.cf 2>/dev/null; then
        cat >> /etc/postfix/master.cf << 'EOF'

echoreply  unix  -       n       n       -       -       pipe
  flags=Rq user=vmail argv=/opt/mail/echo-reply.sh ${sender} ${recipient}
EOF
    fi

    echo "${ECHO_ADDRESS} echoreply:" > /etc/postfix/transport
    postmap /etc/postfix/transport
    postconf -e "transport_maps = hash:/etc/postfix/transport"

    log "Tao user he thong 'vmail' va thu muc mailbox (Maildir)"
    if ! getent group vmail > /dev/null; then
        groupadd -g 5000 vmail
    fi
    if ! id vmail > /dev/null 2>&1; then
        useradd -g vmail -u 5000 vmail -d /var/mail
    fi
    mkdir -p "/var/mail/vhosts/${MAIL_DOMAIN}"
    chown -R vmail:vmail /var/mail/vhosts

    log "Cau hinh Dovecot: mail location, SSL, LDAP auth, IMAP/IMAPS, LMTP"

    cat > /etc/dovecot/conf.d/10-mail.conf.local << EOF
mail_location = maildir:/var/mail/vhosts/%d/%n
EOF
    grep -q "10-mail.conf.local" /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || \
        echo "!include_try 10-mail.conf.local" >> /etc/dovecot/conf.d/10-mail.conf

    cat > /etc/dovecot/dovecot-ldap.conf.ext << EOF
uris = ${LDAP_URI}
base = ${LDAP_BASE_DN}
dn = ${LDAP_ADMIN_DN}
dnpass = ${LDAP_ADMIN_PW}
auth_bind = yes
user_attrs = mail=user
user_filter = (uid=%n)
pass_filter = (uid=%n)
EOF

    cat > /etc/dovecot/conf.d/auth-ldap.conf.ext << 'EOF'
passdb {
  driver = ldap
  args = /etc/dovecot/dovecot-ldap.conf.ext
}
userdb {
  driver = ldap
  args = /etc/dovecot/dovecot-ldap.conf.ext
}
EOF

    sed -i 's/^#*disable_plaintext_auth.*/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
    sed -i 's/^#*auth_mechanisms.*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf
    grep -q "auth-ldap.conf.ext" /etc/dovecot/conf.d/10-auth.conf || \
        echo "!include auth-ldap.conf.ext" >> /etc/dovecot/conf.d/10-auth.conf

    cat > /etc/dovecot/conf.d/10-ssl.conf.local << EOF
ssl = required
ssl_cert = <${MAIL_CERT}
ssl_key = <${MAIL_KEY}
EOF
    grep -q "10-ssl.conf.local" /etc/dovecot/conf.d/10-ssl.conf 2>/dev/null || \
        echo "!include_try 10-ssl.conf.local" >> /etc/dovecot/conf.d/10-ssl.conf

    cat > /etc/dovecot/conf.d/10-master.conf.local << 'EOF'
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
  unix_listener auth-userdb {
    mode = 0600
    user = vmail
  }
}

service lmtp {
  unix_listener private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
EOF
    grep -q "10-master.conf.local" /etc/dovecot/conf.d/10-master.conf 2>/dev/null || \
        echo "!include_try 10-master.conf.local" >> /etc/dovecot/conf.d/10-master.conf

    log "Khoi dong lai Postfix + Dovecot"
    systemctl restart dovecot postfix
    systemctl enable dovecot postfix
}


# ==============================================================================
# SECTION 3: SAO LUU - BACKUP
#   Mount /dev/sdb1 -> /opt/backup (tu dong khi boot), tao script sao luu
#   mailbox + cau hinh mail server.
# ==============================================================================

setup_backup() {
    log "Cau hinh sao luu: mount ${BACKUP_DISK} -> ${BACKUP_MOUNT}"

    mkdir -p "${BACKUP_MOUNT}"

    if ! blkid "${BACKUP_DISK}" > /dev/null 2>&1; then
        log "Dinh dang ${BACKUP_DISK} (ext4) - CHI CHAY LAN DAU, se XOA DU LIEU tren dia nay neu co"
        mkfs.ext4 -F "${BACKUP_DISK}"
    fi

    local uuid
    uuid=$(blkid -s UUID -o value "${BACKUP_DISK}")

    if ! grep -q "${uuid}" /etc/fstab; then
        echo "UUID=${uuid}   ${BACKUP_MOUNT}   ext4   defaults   0   2" >> /etc/fstab
    fi

    mount -a

    log "Ghi script sao luu tu dong: ${BACKUP_SCRIPT}"
    cat > "${BACKUP_SCRIPT}" << EOF
#!/bin/bash
#
# Script sao luu du lieu mail server: mailbox (Maildir) + cau hinh Postfix/Dovecot
# Dich luu: ${BACKUP_MOUNT}
#
set -euo pipefail

BACKUP_ROOT="${BACKUP_MOUNT}"
TIMESTAMP=\$(date +%Y%m%d-%H%M%S)
DEST="\${BACKUP_ROOT}/backup-\${TIMESTAMP}"

mkdir -p "\${DEST}/mail" "\${DEST}/config"

# 1. Sao luu toan bo mailbox (Maildir)
rsync -a --delete /var/mail/vhosts/ "\${DEST}/mail/"

# 2. Sao luu cau hinh Postfix
cp -a /etc/postfix "\${DEST}/config/postfix"

# 3. Sao luu cau hinh Dovecot
cp -a /etc/dovecot "\${DEST}/config/dovecot"

# 4. Sao luu chung chi TLS cua mail server
mkdir -p "\${DEST}/config/ssl"
cp -a ${MAIL_CERT} ${MAIL_KEY} "\${DEST}/config/ssl/" 2>/dev/null || true

# 5. Giu symlink "latest" tro toi ban sao luu moi nhat
ln -sfn "\${DEST}" "\${BACKUP_ROOT}/latest"

echo "[\$(date)] Backup hoan tat: \${DEST}"
EOF
    chmod +x "${BACKUP_SCRIPT}"

    log "Lap lich sao luu tu dong hang ngay 2h sang (cron)"
    if ! crontab -l 2>/dev/null | grep -q "${BACKUP_SCRIPT}"; then
        (crontab -l 2>/dev/null; echo "0 2 * * * ${BACKUP_SCRIPT} >> /var/log/backup.log 2>&1") | crontab -
    fi
}


# ==============================================================================
# SECTION 4: QUAN LY KHOA SSH - SSH USER CERTIFICATE
#   mail CHAP NHAN dang nhap SSH bang chung chi nguoi dung, CA duoc tao
#   san tren ha-prx01 (proof-of-concept, chi ap dung cho mail server).
# ==============================================================================

setup_ssh_certificate() {
    log "Cau hinh mail chap nhan dang nhap SSH bang User Certificate"

    if scp ${SSH_OPTS} "root@${SSH_CA_SOURCE_HOST}:${SSH_CA_SOURCE_PATH}" "${SSH_CA_LOCAL_PATH}" 2>/dev/null; then
        if ! grep -q "TrustedUserCAKeys" /etc/ssh/sshd_config; then
            echo "TrustedUserCAKeys ${SSH_CA_LOCAL_PATH}" >> /etc/ssh/sshd_config
        fi
        systemctl restart ssh
        log "Da cau hinh TrustedUserCAKeys thanh cong tu ha-prx01"
    else
        log "CANH BAO: chua fetch duoc user_ca.pub tu ha-prx01 (${SSH_CA_SOURCE_HOST})."
        log "  -> Nguyen nhan thuong gap: ha-prx01 chua chay xong buoc tao SSH CA."
        log "  -> Chay lai 'setup_ssh_certificate' (hoac ca mail-setup.sh) SAU KHI"
        log "     da hoan tat ha-prx01-setup.sh."
    fi
}


# ==============================================================================
# SECTION 5: KIEM TRA TONG QUAT SAU KHI CAU HINH DICH VU
# ==============================================================================

verify_services() {
    log "===== TOM TAT KIEM TRA DICH VU ====="

    echo "--- Postfix + Dovecot: trang thai dich vu ---"
    systemctl is-active postfix
    systemctl is-active dovecot

    echo -e "\n--- IMAP/IMAPS: cong dang lang nghe ---"
    ss -tlnp | grep -E ':143|:993' || echo "CANH BAO: chua thay cong IMAP/IMAPS!"

    echo -e "\n--- Backup: mount va script ---"
    df -h "${BACKUP_MOUNT}" || echo "CANH BAO: ${BACKUP_MOUNT} chua duoc mount!"
    [[ -x "${BACKUP_SCRIPT}" ]] && echo "  [OK] ${BACKUP_SCRIPT} ton tai va co quyen thuc thi"

    echo -e "\n--- SSH Certificate ---"
    grep -i "TrustedUserCAKeys" /etc/ssh/sshd_config || echo "  [CHUA CAU HINH] TrustedUserCAKeys (xem lai SECTION 4)"

    log "Hoan tat cau hinh dich vu cho mail.dmz.pvnskills.org"
}


# ==============================================================================
# SECTION 6: MAIN
# ==============================================================================

main() {
    require_root
    setup_mail_server
    setup_backup
    setup_ssh_certificate
    verify_services
}

main "$@"
