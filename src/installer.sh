#!/bin/bash
#
# Install Game Server
#
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@bitsnbytes.dev>
# @CATEGORY Game Server
# @TRMM-TIMEOUT 600
# @WARLOCK-TITLE VEIN
# @WARLOCK-IMAGE media/some-game-image.webp
# @WARLOCK-ICON media/some-game-icon.webp
# @WARLOCK-THUMBNAIL media/some-game-thumbnail.webp
#
# Supports:
#   Debian 12, 13
#   Ubuntu 24.04
#
# Requirements:
#   None
#
# TRMM Custom Fields:
#   None
#
# Syntax:
#   MODE_UNINSTALL=--uninstall - Perform an uninstallation
#   OVERRIDE_DIR=--dir=<path> - Use a custom installation directory instead of the default (optional)
#   SKIP_FIREWALL=--skip-firewall - Do not install or configure a system firewall
#   USE_BRANCH=--branch=<stable|experimental> - Install a different branch from Steam (optional)
#   NONINTERACTIVE=--non-interactive - Run the installer in non-interactive mode (useful for scripted installs)
#
# Changelog:
#   20251103 - New installer

############################################
## Parameter Configuration
############################################

# Name of the game (used to create the directory)
INSTALLER_VERSION="v20251120~DEV"
GAME="VEIN"
GAME_DESC="VEIN Dedicated Server"
REPO="BitsNBytes25/VEIN-Dedicated-Server"
WARLOCK_GUID="acdf1bec-2906-c20f-5a59-b0df072c29e8"
# Steam ID of the game
STEAM_ID="2131400"
GAME_USER="steam"
GAME_DIR="/home/${GAME_USER}/${GAME}"
GAME_SERVICE="vein-server"
# Force installation directory for game
# steam produces varying results, sometimes in ~/.local/share/Steam, other times in ~/Steam
STEAM_DIR="/home/${GAME_USER}/.local/share/Steam"
# VEIN uses the default Epic save handler which stores saves in ~/.config
SAVE_DIR="/home/${GAME_USER}/.config/Epic/Vein/Saved/SaveGames/"
#PORT_GAME=7777
#PORT_QUERY=27015

# compile:usage
# compile:argparse
# scriptlet:_common/require_root.sh
# scriptlet:_common/get_firewall.sh
# scriptlet:_common/package_install.sh
# scriptlet:_common/firewall_allow.sh
# scriptlet:_common/download.sh
# scriptlet:bz_eval_tui/prompt_text.sh
# scriptlet:bz_eval_tui/prompt_yn.sh
# scriptlet:bz_eval_tui/print_header.sh
# scriptlet:steam/install-steamcmd.sh
# scriptlet:ufw/install.sh

print_header "$GAME_DESC *unofficial* Installer ${INSTALLER_VERSION}"

############################################
## Installer Actions
############################################

