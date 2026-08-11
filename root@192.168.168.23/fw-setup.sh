#!/bin/bash
#
# ==============================================================================
#  fw-setup.sh
#  Cau hinh cac DICH VU CHINH (phuc tap) cho fw.pvnskills.org
#  (nftables Firewall & NAT, WireGuard VPN, Transparent Proxy - Squid)
#
#  De thi: Quan tri va Bao mat He thong mang CNTT - Module A (PVNSkills 2026)
#
#  YEU CAU: fw.sh phai da chay THANH CONG truoc do (hostname, IP, forwarding
#  da san sang). File nay tu "source fw.sh" de tai su dung bien/ham dung
#  chung (IF_WAN, IF_INT, IF_DMZ, VIP4, WG_*, SQUID_*, log(), require_root())
#  ma KHONG chay lai cac buoc cai dat co ban cua fw.sh (xem co che guard
#  o SECTION 8 cua fw.sh).
#
#  Cach chay:
#     scp fw.sh fw-setup.sh root@1.1.1.10:/root/
#     ssh root@1.1.1.10 "bash /root/fw.sh && bash /root/fw-setup.sh"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SECTION 1: NAP BIEN & HAM DUNG CHUNG TU fw.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/fw.sh" ]]; then
    echo "Khong tim thay fw.sh cung thu muc voi fw-setup.sh. Dat 2 file chung 1 thu muc." >&2
    exit 1
fi

# shellcheck source=fw.sh
source "${SCRIPT_DIR}/fw.sh"
# Luu y: cau lenh source o tren KHONG lam chay main() cua fw.sh,
# vi fw.sh chi tu goi main() khi duoc thuc thi truc tiep (xem SECTION 8 cua fw.sh)


# ==============================================================================
# SECTION 2: FIREWALL & NAT - NFTABLES
#   - (a) INT, DMZ -> Internet: cho phep
#   - (b) INT -> DMZ: cho phep
#   - (c) Masquerade NAT tren WAN
#   - (d) Port-forward 80/443/53 -> VIP Reverse Proxy trong DMZ
#   - (e) VPN Client -> INT + DMZ: cho phep
#   - (f) mail (DMZ) -> int-srv01 (INT) cong LDAP 389/tcp: cho phep
#   - (g) Con lai: default deny
#   - IPv6: tuong tu (tru khong can Masquerade)
#   - Kem san luat redirect cho Transparent Proxy (SECTION 4)
# ==============================================================================

setup_nftables() {
    log "Cai dat nftables"
    apt update
    apt install -y nftables
    systemctl enable nftables

    log "Ghi ruleset nftables vao /etc/nftables.conf"
    cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f

flush ruleset

define WAN = ${IF_WAN}
define INT = ${IF_INT}
define DMZ = ${IF_DMZ}
define VPN = ${IF_VPN}

define VIP4 = ${VIP4}
define VIP6 = ${VIP6}

table inet filter {

    chain input {
        type filter hook input priority 0; policy drop;

        iif lo accept
        ct state established,related accept
        ct state invalid drop

        # Quan tri/kiem tra toi chinh fw
        tcp dport 22 accept
        udp dport ${WG_PORT} accept
        icmp type echo-request accept
        icmpv6 type { echo-request, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;

        ct state established,related accept
        ct state invalid drop

        # (a) INT, DMZ -> Internet (WAN) - IPv4 & IPv6
        iifname { \$INT, \$DMZ } oifname \$WAN accept

        # (b) INT -> DMZ - IPv4 & IPv6
        iifname \$INT oifname \$DMZ accept

        # (e) VPN Client -> INT + DMZ - IPv4 & IPv6
        iifname \$VPN oifname { \$INT, \$DMZ } accept

        # (f) mail (DMZ) -> int-srv01 (INT), LDAP 389/tcp
        iifname \$DMZ oifname \$INT ip saddr 10.1.20.10 ip daddr 10.1.10.10 tcp dport 389 accept
        iifname \$DMZ oifname \$INT ip6 saddr 2001:db8:1001:20::10 ip6 daddr 2001:db8:1001:10::10 tcp dport 389 accept

        # (d) WAN -> DMZ: chi cac cong port-forward (80/443/53) toi VIP
        iifname \$WAN oifname \$DMZ ip daddr \$VIP4 tcp dport { 80, 443 } accept
        iifname \$WAN oifname \$DMZ ip daddr \$VIP4 udp dport 53 accept
        iifname \$WAN oifname \$DMZ ip daddr \$VIP4 tcp dport 53 accept
        iifname \$WAN oifname \$DMZ ip6 daddr \$VIP6 tcp dport { 80, 443 } accept

        # (g) Con lai: default deny (policy drop da ap dung o tren)
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;

        # (d) Port forwarding HTTP/HTTPS/DNS -> Reverse Proxy HA (VIP DMZ)
        iifname \$WAN tcp dport 80  dnat to \$VIP4:80
        iifname \$WAN tcp dport 443 dnat to \$VIP4:443
        iifname \$WAN udp dport 53  dnat to \$VIP4:53
        iifname \$WAN tcp dport 53  dnat to \$VIP4:53

        # Transparent Proxy: chan HTTP (80) tu INT va VPN, redirect vao Squid
        iifname { \$INT, \$VPN } tcp dport 80 redirect to :${SQUID_INTERCEPT_PORT}
    }

    chain postrouting {
        type nat hook postrouting priority srcnat;

        # (c) Masquerade NAT: moi traffic ra WAN dung IP WAN cua fw lam nguon
        oifname \$WAN masquerade
    }
}

table ip6 nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;

        # HTTP/HTTPS tu WAN -> reverse proxy HA (IPv6)
        iifname \$WAN tcp dport 80  dnat to \$VIP6:80
        iifname \$WAN tcp dport 443 dnat to \$VIP6:443
    }

    chain postrouting {
        type nat hook postrouting priority srcnat;
        # IPv6 khong can Masquerade (dung dia chi global that)
    }
}
EOF

    log "Kiem tra cu phap va ap dung ruleset"
    nft -c -f /etc/nftables.conf
    nft -f /etc/nftables.conf
    systemctl restart nftables
}


