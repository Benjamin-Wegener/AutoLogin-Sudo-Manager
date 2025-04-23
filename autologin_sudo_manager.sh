#!/bin/bash

# Script Name: autologin_sudo_manager.sh
# Description: Manages automatic login and passwordless sudo for the current user.
# Usage: ./autologin_sudo_manager.sh [help|remove]

# Function to display help
display_help() {
    echo "Usage: $0 [help|remove]"
    echo
    echo "Options:"
    echo "   help      Displays this help message."
    echo "   remove    Removes automatic login and passwordless sudo settings."
    echo
    echo "If no option is provided, the script will set up automatic login and passwordless sudo."
}

# Function to get the current user
get_current_user() {
    # Try logname first
    if [[ -n $(logname 2>/dev/null) ]]; then
        echo "$(logname)"
    else
        # Fallback to parsing /var/run/utmp or using who
        whoami
    fi
}

# Function to manage the autologin group
manage_autologin_group() {
    local user=$1

    # Check if the autologin group exists
    if ! getent group autologin >/dev/null; then
        echo "Creating autologin group..."
        groupadd -r autologin
    fi

    # Add the user to the autologin group
    if ! groups "$user" | grep -qw autologin; then
        echo "Adding user $user to the autologin group..."
        gpasswd -a "$user" autologin
    fi
}

# Function to remove autologin and passwordless sudo
remove_settings() {
    local CURRENT_USER=$1

    # Remove GDM autologin
    if systemctl is-active --quiet gdm; then
        echo "Disabling autologin for GDM..."
        systemctl edit --full gdm
        sed -i '/^ExecStart=/d' /etc/systemd/system/gdm.service.d/override.conf
    fi

    # Remove LightDM autologin
    if [[ -f /etc/lightdm/lightdm.conf.bak ]]; then
        echo "Restoring LightDM configuration..."
        mv /etc/lightdm/lightdm.conf.bak /etc/lightdm/lightdm.conf
    fi

    # Remove SDDM autologin
    if [[ -f /etc/sddm.conf.bak ]]; then
        echo "Restoring SDDM configuration..."
        mv /etc/sddm.conf.bak /etc/sddm.conf
    fi

    # Remove the user from the autologin group
    if groups "$CURRENT_USER" | grep -qw autologin; then
        echo "Removing user $CURRENT_USER from the autologin group..."
        gpasswd -d "$CURRENT_USER" autologin
    fi

    # Remove passwordless sudo
    echo "Removing passwordless sudo for user $CURRENT_USER..."
    cp /etc/sudoers /etc/sudoers.backup
    sed -i "/^$CURRENT_USER ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers

    # Verify sudoers syntax
    if ! visudo -c >/dev/null 2>&1; then
        echo "Error: Invalid sudoers file. Restoring backup..."
        mv /etc/sudoers.backup /etc/sudoers
    fi

    echo "Settings removed. Reboot your system for changes to take effect."
}

# Function to enable autologin for GDM
enable_gdm_autologin() {
    local USER=$1
    echo "Enabling autologin for GDM..."
    systemctl edit gdm <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/gdm --automatic-login $USER
EOF
}

# Function to enable autologin for LightDM
enable_lightdm_autologin() {
    local USER=$1
    echo "Enabling autologin for LightDM..."
    if [[ ! -f /etc/lightdm/lightdm.conf ]]; then
        echo "LightDM configuration file not found. Skipping..."
        return
    fi
    cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.bak
    sed -i '/^\[Seat:.*/,/^\[/ s/^#*autologin-user=.*/autologin-user='"$USER"'/' /etc/lightdm/lightdm.conf
    sed -i '/^\[Seat:.*/,/^\[/ s/^#*autologin-session=.*/autologin-session=default/' /etc/lightdm/lightdm.conf
}

# Function to enable autologin for SDDM
enable_sddm_autologin() {
    local USER=$1
    echo "Enabling autologin for SDDM..."
    if [[ ! -f /etc/sddm.conf ]]; then
        echo "SDDM configuration file not found. Skipping..."
        return
    fi
    cp /etc/sddm.conf /etc/sddm.conf.bak
    sed -i '/^\[Autologin\]/,/^\[/ s/^#*User=.*/User='"$USER"'/' /etc/sddm.conf
    sed -i '/^\[Autologin\]/,/^\[/ s/^#*Session=.*/Session=plasma.desktop/' /etc/sddm.conf
}

# Function to enable passwordless sudo for the current user
enable_passwordless_sudo() {
    local USER=$1
    echo "Enabling passwordless sudo for user $USER..."
    cp /etc/sudoers /etc/sudoers.bak
    echo "$USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    # Verify sudoers syntax
    if ! visudo -c >/dev/null 2>&1; then
        echo "Error: Invalid sudoers file. Restoring backup..."
        mv /etc/sudoers.bak /etc/sudoers
        exit 1
    fi
}

# Main script logic
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

CURRENT_USER=$(get_current_user)

case "$1" in
    help)
        display_help
        exit 0
        ;;
    remove)
        remove_settings "$CURRENT_USER"
        exit 0
        ;;
    *)
        echo "Detecting display manager..."

        # Manage the autologin group
        manage_autologin_group "$CURRENT_USER"

        if systemctl is-active --quiet gdm; then
            echo "GDM is running."
            enable_gdm_autologin "$CURRENT_USER"
        elif systemctl is-active --quiet lightdm; then
            echo "LightDM is running."
            enable_lightdm_autologin "$CURRENT_USER"
        elif systemctl is-active --quiet sddm; then
            echo "SDDM is running."
            enable_sddm_autologin "$CURRENT_USER"
        else
            echo "No supported display manager detected (checked GDM, LightDM, SDDM)."
            exit 1
        fi

        # Enable passwordless sudo
        enable_passwordless_sudo "$CURRENT_USER"

        echo "Setup complete. Reboot your system for changes to take effect."
        ;;
esac