##
# Install the VEIN game server using Steam
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#   STEAM_ID     - Steam App ID of the game
#   GAME_DESC    - Description of the game (for logging purposes)
#   GAME_SERVICE - Service name to install with Systemd
#   SAVE_DIR     - Directory to store game save files
#
function install_application() {
	print_header "Performing install_application"

	# Create a "steam" user account
	# This will create the account with no password, so if you need to log in with this user,
	# run `sudo passwd steam` to set a password.
	if [ -z "$(getent passwd $GAME_USER)" ]; then
		useradd -m -U $GAME_USER
	fi

	# Preliminary requirements
	# VEIN needs ALSA and PulseAudio libraries to run
	package_install curl sudo libasound2-data libpulse0 python3-venv

	if [ "$FIREWALL" == "1" ]; then
		if [ "$(get_enabled_firewall)" == "none" ]; then
			# No firewall installed, go ahead and install UFW
			install_ufw
		fi
	fi

	# Install steam binary and steamcmd
	install_steamcmd

	if ! sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir "$GAME_DIR/AppFiles" +login anonymous +app_update $STEAM_ID validate +quit; then
		echo "Could not install $GAME_DESC, exiting" >&2
		exit 1
	fi

	# VEIN requires the Steam client binary to be loaded into the game server
	[ -h "$GAME_DIR/AppFiles/Vein/Binaries/Linux/steamclient.so" ] || \
		sudo -u $GAME_USER \
		ln -s /home/$GAME_USER/.steam/steam/steamcmd/linux64/steamclient.so "$GAME_DIR/AppFiles/Vein/Binaries/Linux/steamclient.so"

	# Install system service file to be loaded by systemd
    cat > /etc/systemd/system/${GAME_SERVICE}.service <<EOF
# script:systemd-template.service
EOF
    systemctl daemon-reload
    systemctl enable $GAME_SERVICE

    # Ensure necessary directories exist
    [ -d "$SAVE_DIR" ] || sudo -u $GAME_USER mkdir -p "$SAVE_DIR"

    # Ensure game configurations exist, (for convenience)
    [ -e "$GAME_DIR/AppFiles/Vein/Saved/Config/LinuxServer" ] || \
    	sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles/Vein/Saved/Config/LinuxServer"
	[ -e "$GAME_DIR/AppFiles/Vein/Saved/Config/LinuxServer/Game.ini" ] || \
		sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/Vein/Saved/Config/LinuxServer/Game.ini"
	[ -e "$GAME_DIR/AppFiles/Vein/Saved/Config/LinuxServer/GameUserSettings.ini" ] || \
		sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/Vein/Saved/Config/LinuxServer/GameUserSettings.ini"

	# Symlink for convenience
	[ -h "$GAME_DIR/Game.ini" ] || \
		sudo -u $GAME_USER ln -s "$GAME_DIR/AppFiles/Vein/Saved/Config/LinuxServer/Game.ini" "$GAME_DIR/Game.ini"
	[ -h "$GAME_DIR/GameUserSettings.ini" ] || \
		sudo -u $GAME_USER ln -s "$GAME_DIR/AppFiles/Vein/Saved/Config/LinuxServer/GameUserSettings.ini" "$GAME_DIR/GameUserSettings.ini"
	[ -h "$GAME_DIR/SaveGames" ] || sudo -u $GAME_USER ln -s "$SAVE_DIR" "$GAME_DIR/SaveGames"
	[ -h "$GAME_DIR/Vein.log" ] || \
		sudo -u $GAME_USER ln -s "$GAME_DIR/AppFiles/Vein/Saved/Logs/Vein.log" "$GAME_DIR/Vein.log"

	if [ -n "$WARLOCK_GUID" ]; then
		# Register Warlock
		[ -d "/var/lib/warlock" ] || mkdir -p "/var/lib/warlock"
		echo -n "$GAME_DIR" > "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

##
# Install the management script from the project's repo
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#
function install_management() {
	print_header "Performing install_management"

	# Install management console and its dependencies
	local SRC=""

	if [[ "$INSTALLER_VERSION" == *"~DEV"* ]]; then
		# Development version, pull from dev branch
		SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/dev/dist/manage.py"
	else
		# Stable version, pull from tagged release
		SRC="https://raw.githubusercontent.com/${REPO}/refs/tags/${INSTALLER_VERSION}/dist/manage.py"
	fi

	if ! download "$SRC" "$GAME_DIR/manage.py"; then
		echo "Could not download management script!" >&2
		exit 1
	fi

	chown $GAME_USER:$GAME_USER "$GAME_DIR/manage.py"
	chmod +x "$GAME_DIR/manage.py"

	# Install configuration definitions
	cat > "$GAME_DIR/configs.yaml" <<EOF
# script:configs.yaml
EOF

	# If a pyenv is required:
	sudo -u $GAME_USER python3 -m venv "$GAME_DIR/.venv"
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install --upgrade pip
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install pyyaml
}

function postinstall() {
	print_header "Performing postinstall"

	# First run setup
	$GAME_DIR/manage.py --first-run
}

##
# Uninstall the VEIN game server
#
# Expects the following variables:
#   GAME_DIR     - Directory where the game is installed
#   GAME_SERVICE - Service name used with Systemd
#   SAVE_DIR     - Directory where game save files are stored
#
function uninstall_application() {
	print_header "Performing uninstall_application"

	systemctl disable $GAME_SERVICE
	systemctl stop $GAME_SERVICE

	# Save directory, (usually outside of GAME_DIR)
	[ -n "$SAVE_DIR" -a -d "$SAVE_DIR" ] && rm -fr "$SAVE_DIR"

	# Symlinks
	[ -h "$GAME_DIR/Game.ini" ] && unlink "$GAME_DIR/Game.ini"
	[ -h "$GAME_DIR/GameUserSettings.ini" ] && unlink "$GAME_DIR/GameUserSettings.ini"
	[ -h "$GAME_DIR/SaveGames" ] && unlink "$GAME_DIR/SaveGames"
	[ -h "$GAME_DIR/Vein.log" ] && unlink "$GAME_DIR/Vein.log"

	# Service files
	[ -e "/etc/systemd/system/${GAME_SERVICE}.service" ] && rm "/etc/systemd/system/${GAME_SERVICE}.service"

	# Game files
	[ -d "$GAME_DIR" ] && rm -rf "$GAME_DIR/AppFiles"

	# Management scripts
	[ -e "$GAME_DIR/manage.py" ] && rm "$GAME_DIR/manage.py"
	[ -e "$GAME_DIR/configs.yaml" ] && rm "$GAME_DIR/configs.yaml"
	[ -d "$GAME_DIR/.venv" ] && rm -rf "$GAME_DIR/.venv"

	if [ -n "$WARLOCK_GUID" ]; then
		# unregister Warlock
		[ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] && rm "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

############################################
## Pre-exec Checks
############################################

if [ $MODE_UNINSTALL -eq 1 ]; then
	MODE="uninstall"
else
	# Default to install mode
	MODE="install"
fi


if systemctl -q is-active $GAME_SERVICE; then
	echo "$GAME_DESC service is currently running, please stop it before running this installer."
	echo "You can do this with: sudo systemctl stop $GAME_SERVICE"
	exit 1
fi

if [ -n "$OVERRIDE_DIR" ]; then
	# User requested to change the install dir!
	# This changes the GAME_DIR from the default location to wherever the user requested.
	if [ -e "/etc/systemd/system/${GAME_SERVICE}.service" ]; then
    	# Check for existing installation directory based on service file
    	GAME_DIR="$(egrep '^WorkingDirectory' "/etc/systemd/system/${GAME_SERVICE}.service" | sed 's:.*=\(.*\)/AppFiles.*:\1:')"
    	if [ "$GAME_DIR" != "$OVERRIDE_DIR" ]; then
    		echo "ERROR: $GAME_DESC already installed in $GAME_DIR, cannot override to $OVERRIDE_DIR" >&2
    		echo "If you want to move the installation, please uninstall first and then re-install to the new location." >&2
    		exit 1
		fi
	fi

	GAME_DIR="$OVERRIDE_DIR"
	echo "Using ${GAME_DIR} as the installation directory based on explicit argument"
elif [ -e "/etc/systemd/system/${GAME_SERVICE}.service" ]; then
	# Check for existing installation directory based on service file
	GAME_DIR="$(egrep '^WorkingDirectory' "/etc/systemd/system/${GAME_SERVICE}.service" | sed 's:.*=\(.*\)/AppFiles.*:\1:')"
	echo "Detected installation directory of ${GAME_DIR} based on service registration"
else
	echo "Using default installation directory of ${GAME_DIR}"
fi

if [ -e "/etc/systemd/system/${GAME_SERVICE}.service" ]; then
	EXISTING=1
else
	EXISTING=0
fi

if [ -e "/etc/systemd/system/${GAME_SERVICE}.service" ]; then
	if egrep -q '^ExecStartPre=.*-beta ' "/etc/systemd/system/${GAME_SERVICE}.service"; then
		BETA="$(egrep '^ExecStartPre=.*-beta ' "/etc/systemd/system/${GAME_SERVICE}.service" | sed 's:.*-beta \([^ ]*\) .*:\1:')"
	else
		BETA=""
	fi
else
	BETA=""
fi

############################################
## Installer
############################################


if [ "$MODE" == "install" ]; then

	if [ $SKIP_FIREWALL -eq 1 ]; then
		FIREWALL=0
	elif [ $EXISTING -eq 0 ] && prompt_yn -q --default-yes "Install system firewall?"; then
		FIREWALL=1
	else
		FIREWALL=0
	fi

	if [ -n "$USE_BRANCH" ]; then
		# User requested a specific branch
		if [ "$USE_BRANCH" == "stable" ]; then
			BETA=""
		else
			BETA="$USE_BRANCH"
		fi
	elif [ -n "$BETA" ]; then
		echo "Using beta branch $BETA"
		if prompt_yn -q --default-no "Switch to stable branch?"; then
			BETA=""
		fi
	else
		if prompt_yn -q --default-no "Install experimental branch?"; then
			BETA="experimental"
		fi
	fi

	if [ -n "$BETA" ]; then
		STEAMBETABRANCH=" -beta $BETA"
	else
		STEAMBETABRANCH=""
	fi

	install_application

	install_management

	postinstall

	# Print some instructions and useful tips
    print_header "$GAME_DESC Installation Complete"
    echo 'Game server will auto-update on restarts and will auto-start on server boot.'
    echo ''
    echo "Game files:     $GAME_DIR/AppFiles/"
    echo "Game settings:  $GAME_DIR/Game.ini"
    echo "GUS settings:   $GAME_DIR/GameUserSettings.ini"
    echo "Log:            $GAME_DIR/Vein.log"
    echo ''
    echo "Next steps: configure your server by running"
    echo "sudo $GAME_DIR/manage.py"
fi

if [ "$MODE" == "uninstall" ]; then
	if [ $NONINTERACTIVE -eq 0 ]; then
		if prompt_yn -q --invert --default-no "This will remove all game binary content"; then
			exit 1
		fi
		if prompt_yn -q --invert --default-no "This will remove all player and map data"; then
			exit 1
		fi
	fi

	if prompt_yn -q --default-yes "Perform a backup before everything is wiped?"; then
		$GAME_DIR/manage.py --backup
	fi

	uninstall_application
fi
