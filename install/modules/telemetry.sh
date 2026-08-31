#!/usr/bin/env bash

WORKER_URL="https://dots-telemetry.ilyamiro-work.workers.dev"

if ! declare -F detect_gpu_info &>/dev/null; then
    source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/hwdetect.sh" 2>/dev/null || true
fi

MODE=""
VERSION=""
OLD_VERSION=""
INSTALL_STATE=""
COMPOSITOR=""
TELEMETRY_ID=""
OS_NAME=""
TELEMETRY_ENABLED="true"
FAILED_PACKAGES=""
CPU_INFO=""
GPU_INFO=""
KERNEL_INFO=""
RAM_INFO=""
DE_INFO=""

format_uuid() {
    local raw
    raw=$(echo "$1" | tr -d '-' | tr '[:upper:]' '[:lower:]' | tr -cd '0-9a-f')
    if [[ ${#raw} -eq 32 ]]; then
        echo "$raw" | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
    else
        echo "$1"
    fi
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --mode|-m) MODE="$2"; shift 2 ;;
        --version|-v) VERSION="$2"; shift 2 ;;
        --old-version) OLD_VERSION="$2"; shift 2 ;;
        --install-state) INSTALL_STATE="$2"; shift 2 ;;
        --compositor|-c) COMPOSITOR="$2"; shift 2 ;;
        --id) TELEMETRY_ID="$2"; shift 2 ;;
        --os) OS_NAME="$2"; shift 2 ;;
        --enabled) TELEMETRY_ENABLED="$2"; shift 2 ;;
        --failed) FAILED_PACKAGES="$2"; shift 2 ;;
        --cpu) CPU_INFO="$2"; shift 2 ;;
        --gpu) GPU_INFO="$2"; shift 2 ;;
        --kernel) KERNEL_INFO="$2"; shift 2 ;;
        --ram) RAM_INFO="$2"; shift 2 ;;
        --de) DE_INFO="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "$MODE" ]]; then
    exit 1
fi

TELEMETRY_ID=$(format_uuid "$TELEMETRY_ID")

if [[ -z "$OS_NAME" && -f /etc/os-release ]]; then
    OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"' || true)
fi

if [[ "$OS_NAME" =~ "Fedora" ]]; then
    exit 0
fi

if [[ -z "$WORKER_URL" || "$WORKER_URL" == *"YOUR_USERNAME"* ]]; then
    exit 0
fi

payload=""

if [[ "$MODE" == "init" || "$MODE" == "full" ]]; then
    payload=$(cat <<EOF
{
  "type": "${MODE}",
  "version": "${VERSION}",
  "id": "${TELEMETRY_ID}",
  "os": "${OS_NAME//\"/\\\"}"
}
EOF
)
elif [[ "$MODE" == "done" ]]; then
    if [[ "$TELEMETRY_ENABLED" == "true" ]]; then
        [[ -z "$RAM_INFO" ]] && RAM_INFO=$(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "Unknown")
        [[ -z "$KERNEL_INFO" ]] && KERNEL_INFO=$(uname -r 2>/dev/null || echo "Unknown")
        [[ -z "$DE_INFO" ]] && DE_INFO=${XDG_CURRENT_DESKTOP:-"TTY / Unknown"}
        if [[ -z "$CPU_INFO" ]]; then
            if declare -F detect_cpu_info &>/dev/null; then
                CPU_INFO=$(detect_cpu_info)
            else
                CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || true)
            fi
        fi
        if [[ -z "$GPU_INFO" ]]; then
            if declare -F detect_gpu_info &>/dev/null; then
                GPU_INFO=$(detect_gpu_info)
            else
                GPU_RAW=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)
                GPU_INFO=$(echo "$GPU_RAW" | cut -d: -f3 | sed -E 's/ \(rev [0-9a-f]+\)//g' | xargs || true)
            fi
            [[ -z "$GPU_INFO" ]] && GPU_INFO="Unknown / Virtual Machine"
        fi

        payload=$(cat <<EOF
{
  "type": "done",
  "version": "${VERSION}",
  "old_version": "${OLD_VERSION//\"/\\\"}",
  "install_state": "${INSTALL_STATE//\"/\\\"}",
  "compositor": "${COMPOSITOR//\"/\\\"}",
  "id": "${TELEMETRY_ID}",
  "telemetry_enabled": true,
  "failed_packages": "${FAILED_PACKAGES//\"/\\\"}",
  "os": "${OS_NAME//\"/\\\"}",
  "kernel": "${KERNEL_INFO//\"/\\\"}",
  "ram": "${RAM_INFO//\"/\\\"}",
  "de": "${DE_INFO//\"/\\\"}",
  "cpu": "${CPU_INFO//\"/\\\"}",
  "gpu": "${GPU_INFO//\"/\\\"}"
}
EOF
)
    else
        payload=$(cat <<EOF
{
  "type": "done",
  "version": "${VERSION}",
  "old_version": "${OLD_VERSION//\"/\\\"}",
  "install_state": "${INSTALL_STATE//\"/\\\"}",
  "compositor": "${COMPOSITOR//\"/\\\"}",
  "id": "${TELEMETRY_ID}",
  "telemetry_enabled": false,
  "os": "${OS_NAME//\"/\\\"}"
}
EOF
)
    fi
fi

if [[ -n "$payload" ]]; then
    curl -X POST -H "Content-Type: application/json" -d "$payload" "$WORKER_URL" -s -o /dev/null &
fi
