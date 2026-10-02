#!/bin/bash
# ============================================================================== 
#  ssh_conf.sh
#  Muc dich: dam bao moi may Debian/Ubuntu deu co khoa SSH root
#  /root/.ssh/id_ed25519 va them public key vao /root/.ssh/authorized_keys.
#
#  YEU CAU DE THI:
#    - Moi may chu co khoa SSH root tai /root/.ssh/id_ed25519.
#    - Khoa do duoc them vao authorized_keys tren moi may.
#    - Khong ghi de key da co san.
#
#  Cach su dung:
#    chmod +x /root/ssh_conf.sh
#    /root/ssh_conf.sh 10.1.20.21 10.1.20.22 10.1.20.31 10.1.20.32
#    Hoac: /root/ssh_conf.sh
# ============================================================================== 

set -euo pipefail

LOCAL_KEY="/root/.ssh/id_ed25519"
LOCAL_PUB="${LOCAL_KEY}.pub"
AUTH_KEYS="/root/.ssh/authorized_keys"

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "[ERROR] Script phai chay voi quyen root. Vui long chay: sudo bash $0" >&2
        exit 1
    fi
}

ensure_local_key() {
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    if [[ ! -f "${LOCAL_KEY}" ]]; then
        echo "[INFO] Khong tim thay khoa SSH root. Dang tao khoa moi..."
        ssh-keygen -t ed25519 -f "${LOCAL_KEY}" -N "" -C "root@$(hostname -f 2>/dev/null || hostname)"
    fi

    chmod 600 "${LOCAL_KEY}"

    if [[ ! -f "${LOCAL_PUB}" ]]; then
        ssh-keygen -y -f "${LOCAL_KEY}" > "${LOCAL_PUB}"
    fi
    chmod 644 "${LOCAL_PUB}"
}

add_local_key_to_authorized_keys() {
    touch "${AUTH_KEYS}"
    chmod 600 "${AUTH_KEYS}"

    local pub_key
    pub_key="$(cat "${LOCAL_PUB}")"

    if ! grep -Fqx -- "${pub_key}" "${AUTH_KEYS}" 2>/dev/null; then
        echo "${pub_key}" >> "${AUTH_KEYS}"
        echo "[OK] Da them public key vao ${AUTH_KEYS}."
    else
        echo "[INFO] Public key da ton tai trong ${AUTH_KEYS}."
    fi
}

copy_key_to_remote() {
    local host="$1"
    local pub_key
    pub_key="$(cat "${LOCAL_PUB}")"

    echo "[INFO] Dong bo khoa den ${host}..."

    if command -v ssh-copy-id >/dev/null 2>&1; then
        ssh-copy-id -i "${LOCAL_PUB}" "root@${host}" >/dev/null 2>&1 || true
    fi

    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@${host}" \
        "mkdir -p /root/.ssh; chmod 700 /root/.ssh; touch /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; grep -Fqx -- '$pub_key' /root/.ssh/authorized_keys || printf '%s\\n' '$pub_key' >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys" \
        >/dev/null 2>&1 || {
            echo "[WARN] Khong the dong bo den ${host}. Vui long kiem tra SSH root va IP." >&2
            return 1
        }

    echo "[OK] Da dong bo khoa den ${host}."
}

default_hosts() {
    echo "10.1.10.10 10.1.20.21 10.1.20.22 10.1.20.31 10.1.20.32"
}

main() {
    require_root
    ensure_local_key
    add_local_key_to_authorized_keys

    local hosts=("$@")
    if [[ ${#hosts[@]} -eq 0 ]]; then
        read -r -a hosts <<< "$(default_hosts)"
    fi

    for host in "${hosts[@]}"; do
        copy_key_to_remote "${host}" || true
    done

    echo ""
    echo "==============================================================="
    echo "[OK] Khoa SSH root hien co: /root/.ssh/id_ed25519"
    echo "[OK] Co the dung: ssh -i /root/.ssh/id_ed25519 root@<IP_or_hostname>"
    echo "==============================================================="
}

main "$@"
