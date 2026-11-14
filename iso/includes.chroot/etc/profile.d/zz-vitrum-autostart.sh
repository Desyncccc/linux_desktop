# Live session: start Vitrum on the first console after autologin.
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(id -u)" -ne 0 ]; then
    clear
    vitrum-session
    # Signing out returns here; start again rather than showing a console.
    exec vitrum-session
fi
