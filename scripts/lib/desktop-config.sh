#!/usr/bin/env bash

desktop_normalize() {
    case "${1:-}" in
        none) printf '%s\n' none ;;
        KDE|kde) printf '%s\n' kde ;;
        'KDE mobile'|kde-mobile) printf '%s\n' kde-mobile ;;
        GNOME|gnome) printf '%s\n' gnome ;;
        *) return 1 ;;
    esac
}

desktop_label() {
    case "${1:-}" in
        none) printf '%s\n' none ;;
        kde) printf '%s\n' KDE ;;
        kde-mobile) printf '%s\n' 'KDE mobile' ;;
        gnome) printf '%s\n' GNOME ;;
        *) return 1 ;;
    esac
}

display_backend_normalize() {
    case "${1:-}" in
        X11|x11|'') printf '%s\n' x11 ;;
        'Wayland'|wayland) printf '%s\n' wayland ;;
        *) return 1 ;;
    esac
}

display_backend_label() {
    case "${1:-}" in
        x11) printf '%s\n' X11 ;;
        wayland) printf '%s\n' Wayland ;;
        *) return 1 ;;
    esac
}

target_is_known() {
    case "${1:-}" in
        Debian-13|Ubuntu-24|Ubuntu-25|Ubuntu-26|Fedora-43|Fedora-44|Arch) return 0 ;;
        *) return 1 ;;
    esac
}

desktop_target_supported() {
    local target="${1:-}"
    local desktop="${2:-}"

    target_is_known "$target" || return 1
    case "$desktop" in
        none|kde) return 0 ;;
        kde-mobile)
            case "$target" in
                Debian-13|Ubuntu-26|Fedora-43|Fedora-44|Arch) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        gnome)
            case "$target" in
                Debian-13|Ubuntu-26) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

desktop_backend_supported() {
    local target="${1:-}"
    local desktop="${2:-}"
    local backend="${3:-}"

    desktop_target_supported "$target" "$desktop" || return 1
    case "$desktop:$backend" in
        none:x11|kde:x11) return 0 ;;
        kde:wayland|kde-mobile:wayland)
            case "$target" in
                Debian-13|Ubuntu-26|Fedora-43|Fedora-44|Arch) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        gnome:wayland)
            case "$target" in
                Debian-13|Ubuntu-26) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

desktop_wayland_targets_json() {
    case "${1:-}" in
        kde|kde-mobile)
            printf '%s\n' '["Debian-13","Ubuntu-26","Fedora-43","Fedora-44","Arch"]'
            ;;
        gnome)
            printf '%s\n' '["Debian-13","Ubuntu-26"]'
            ;;
        *) return 1 ;;
    esac
}


