#!/bin/bash
#
# Install Minecraft Server
#
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@bitsnbytes.dev>
# @CATEGORY Game Server
# @TRMM-TIMEOUT 600
# @WARLOCK-TITLE Minecraft
# @WARLOCK-IMAGE media/minecraft-1280x720.webp
# @WARLOCK-ICON media/minecraft-128x128.webp
# @WARLOCK-THUMBNAIL media/minecraft-713x499.webp
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
#   --uninstall  - Perform an uninstallation
#   --dir=<path> - Use a custom installation directory instead of the default (optional)
#   --skip-firewall  - Do not install or configure a system firewall
#   --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
#
# Changelog:
#   20251103 - New installer

############################################
## Parameter Configuration
############################################

# Name of the game (used to create the directory)
INSTALLER_VERSION="v20251127~DEV"
GAME="Minecraft"
GAME_DESC="Minecraft Dedicated Server"
REPO="BitsNBytes25/Minecraft-Installer"
WARLOCK_GUID="700798f0-35be-bc6c-da84-62c510dfbd06"
GAME_USER="minecraft"
GAME_DIR="/home/${GAME_USER}"
GAME_SERVICE="minecraft-server"
GAME_SOURCE="https://piston-data.mojang.com/v1/objects/95495a7f485eedd84ce928cef5e223b757d2f764/server.jar"

function usage() {
  cat >&2 <<EOD
Usage: $0 [options]

Options:
    --uninstall  - Perform an uninstallation
    --dir=<path> - Use a custom installation directory instead of the default (optional)
    --skip-firewall  - Do not install or configure a system firewall
    --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)

Please ensure to run this script as root (or at least with sudo)

@LICENSE AGPLv3
EOD
  exit 1
}

# Parse arguments
MODE_UNINSTALL=0
OVERRIDE_DIR=""
SKIP_FIREWALL=0
NONINTERACTIVE=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--uninstall) MODE_UNINSTALL=1; shift 1;;
		--dir=*)
			OVERRIDE_DIR="${1#*=}";
			[ "${OVERRIDE_DIR:0:1}" == "'" ] && [ "${OVERRIDE_DIR:0-1}" == "'" ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			[ "${OVERRIDE_DIR:0:1}" == '"' ] && [ "${OVERRIDE_DIR:0-1}" == '"' ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			shift 1;;
		--skip-firewall) SKIP_FIREWALL=1; shift 1;;
		--non-interactive) NONINTERACTIVE=1; shift 1;;
		-h|--help) usage;;
	esac
done

##
# Simple check to enforce the script to be run as root
if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi
##
# Get which firewall is enabled,
# or "none" if none located
function get_enabled_firewall() {
	if [ "$(systemctl is-active firewalld)" == "active" ]; then
		echo "firewalld"
	elif [ "$(systemctl is-active ufw)" == "active" ]; then
		echo "ufw"
	elif [ "$(systemctl is-active iptables)" == "active" ]; then
		echo "iptables"
	else
		echo "none"
	fi
}