# ==============================================================================
# SECTION 3: WIREGUARD VPN
#   - Sinh khoa Server + Client + Pre-shared key (chi 1 lan dau)
#   - Tao /etc/wireguard/wg0.conf voi PSK
#   - Chay nhu dich vu he thong (wg-quick@wg0)
# ==============================================================================

setup_wireguard() {
    log "Cai dat WireGuard"
    apt install -y wireguard wireguard-tools

    local key_dir="/etc/wireguard/keys"
    mkdir -p "${key_dir}"
    umask 077

    if [[ ! -f "${key_dir}/server_private.key" ]]; then
        log "Sinh khoa Server + Client + Pre-shared key (chi chay lan dau)"
        wg genkey | tee "${key_dir}/server_private.key" | wg pubkey > "${key_dir}/server_public.key"
        wg genkey | tee "${key_dir}/client_private.key" | wg pubkey > "${key_dir}/client_public.key"
        wg genpsk > "${key_dir}/psk.key"
    else
        log "Da co san bo khoa WireGuard, bo qua buoc sinh khoa"
    fi

    local server_priv client_pub psk
    server_priv=$(cat "${key_dir}/server_private.key")
    client_pub=$(cat "${key_dir}/client_public.key")
    psk=$(cat "${key_dir}/psk.key")

    log "Ghi file cau hinh /etc/wireguard/wg0.conf (co PresharedKey)"
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${WG_ADDR4}, ${WG_ADDR6}
ListenPort = ${WG_PORT}
PrivateKey = ${server_priv}
SaveConfig = false

[Peer]
# jamie-pvns01
PublicKey = ${client_pub}
PresharedKey = ${psk}
AllowedIPs = ${WG_CLIENT_ADDR4}, ${WG_CLIENT_ADDR6}
EOF

    chmod 600 /etc/wireguard/wg0.conf

    log "Chay WireGuard nhu dich vu he thong (wg-quick@wg0)"
    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0

    log "Thong tin de cau hinh phia CLIENT (jamie-pvns01) - luu lai:"
    echo "    Client PrivateKey : $(cat "${key_dir}/client_private.key")"
    echo "    Server PublicKey  : $(cat "${key_dir}/server_public.key")"
    echo "    PresharedKey      : ${psk}"
    echo "    Endpoint          : 1.1.1.10:${WG_PORT}"
}


# ==============================================================================
# SECTION 4: TRANSPARENT PROXY - SQUID
#   - Che do intercept, chi cho phep mang INT + VPN
#   - Them header x-secured-by: clearsky-proxy vao MOI phan hoi HTTP
#   (Luat redirect NAT da duoc them san trong SECTION 2)
# ==============================================================================

setup_transparent_proxy() {
    log "Cai dat Squid (Transparent Proxy)"
    apt install -y squid

    log "Backup cau hinh Squid mac dinh (neu chua backup)"
    [[ -f /etc/squid/squid.conf.orig ]] || cp /etc/squid/squid.conf /etc/squid/squid.conf.orig

    log "Ghi cau hinh Squid transparent proxy"
    cat > /etc/squid/squid.conf << EOF
# ==== fw-setup.sh: Transparent Proxy config ====

http_port ${SQUID_INTERCEPT_PORT} intercept

acl int_net src 10.1.10.0/24
acl vpn_net src 10.1.30.0/24
http_access allow int_net
http_access allow vpn_net
http_access deny all

# Them header vao MOI phan hoi HTTP da qua proxy (yeu cau de thi)
reply_header_add x-secured-by "clearsky-proxy"

cache_dir ufs /var/spool/squid 100 16 256
coredump_dir /var/spool/squid
EOF

    log "Khoi tao thu muc cache Squid"
    squid -z || true

    systemctl enable squid
    systemctl restart squid
}


# ==============================================================================
# SECTION 5: KIEM TRA TONG QUAT SAU KHI CAU HINH DICH VU
# ==============================================================================

verify_services() {
    log "===== TOM TAT KIEM TRA DICH VU ====="

    echo "--- nftables ruleset (rut gon) ---"
    nft list ruleset | head -20
    echo "... (xem day du: nft list ruleset)"

    echo -e "\n--- WireGuard ---"
    wg show wg0 || echo "wg0 chua co peer ket noi (binh thuong neu client chua config)"

    echo -e "\n--- Squid ---"
    systemctl is-active squid
    ss -tlnp | grep "${SQUID_INTERCEPT_PORT}" || echo "CANH BAO: Squid chua lang nghe dung cong!"

    log "Hoan tat cau hinh dich vu cho fw.pvnskills.org"
}


# ==============================================================================
# SECTION 6: MAIN
# ==============================================================================

main() {
    require_root
    setup_nftables
    setup_wireguard
    setup_transparent_proxy
    verify_services
}

main "$@"
