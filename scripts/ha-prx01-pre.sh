#!/bin/bash

set -euo pipefail

SCRIPT_NAME="ha-prx01-pre.sh"
DOCSET_SOURCE_DIR="${DOCSET_SOURCE_DIR:-/opt/docsets}"
VSCODE_DEB="${VSCODE_DEB:-}"

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "${SCRIPT_NAME} phai duoc chay bang quyen root."
}

install_vscode() {
    if command -v code >/dev/null 2>&1; then
        log "Da co Visual Studio Code"
        return 0
    fi

    if [[ -z "${VSCODE_DEB}" ]]; then
        VSCODE_DEB="$(find /opt /root /tmp -maxdepth 4 -type f -iname 'code_*.deb' -print -quit 2>/dev/null || true)"
    fi

    if [[ -n "${VSCODE_DEB}" && -f "${VSCODE_DEB}" ]]; then
        log "Cai Visual Studio Code tu goi offline: ${VSCODE_DEB}"
        apt-get install -y "${VSCODE_DEB}"
        return 0
    fi

    if apt-cache show code >/dev/null 2>&1; then
        log "Cai Visual Studio Code tu APT"
        apt-get install -y code
        return 0
    fi

    die "Khong tim thay VS Code. Dat file .deb vao /opt hoac chay voi VSCODE_DEB=/duong/dan/code.deb."
}

install_zeal_docsets() {
    local zeal_docset_dir="/root/.local/share/Zeal/Zeal/docsets"
    local docset_count=0

    mkdir -p "${zeal_docset_dir}"

    if [[ -d "${DOCSET_SOURCE_DIR}" ]]; then
        while IFS= read -r -d '' docset; do
            cp -a "${docset}" "${zeal_docset_dir}/"
            docset_count=$((docset_count + 1))
        done < <(find "${DOCSET_SOURCE_DIR}" -maxdepth 2 -type d -name '*.docset' -print0)
    fi

    if [[ "${docset_count}" -eq 0 ]]; then
        printf 'WARNING: Chua tim thay docset offline trong %s.\n' "${DOCSET_SOURCE_DIR}" >&2
        printf '         Dat cac thu muc Python.docset, Ansible.docset, Nginx.docset va Bash.docset vao thu muc nay.\n' >&2
    else
        log "Da sao chep ${docset_count} docset vao ${zeal_docset_dir}"
    fi
}

verify_installation() {
    local failed=0

    log "Kiem tra phan mem"
    for command_name in bash python3 ansible-playbook nginx code zeal gnome-shell; do
        if command -v "${command_name}" >/dev/null 2>&1; then
            printf '%-20s OK (%s)\n' "${command_name}" "$(command -v "${command_name}")"
        else
            printf '%-20s THIEU\n' "${command_name}"
            failed=1
        fi
    done

    if command -v nginx >/dev/null 2>&1; then
        nginx -t
    fi

    [[ "${failed}" -eq 0 ]] || die "Mot hoac nhieu thanh phan chua duoc cai dat."
}

main() {
    require_root

    log "Cai dat cac thanh phan cho ha-prx01"
    apt-get update
    apt-get install -y \
        bash bash-completion sudo curl wget git ca-certificates \
        python3 python3-pip python3-venv python3-dev python3-setuptools \
        ansible nginx zeal

    apt-get install -y task-gnome-desktop gnome-shell gdm3
    install_vscode
    install_zeal_docsets

    systemctl set-default graphical.target
    if systemctl list-unit-files gdm3.service >/dev/null 2>&1; then
        systemctl enable gdm3
    fi
    systemctl enable --now nginx

    verify_installation
    log "Hoan tat cai dat phan mem cho ha-prx01"
}

main "$@"