##
# Get which firewall is available on the local system,
# or "none" if none located
#
# CHANGELOG:
#   2025.04.10 - Switch from "systemctl list-unit-files" to "which" to support older systems
function get_available_firewall() {
	if which -s firewall-cmd; then
		echo "firewalld"
	elif which -s ufw; then
		echo "ufw"
	elif systemctl list-unit-files iptables.service &>/dev/null; then
		echo "iptables"
	else
		echo "none"
	fi
}
##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_debian() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'debian' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'ubuntu' ]]; then echo 1; return; fi
		if [ "$ID" == 'debian' ]; then echo 1; return; fi
		if [ "$ID" == 'ubuntu' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_ubuntu() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'ubuntu' ]]; then echo 1; return; fi
		if [ "$ID" == 'ubuntu' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_rhel() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'rhel' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'fedora' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'centos' ]]; then echo 1; return; fi
		if [ "$ID" == 'rhel' ]; then echo 1; return; fi
		if [ "$ID" == 'fedora' ]; then echo 1; return; fi
		if [ "$ID" == 'centos' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_suse() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'suse' ]]; then echo 1; return; fi
		if [ "$ID" == 'suse' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_arch() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'arch' ]]; then echo 1; return; fi
		if [ "$ID" == 'arch' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_bsd() {
	if [ "$(uname -s)" == 'FreeBSD' ]; then
		echo 1
	else
		echo 0
	fi
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_macos() {
	if [ "$(uname -s)" == 'Darwin' ]; then
		echo 1
	else
		echo 0
	fi
}

##
# Install a package with the system's package manager.
#
# Uses Redhat's yum, Debian's apt-get, and SuSE's zypper.
#
# Usage:
#
# ```syntax-shell
# package_install apache2 php7.0 mariadb-server
# ```
#
# @param $1..$N string
#        Package, (or packages), to install.  Accepts multiple packages at once.
#
#
# CHANGELOG:
#   2025.04.10 - Set Debian frontend to noninteractive
#
function package_install (){
	echo "package_install: Installing $*..."

	TYPE_BSD="$(os_like_bsd)"
	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_RHEL="$(os_like_rhel)"
	TYPE_ARCH="$(os_like_arch)"
	TYPE_SUSE="$(os_like_suse)"

	if [ "$TYPE_BSD" == 1 ]; then
		pkg install -y $*
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		DEBIAN_FRONTEND="noninteractive" apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install -y $*
	elif [ "$TYPE_RHEL" == 1 ]; then
		yum install -y $*
	elif [ "$TYPE_ARCH" == 1 ]; then
		pacman -Syu --noconfirm $*
	elif [ "$TYPE_SUSE" == 1 ]; then
		zypper install -y $*
	else
		echo 'package_install: Unsupported or unknown OS' >&2
		echo 'Please report this at https://github.com/cdp1337/ScriptsCollection/issues' >&2
		exit 1
	fi
}
##
# Add an "allow" rule to the firewall in the INPUT chain
#
# Arguments:
#   --port <port>       Port(s) to allow
#   --source <source>   Source IP to allow (default: any)
#   --zone <zone>       Zone to allow (default: public)
#   --tcp|--udp         Protocol to allow (default: tcp)
#   --proto <tcp|udp>   Protocol to allow (alternative method)
#   --comment <comment> (only UFW) Comment for the rule
#
# Specify multiple ports with `--port '#,#,#'` or a range `--port '#:#'`
#
# CHANGELOG:
#   2025.11.23 - Use return codes instead of exit to allow the caller to handle errors
#   2025.04.10 - Add "--proto" argument as alternative to "--tcp|--udp"
#
function firewall_allow() {
	# Defaults and argument processing
	local PORT=""
	local PROTO="tcp"
	local SOURCE="any"
	local FIREWALL=$(get_available_firewall)
	local ZONE="public"
	local COMMENT=""
	while [ $# -ge 1 ]; do
		case $1 in
			--port)
				shift
				PORT=$1
				;;
			--tcp|--udp)
				PROTO=${1:2}
				;;
			--proto)
				shift
				PROTO=$1
				;;
			--source|--from)
				shift
				SOURCE=$1
				;;
			--zone)
				shift
				ZONE=$1
				;;
			--comment)
				shift
				COMMENT=$1
				;;
			*)
				PORT=$1
				;;
		esac
		shift
	done

	if [ "$PORT" == "" -a "$ZONE" != "trusted" ]; then
		echo "firewall_allow: No port specified!" >&2
		return 2
	fi

	if [ "$PORT" != "" -a "$ZONE" == "trusted" ]; then
		echo "firewall_allow: Trusted zones do not use ports!" >&2
		return 2
	fi

	if [ "$ZONE" == "trusted" -a "$SOURCE" == "any" ]; then
		echo "firewall_allow: Trusted zones require a source!" >&2
		return 2
	fi

	if [ "$FIREWALL" == "ufw" ]; then
		if [ "$SOURCE" == "any" ]; then
			echo "firewall_allow/UFW: Allowing $PORT/$PROTO from any..."
			ufw allow proto $PROTO to any port $PORT comment "$COMMENT"
		elif [ "$ZONE" == "trusted" ]; then
			echo "firewall_allow/UFW: Allowing all connections from $SOURCE..."
			ufw allow from $SOURCE comment "$COMMENT"
		else
			echo "firewall_allow/UFW: Allowing $PORT/$PROTO from $SOURCE..."
			ufw allow from $SOURCE proto $PROTO to any port $PORT comment "$COMMENT"
		fi
		return 0
	elif [ "$FIREWALL" == "firewalld" ]; then
		if [ "$SOURCE" != "any" ]; then
			# Firewalld uses Zones to specify sources
			echo "firewall_allow/firewalld: Adding $SOURCE to $ZONE zone..."
			firewall-cmd --zone=$ZONE --add-source=$SOURCE --permanent
		fi

		if [ "$PORT" != "" ]; then
			echo "firewall_allow/firewalld: Allowing $PORT/$PROTO in $ZONE zone..."
			if [[ "$PORT" =~ ":" ]]; then
				# firewalld expects port ranges to be in the format of "#-#" vs "#:#"
				local DPORTS="${PORT/:/-}"
				firewall-cmd --zone=$ZONE --add-port=$DPORTS/$PROTO --permanent
			elif [[ "$PORT" =~ "," ]]; then
				# Firewalld cannot handle multiple ports all that well, so split them by the comma
				# and run the add command separately for each port
				local DPORTS="$(echo $PORT | sed 's:,: :g')"
				for P in $DPORTS; do
					firewall-cmd --zone=$ZONE --add-port=$P/$PROTO --permanent
				done
			else
				firewall-cmd --zone=$ZONE --add-port=$PORT/$PROTO --permanent
			fi
		fi

		firewall-cmd --reload
		return 0
	elif [ "$FIREWALL" == "iptables" ]; then
		echo "firewall_allow/iptables: WARNING - iptables is untested"
		# iptables doesn't natively support multiple ports, so we have to get creative
		if [[ "$PORT" =~ ":" ]]; then
			local DPORTS="-m multiport --dports $PORT"
		elif [[ "$PORT" =~ "," ]]; then
			local DPORTS="-m multiport --dports $PORT"
		else
			local DPORTS="--dport $PORT"
		fi

		if [ "$SOURCE" == "any" ]; then
			echo "firewall_allow/iptables: Allowing $PORT/$PROTO from any..."
			iptables -A INPUT -p $PROTO $DPORTS -j ACCEPT
		else
			echo "firewall_allow/iptables: Allowing $PORT/$PROTO from $SOURCE..."
			iptables -A INPUT -p $PROTO $DPORTS -s $SOURCE -j ACCEPT
		fi
		iptables-save > /etc/iptables/rules.v4
		return 0
	elif [ "$FIREWALL" == "none" ]; then
		echo "firewall_allow: No firewall detected" >&2
		return 1
	else
		echo "firewall_allow: Unsupported or unknown firewall" >&2
		echo 'Please report this at https://github.com/cdp1337/ScriptsCollection/issues' >&2
		return 1
	fi
}
##
# Simple download utility function
#
# Uses either cURL or wget based on which is available
#
# Downloads the file to a temp location initially, then moves it to the final destination
# upon a successful download to avoid partial files.
#
# Returns 0 on success, 1 on failure
#
# CHANGELOG:
#   2025.11.23 - Download to a temp location to verify download was successful
#              - use which -s for cleaner checks
#   2025.11.09 - Initial version
#
function download() {
	local SOURCE="$1"
	local DESTINATION="$2"
	local TMP=$(mktemp)

	if [ -z "$SOURCE" ] || [ -z "$DESTINATION" ]; then
		echo "download: Missing required parameters!" >&2
		return 1
	fi

	if which -s curl; then
		if curl -fsL "$SOURCE" -o "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: curl failed to download $SOURCE" >&2
			return 1
		fi
	elif which -s wget; then
		if wget -q "$SOURCE" -O "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: wget failed to download $SOURCE" >&2
			return 1
		fi
	else
		echo "download: Neither curl nor wget is installed, cannot download!" >&2
		return 1
	fi
}
##
# Determine if the current shell session is non-interactive.
#
# Checks NONINTERACTIVE, CI, DEBIAN_FRONTEND, TERM, and TTY status.
#
# Returns 0 (true) if non-interactive, 1 (false) if interactive.
#
# CHANGELOG:
#   2025.11.23 - Initial version
#
function is_noninteractive() {
	# explicit flags
	case "${NONINTERACTIVE:-}${CI:-}" in
		1*|true*|TRUE*|True*|*CI* ) return 0 ;;
	esac

	# debian frontend
	if [ "${DEBIAN_FRONTEND:-}" = "noninteractive" ]; then
		return 0
	fi

	# dumb terminal or no tty on stdin/stdout
	if [ "${TERM:-}" = "dumb" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
		return 0
	fi

	return 1
}

