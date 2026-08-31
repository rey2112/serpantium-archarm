#!/usr/bin/env bash

# Hardware detection helpers.
#
# Everything here is sourced into a `set -e` installer, so each command
# substitution is guarded. The classic trap is a pipeline ending in `grep`:
# with nothing to match it exits 1 and takes the whole installer down without
# printing anything. That is exactly what happens on machines with no PCI
# graphics -- Apple Silicon under Asahi, and ARM SoCs generally -- where
# `lspci` produces no output at all.
#
# Detection is layered rather than gated on `uname -m`: the PCI probe still
# runs first and wins whenever it finds something, so x86_64 results are
# unchanged. The extra layers only run when the ones above them come up empty.

read_dt_string() {
    local file="$1"
    [ -r "$file" ] || return 0
    # Device-tree properties are NUL-terminated.
    tr -d '\0' < "$file" 2>/dev/null || true
    return 0
}

detect_machine_model() {
    local model=""

    # Device tree: Apple Silicon reports e.g. "Apple MacBook Pro (14-inch, M2 Pro, 2023)".
    model=$(read_dt_string /sys/firmware/devicetree/base/model)
    [ -n "$model" ] || model=$(read_dt_string /proc/device-tree/model)

    # DMI: x86 and ARM servers with firmware tables.
    [ -n "$model" ] || model=$(read_dt_string /sys/devices/virtual/dmi/id/product_name)

    printf '%s' "$model"
    return 0
}

detect_cpu_info() {
    local cpu=""

    # x86 exposes a marketing name here. ARM /proc/cpuinfo has no 'model name'
    # field at all, so this comes back empty on Apple Silicon.
    cpu=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || true)

    # On device-tree platforms the machine model carries the useful string.
    [ -n "$cpu" ] || cpu=$(detect_machine_model)

    [ -n "$cpu" ] || cpu=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1 || true)

    printf '%s' "$cpu"
    return 0
}

detect_gpu_info() {
    local gpu=""
    local raw=""

    # PCI path: x86, and any machine with PCI/PCIe graphics.
    if command -v lspci &>/dev/null; then
        raw=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)
        if [ -n "$raw" ]; then
            gpu=$(printf '%s\n' "$raw" | cut -d: -f3 | sed -E 's/ \(rev [0-9a-f]+\)//g' | xargs || true)
        fi
    fi

    # Non-PCI path: the Apple Silicon GPU is a device-tree node hanging off the
    # SoC, so lspci never sees it. Ask DRM which driver actually bound.
    if [ -z "$gpu" ]; then
        local card name drv
        for card in /sys/class/drm/card*; do
            name="${card##*/}"
            # Skip connector entries such as card0-DP-1.
            case "$name" in
                card[0-9]|card[0-9][0-9]) ;;
                *) continue ;;
            esac
            [ -r "$card/device/uevent" ] || continue
            drv=$(sed -n 's/^DRIVER=//p' "$card/device/uevent" 2>/dev/null | head -n 1 || true)
            [ -n "$drv" ] || continue
            case "$drv" in
                asahi|apple*) gpu="Apple Silicon GPU ($drv)" ;;
                *) gpu="$drv" ;;
            esac
            break
        done
    fi

    printf '%s' "$gpu"
    return 0
}