##
# Prompt user for a text response
#
# Arguments:
#   --default="..."   Default text to use if no response is given
#
# Returns:
#   text as entered by user
#
# CHANGELOG:
#   2025.11.23 - Use is_noninteractive to handle non-interactive mode
#   2025.01.01 - Initial version
#
function prompt_text() {
	local DEFAULT=""
	local PROMPT="Enter some text"
	local RESPONSE=""

	while [ $# -ge 1 ]; do
		case $1 in
			--default=*) DEFAULT="${1#*=}";;
			*) PROMPT="$1";;
		esac
		shift
	done

	echo "$PROMPT" >&2
	echo -n '> : ' >&2

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		echo $DEFAULT
		return
	fi

	read RESPONSE
	if [ "$RESPONSE" == "" ]; then
		echo "$DEFAULT"
	else
		echo "$RESPONSE"
	fi
}

##
# Prompt user for a yes or no response
#
# Arguments:
#   --invert            Invert the response (yes becomes 0, no becomes 1)
#   --default-yes       Default to yes if no response is given
#   --default-no        Default to no if no response is given
#   -q                  Quiet mode (no output text after response)
#
# Returns:
#   1 for yes, 0 for no (or inverted if --invert is set)
#
# CHANGELOG:
#   2025.11.23 - Use is_noninteractive to handle non-interactive mode
#   2025.11.09 - Add -q (quiet) option to suppress output after prompt (and use return value)
#   2025.01.01 - Initial version
#
function prompt_yn() {
	local TRUE=0 # Bash convention: 0 is success/true
	local YES=1
	local FALSE=1 # Bash convention: non-zero is failure/false
	local NO=0
	local DEFAULT="n"
	local DEFAULT_CODE=1
	local PROMPT="Yes or no?"
	local RESPONSE=""
	local QUIET=0

	while [ $# -ge 1 ]; do
		case $1 in
			--invert) YES=0; NO=1 TRUE=1; FALSE=0;;
			--default-yes) DEFAULT="y";;
			--default-no) DEFAULT="n";;
			-q) QUIET=1;;
			*) PROMPT="$1";;
		esac
		shift
	done

	echo "$PROMPT" >&2
	if [ "$DEFAULT" == "y" ]; then
		DEFAULT="$YES"
		DEFAULT_CODE=$TRUE
		echo -n "> (Y/n): " >&2
	else
		DEFAULT="$NO"
		DEFAULT_CODE=$FALSE
		echo -n "> (y/N): " >&2
	fi

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		if [ $QUIET -eq 0 ]; then
			echo $DEFAULT
		fi
		return $DEFAULT_CODE
	fi

	read RESPONSE
	case "$RESPONSE" in
		[yY]*)
			if [ $QUIET -eq 0 ]; then
				echo $YES
			fi
			return $TRUE;;
		[nN]*)
			if [ $QUIET -eq 0 ]; then
				echo $NO
			fi
			return $FALSE;;
		*)
			if [ $QUIET -eq 0 ]; then
				echo $DEFAULT
			fi
			return $DEFAULT_CODE;;
	esac
}
##
# Print a header message
#
# CHANGELOG:
#   2025.11.09 - Port from _common to bz_eval_tui
#   2024.12.25 - Initial version
#
function print_header() {
	local header="$1"
	echo "================================================================================"
	printf "%*s\n" $(((${#header}+80)/2)) "$header"
    echo ""
}
##
# Get the operating system version
#
# Just the major version number is returned
#
function os_version() {
	if [ "$(uname -s)" == 'FreeBSD' ]; then
		local _V="$(uname -K)"
		if [ ${#_V} -eq 6 ]; then
			echo "${_V:0:1}"
		elif [ ${#_V} -eq 7 ]; then
			echo "${_V:0:2}"
		fi

	elif [ -f '/etc/os-release' ]; then
		local VERS="$(egrep '^VERSION_ID=' /etc/os-release | sed 's:VERSION_ID=::')"

		if [[ "$VERS" =~ '"' ]]; then
			# Strip quotes around the OS name
			VERS="$(echo "$VERS" | sed 's:"::g')"
		fi

		if [[ "$VERS" =~ \. ]]; then
			# Remove the decimal point and everything after
			# Trims "24.04" down to "24"
			VERS="${VERS/\.*/}"
		fi

		if [[ "$VERS" =~ "v" ]]; then
			# Remove the "v" from the version
			# Trims "v24" down to "24"
			VERS="${VERS/v/}"
		fi

		echo "$VERS"

	else
		echo 0
	fi
}

##
# Install SteamCMD
function install_steamcmd() {
	echo "Installing SteamCMD..."

	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_UBUNTU="$(os_like_ubuntu)"
	OS_VERSION="$(os_version)"

	# Preliminary requirements
	if [ "$TYPE_UBUNTU" == 1 ]; then
		add-apt-repository -y multiverse
		dpkg --add-architecture i386
		apt update

		# By using this script, you agree to the Steam license agreement at https://store.steampowered.com/subscriber_agreement/
		# and the Steam privacy policy at https://store.steampowered.com/privacy_agreement/
		# Since this is meant to support unattended installs, we will forward your acceptance of their license.
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections

		apt install -y steamcmd
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		dpkg --add-architecture i386
		apt update

		if [ "$OS_VERSION" -le 12 ]; then
			apt install -y software-properties-common apt-transport-https dirmngr ca-certificates lib32gcc-s1

			# Enable "non-free" repos for Debian (for steamcmd)
			# https://stackoverflow.com/questions/76688863/apt-add-repository-doesnt-work-on-debian-12
			add-apt-repository -y -U http://deb.debian.org/debian -c non-free-firmware -c non-free
			if [ $? -ne 0 ]; then
				echo "Workaround failed to add non-free repos, trying new method instead"
				apt-add-repository -y non-free
			fi
		else
			# Debian Trixie and later
			if [ -e /etc/apt/sources.list ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list
				fi
			elif [ -e /etc/apt/sources.list.d/debian.sources ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list.d/debian.sources; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list.d/debian.sources
				fi
			else
				echo "Could not find a sources.list file to enable non-free repos" >&2
				exit 1
			fi
		fi

		# Install steam repo
		download http://repo.steampowered.com/steam/archive/stable/steam.gpg /usr/share/keyrings/steam.gpg
		echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] http://repo.steampowered.com/steam/ stable steam" > /etc/apt/sources.list.d/steam.list

		# By using this script, you agree to the Steam license agreement at https://store.steampowered.com/subscriber_agreement/
		# and the Steam privacy policy at https://store.steampowered.com/privacy_agreement/
		# Since this is meant to support unattended installs, we will forward your acceptance of their license.
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections

		# Install steam binary and steamcmd
		apt update
		apt install -y steamcmd
	else
		echo 'Unsupported or unknown OS' >&2
		exit 1
	fi
}

##
# Install UFW
#
function install_ufw() {
	if [ "$(os_like_rhel)" == 1 ]; then
		# RHEL/CentOS requires EPEL to be installed first
		package_install epel-release
	fi

	package_install ufw

	# Auto-enable a newly installed firewall
	ufw --force enable
	systemctl enable ufw
	systemctl start ufw

	# Auto-add the current user's remote IP to the whitelist (anti-lockout rule)
	local TTY_IP="$(who am i | awk '{print $NF}' | sed 's/[()]//g')"
	if [ -n "$TTY_IP" ]; then
		ufw allow from $TTY_IP comment 'Anti-lockout rule based on first install of UFW'
	fi
}

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
	package_install curl sudo default-jdk python3-venv

	java -version

	if [ "$FIREWALL" == "1" ]; then
		if [ "$(get_enabled_firewall)" == "none" ]; then
			# No firewall installed, go ahead and install UFW
			install_ufw
		fi
	fi

	[ -e "$GAME_DIR/AppFiles" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles"

	# EULA Agreement, (because Microsoft is fun like that)
	if ! prompt_yn -q --default-yes "By continuing you agree to the Minecraft EULA located at https://aka.ms/MinecraftEULA"; then
		echo "You must agree to the EULA to continue, exiting." >&2
		exit 1
	fi
	sudo -u $GAME_USER echo "eula=true" > "$GAME_DIR/AppFiles/eula.txt"

	if ! download "$GAME_SOURCE" "$GAME_DIR/AppFiles/minecraft_server.jar"; then
		echo "Could not install $GAME_DESC, exiting" >&2
		exit 1
	fi

	chown $GAME_USER:$GAME_USER "$GAME_DIR/AppFiles/minecraft_server.jar"

	# Install system service file to be loaded by systemd
    cat > /etc/systemd/system/${GAME_SERVICE}.service <<EOF
[Unit]
# DYNAMICALLY GENERATED FILE! Edit at your own risk
Description=$GAME_DESC
After=network.target

[Service]
Type=simple
LimitNOFILE=10000
User=$GAME_USER
Group=$GAME_USER
WorkingDirectory=$GAME_DIR/AppFiles
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $GAME_USER)
ExecStart=/usr/bin/java -Xmx1G -Xms1G -jar minecraft_server.jar nogui
ExecStop=$GAME_DIR/manage.py --pre-stop --service ${GAME_SERVICE}
ExecStartPost=$GAME_DIR/manage.py --post-start --service ${GAME_SERVICE}
Restart=on-failure
RestartSec=1800s
TimeoutStartSec=600s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    # systemctl enable $GAME_SERVICE

    # Ensure necessary directories exist
    #[ -d "$SAVE_DIR" ] || sudo -u $GAME_USER mkdir -p "$SAVE_DIR"

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
server:
  - name: Accepts Transfers
    key: accepts-transfers
    type: bool
    default: false
    help: "Whether to accept incoming transfers via a transfer packet."
  - name: Allow Flight
    key: allow-flight
    type: bool
    default: false
    help: "Whether to allow players to fly."
  - name: Broadcast Console to Ops
    key: broadcast-console-to-ops
    type: bool
    default: true
    help: "Whether to broadcast console messages to operators."
  - name: Broadcast RCON to Ops
    key: broadcast-rcon-to-ops
    type: bool
    default: true
    help: "Whether to broadcast RCON messages to operators."
  - name: Bug Report Link
    key: bug-report-link
    type: str
    default: ""
    help: "A link to your bug reporting platform, shown when players use the /bugreport command."
  - name: Difficulty
    key: difficulty
    type: str
    default: normal
    options:
      - peaceful
      - easy
      - normal
      - hard
    help: "Sets the game difficulty."
  - name: Enable Code of Conduct
    key: enable-code-of-conduct
    type: bool
    default: false
    help: "Whether to enable the code of conduct enforcement."
  - name: Enable JMX Monitoring
    key: enable-jmx-monitoring
    type: bool
    default: false
    help: "Whether to enable JMX monitoring for the server."
  - name: Enable Query
    key: enable-query
    type: bool
    default: false
    help: "Whether to enable the query protocol."
  - name: Enable RCON
    key: enable-rcon
    type: bool
    default: false
    help: "Whether to enable RCON (Remote Console) for server management."
  - name: Enable Status
    key: enable-status
    type: bool
    default: true
    help: "Whether to enable the server status query."
  - name: Enable Secure Profile
    key: enable-secure-profile
    type: bool
    default: true
    help: "Whether to enable secure profile handling."
  - name: Enable Whitelist
    key: enable-whitelist
    type: bool
    default: false
    help: "Whether to enable the server whitelist."
  - name: Enforce Whitelist on Login
    key: enforce-whitelist-on-login
    type: bool
    default: false
    help: "Whether to enforce the whitelist when players log in."
  - name: Entity Broadcast Range Percentage
    key: entity-broadcast-range-percentage
    type: int
    default: 100
    help: "Sets the percentage of the entity broadcast range."
  - name: Force Gamemode
    key: force-gamemode
    type: bool
    default: false
    help: "Whether to force players into the default gamemode upon joining."
  - name: Function Permission Level
    key: function-permission-level
    type: int
    default: 2
    help: "Sets the permission level required to use server functions."
  - name: Gamemode
    key: gamemode
    type: str
    default: survival
    options:
      - survival
      - creative
      - adventure
      - spectator
    help: "Sets the default gamemode for players."
  - name: Generate Structures
    key: generate-structures
    type: bool
    default: true
    help: "Whether to generate structures like villages and temples."
  - name: Generator Settings
    key: generator-settings
    type: str
    default: "{}"
    help: "Custom settings for world generation."
  - name: Hardcore
    key: hardcore
    type: bool
    default: false
    help: "Whether to enable hardcore mode."
  - name: Hide Online Players
    key: hide-online-players
    type: bool
    default: false
    help: "Whether to hide the number of online players from the server list."
  - name: Initial Disabled Packs
    key: initial-disabled-packs
    type: str
    default: ""
    help: "A comma-separated list of data packs to be disabled when the world is created."
  - name: Initial Enabled Packs
    key: initial-enabled-packs
    type: str
    default: "vanilla"
    help: "A comma-separated list of data packs to be enabled when the world is created."
  - name: Level Name
    key: level-name
    type: str
    default: world
    help: "The name of the world folder."
  - name: Level Seed
    key: level-seed
    type: str
    default: ""
    help: "The seed used to generate the world."
  - name: Level Type
    key: level-type
    type: str
    default: "minecraft:normal"
    options:
      - minecraft:normal
      - minecraft:flat
      - minecraft:large_biomes
      - minecraft:amplified
      - minecraft:single_biome_surface
    help: "The type of world to generate."
  - name: Log IPs
    key: log-ips
    type: bool
    default: true
    help: "Whether to log player IP addresses."
  - name: Management Server Enabled
    key: management-server-enabled
    type: bool
    default: false
    help: "Whether to enable the management server for remote administration."
  - name: Management Server Host
    key: management-server-host
    type: str
    default: "localhost"
    help: "The host address for the management server."
  - name: Management Server Port
    key: management-server-port
    type: int
    default: 0
    help: "The port number for the management server."
  - name: Management Server Secret
    key: management-server-secret
    type: str
    default: ""
    help: "The secret key for authenticating with the management server."
  - name: Management Server TLS Enabled
    key: management-server-tls-enabled
    type: bool
    default: true
    help: "Whether to enable TLS for the management server."
  - name: Management Server TLS Keystore
    key: management-server-tls-keystore
    type: str
    default: ""
    help: "The keystore file for TLS on the management server."
  - name: Management Server TLS Keystore Password
    key: management-server-tls-keystore-password
    type: str
    default: ""
    help: "The password for the TLS keystore on the management server."
  - name: Max Chained Neighbor Updates
    key: max-chained-neighbor-updates
    type: int
    default: 1000000
    help: "The maximum number of block updates that can be chained together."
  - name: Max Players
    key: max-players
    type: int
    default: 20
    help: "The maximum number of players allowed on the server."
  - name: Max Tick Time
    key: max-tick-time
    type: int
    default: 60000
    help: "The maximum time (in milliseconds) a single tick can take before the server is considered frozen."
  - name: Max World Size
    key: max-world-size
    type: int
    default: 29999984
    help: "The maximum size of the world in blocks."
  - name: MOTD
    key: motd
    type: str
    default: A Minecraft Server
    help: "The message of the day displayed in the server list."
  - name: Network Compression Threshold
    key: network-compression-threshold
    type: int
    default: 256
    help: "The threshold (in bytes) for network compression."
  - name: Online Mode
    key: online-mode
    type: bool
    default: true
    help: "Whether to enable online mode (authentication with Mojang servers)."
  - name: Op Permission Level
    key: op-permission-level
    type: int
    default: 4
    help: "Sets the permission level for server operators."
  - name: Pause When Empty Seconds
    key: pause-when-empty-seconds
    type: int
    default: 60
    help: "The number of seconds to wait before pausing the server when no players are online."
  - name: Player Idle Timeout
    key: player-idle-timeout
    type: int
    default: 0
    help: "The time (in minutes) before an idle player is kicked from the server. 0 disables this feature."
  - name: Prevent Proxy Connections
    key: prevent-proxy-connections
    type: bool
    default: false
    help: "Whether to prevent connections from known proxy servers."
  - name: Query Port
    key: query.port
    type: int
    default: 25565
    help: "The port number for the query protocol."
  - name: Rate Limit
    key: rate-limit
    type: int
    default: 0
    help: "The maximum number of packets per second a player can send. 0 disables rate limiting."
  - name: RCON Password
    key: rcon.password
    type: str
    default: ""
    help: "The password for RCON access."
  - name: RCON Port
    key: rcon.port
    type: int
    default: 25575
    help: "The port number for RCON access."
  - name: Region File Compression
    key: region-file-compression
    type: str
    default: deflate
    options:
      - none
      - zlib
      - deflate
    help: "The algorithm used for compressing chunks in regions."
  - name: Require Resource Pack
    key: require-resource-pack
    type: bool
    default: false
    help: "Whether to require players to use the server's resource pack."
  - name: Resource Pack
    key: resource-pack
    type: str
    default: ""
    help: "The URL of the resource pack to be used by players."
  - name: Resource Pack ID
    key: resource-pack-id
    type: str
    default: ""
    help: "An optional UUID for the resource pack set by resource-pack to identify the pack with clients. "
  - name: Resource Pack Prompt
    key: resource-pack-prompt
    type: str
    default: ""
    help: "The message shown to players when asking them to accept the resource pack."
  - name: Resource Pack SHA1
    key: resource-pack-sha1
    type: str
    default: ""
    help: "The SHA-1 hash of the resource pack file for integrity verification."
  - name: Server IP
    key: server-ip
    type: str
    default: ""
    help: "The IP address the server listens on."
  - name: Server Port
    key: server-port
    type: int
    default: 25565
    help: "The port number the server listens on."
  - name: Simulation Distance
    key: simulation-distance
    type: int
    default: 10
    help: "The distance (in chunks) that the server simulates around each player."
  - name: Spawn Protection
    key: spawn-protection
    type: int
    default: 16
    help: "The radius (in blocks) around the world spawn point that is protected from player modifications."
  - name: Status Heartbeat Interval
    key: status-heartbeat-interval
    type: int
    default: 5
    help: "The interval (in seconds) between status heartbeats."
  - name: Sync Chunk Writes
    key: sync-chunk-writes
    type: bool
    default: true
    help: "Whether to synchronize chunk writes to disk."
  - name: Text Filtering Config
    key: text-filtering-config
    type: str
    default: ""
    help: "The configuration for text filtering."
  - name: Text Filtering Version
    key: text-filtering-version
    type: int
    default: 0
    help: "The version of the text filtering configuration."
  - name: Use Native Transport
    key: use-native-transport
    type: bool
    default: true
    help: "Whether to use native transport libraries for better performance."
  - name: View Distance
    key: view-distance
    type: int
    default: 10
    help: "The distance (in chunks) that players can see."
  - name: Whitelist
    key: white-list
    type: bool
    default: false
    help: "Whether the whitelist is enabled."
manager:
  - name: Shutdown Warning 5 Minutes
    section: Messages
    key: shutdown_5min
    type: str
    default: Server is shutting down in 5 minutes
    help: "Custom message broadcasted to players 5 minutes before server shutdown."
  - name: Shutdown Warning 4 Minutes
    section: Messages
    key: shutdown_4min
    type: str
    default: Server is shutting down in 4 minutes
    help: "Custom message broadcasted to players 4 minutes before server shutdown."
  - name: Shutdown Warning 3 Minutes
    section: Messages
    key: shutdown_3min
    type: str
    default: Server is shutting down in 3 minutes
    help: "Custom message broadcasted to players 3 minutes before server shutdown."
  - name: Shutdown Warning 2 Minutes
    section: Messages
    key: shutdown_2min
    type: str
    default: Server is shutting down in 2 minutes
    help: "Custom message broadcasted to players 2 minutes before server shutdown."
  - name: Shutdown Warning 1 Minute
    section: Messages
    key: shutdown_1min
    type: str
    default: Server is shutting down in 1 minute
    help: "Custom message broadcasted to players 1 minute before server shutdown."
  - name: Shutdown Warning 30 Seconds
    section: Messages
    key: shutdown_30sec
    type: str
    default: Server is shutting down in 30 seconds!
    help: "Custom message broadcasted to players 30 seconds before server shutdown."
  - name: Shutdown Warning NOW
    section: Messages
    key: shutdown_now
    type: str
    default: Server is shutting down NOW!
    help: "Custom message broadcasted to players immediately before server shutdown."
  - name: Instance Started (Discord)
    section: Discord
    key: instance_started
    type: str
    default: "{instance} has started! :rocket:"
    help: "Custom message sent to Discord when the server starts, use '{instance}' to insert the map name"
  - name: Instance Stopping (Discord)
    section: Discord
    key: instance_stopping
    type: str
    default: ":small_red_triangle_down: {instance} is shutting down"
    help: "Custom message sent to Discord when the server stops, use '{instance}' to insert the map name"
  - name: Discord Enabled
    section: Discord
    key: enabled
    type: bool
    default: false
    help: "Enables or disables Discord integration for server status updates."
  - name: Discord Webhook URL
    section: Discord
    key: webhook
    type: str
    help: "The webhook URL for sending server status updates to a Discord channel."
EOF

	# If a pyenv is required:
	sudo -u $GAME_USER python3 -m venv "$GAME_DIR/.venv"
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install --upgrade pip
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install pyyaml
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install rcon
}

function postinstall() {
	print_header "Performing postinstall"

	# First run setup
	$GAME_DIR/manage.py --first-run
}

##
# Uninstall the game server
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
	if [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] ; then
		# Check for existing installation directory based on Warlock registration
		GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
		if [ "$GAME_DIR" != "$OVERRIDE_DIR" ]; then
			echo "ERROR: $GAME_DESC already installed in $GAME_DIR, cannot override to $OVERRIDE_DIR" >&2
			echo "If you want to move the installation, please uninstall first and then re-install to the new location." >&2
			exit 1
		fi
	fi

	GAME_DIR="$OVERRIDE_DIR"
	echo "Using ${GAME_DIR} as the installation directory based on explicit argument"
elif [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ]; then
	# Check for existing installation directory based on service file
	GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
	echo "Detected installation directory of ${GAME_DIR} based on service registration"
else
	echo "Using default installation directory of ${GAME_DIR}"
fi

if [ -e "/etc/systemd/system/${GAME_SERVICE}.service" ]; then
	EXISTING=1
else
	EXISTING=0
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
