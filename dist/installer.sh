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
#   --dir=<str> - Use a custom installation directory instead of the default (optional)
#   --skip-firewall  - Do not install or configure a system firewall
#   --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
#   --branch=<str> - Use a specific branch of the management script repository DEFAULT=main
#
# Changelog:
#   20260318 - Migrated script to V2 of the API
#   20251103 - New installer

############################################
## Parameter Configuration
############################################

# Name of the game (used to create the directory)
INSTALLER_VERSION="v20260318"
GAME="Minecraft"
GAME_DESC="Minecraft Dedicated Server"
REPO="BitsNBytes25/Minecraft-Installer"
WARLOCK_GUID="700798f0-35be-bc6c-da84-62c510dfbd06"
GAME_USER="minecraft"
GAME_DIR="/home/${GAME_USER}"

function usage() {
  cat >&2 <<EOD
Usage: $0 [options]

Options:
    --uninstall  - Perform an uninstallation
    --dir=<str> - Use a custom installation directory instead of the default (optional)
    --skip-firewall  - Do not install or configure a system firewall
    --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
    --branch=<str> - Use a specific branch of the management script repository DEFAULT=main

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
BRANCH="main"
while [ "$#" -gt 0 ]; do
	case "$1" in
		--uninstall) MODE_UNINSTALL=1;;
		--dir=*|--dir)
			[ "$1" == "--dir" ] && shift 1 && OVERRIDE_DIR="$1" || OVERRIDE_DIR="${1#*=}"
			[ "${OVERRIDE_DIR:0:1}" == "'" ] && [ "${OVERRIDE_DIR:0-1}" == "'" ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			[ "${OVERRIDE_DIR:0:1}" == '"' ] && [ "${OVERRIDE_DIR:0-1}" == '"' ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			;;
		--skip-firewall) SKIP_FIREWALL=1;;
		--non-interactive) NONINTERACTIVE=1;;
		--branch=*|--branch)
			[ "$1" == "--branch" ] && shift 1 && BRANCH="$1" || BRANCH="${1#*=}"
			[ "${BRANCH:0:1}" == "'" ] && [ "${BRANCH:0-1}" == "'" ] && BRANCH="${BRANCH:1:-1}"
			[ "${BRANCH:0:1}" == '"' ] && [ "${BRANCH:0-1}" == '"' ] && BRANCH="${BRANCH:1:-1}"
			;;
		-h|--help) usage;;
		*) echo "Unknown argument: $1" >&2; usage;;
	esac
	shift 1
done

##
# Simple check to enforce the script to be run as root
if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi
##
# Simple wrapper to emulate `which -s`
#
# The -s flag is not available on all systems, so this function
# provides a consistent way to check for command existence
# without having to include '&>/dev/null' everywhere.
#
# Returns 0 on success, 1 on failure
#
# Arguments:
#   $1 - Command to check
#
# CHANGELOG:
#   2025.12.15 - Initial version (for a regression fix)
#
function cmd_exists() {
	local CMD="$1"
	which "$CMD" &>/dev/null
	return $?
}

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
#   2025.12.15 - Use cmd_exists to fix regression bug
#   2025.04.10 - Switch from "systemctl list-unit-files" to "which" to support older systems
function get_available_firewall() {
	if cmd_exists firewall-cmd; then
		echo "firewalld"
	elif cmd_exists ufw; then
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
# Returns 0 if true, 1 if false
#
# Usage:
#   if os_like debian; then ... ; fi
#
function os_like() {
	local OS="$1"

	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ "$OS" ]] || [ "$ID" == "$OS" ]; then
			return 0;
		fi
	fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_debian)" -eq 1 ]; then ... ; fi
#   if os_like_debian -q; then ... ; fi
#
function os_like_debian() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like debian || os_like ubuntu; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_ubuntu)" -eq 1 ]; then ... ; fi
#   if os_like_ubuntu -q; then ... ; fi
#
function os_like_ubuntu() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like ubuntu; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_rhel)" -eq 1 ]; then ... ; fi
#   if os_like_rhel -q; then ... ; fi
#
function os_like_rhel() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like rhel || os_like fedora || os_like rocky || os_like centos; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_suse)" -eq 1 ]; then ... ; fi
#   if os_like_suse -q; then ... ; fi
#
function os_like_suse() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like suse; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_arch)" -eq 1 ]; then ... ; fi
#   if os_like_arch -q; then ... ; fi
#
function os_like_arch() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like arch; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_bsd)" -eq 1 ]; then ... ; fi
#   if os_like_bsd -q; then ... ; fi
#
function os_like_bsd() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if [ "$(uname -s)" == 'FreeBSD' ]; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	else
		if [ $QUIET -eq 0 ]; then echo 0; fi
		return 1
	fi
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_macos)" -eq 1 ]; then ... ; fi
#   if os_like_macos -q; then ... ; fi
#
function os_like_macos() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if [ "$(uname -s)" == 'Darwin' ]; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	else
		if [ $QUIET -eq 0 ]; then echo 0; fi
		return 1
	fi
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
#   2026.01.09 - Cleanup os_like a bit and add support for RHEL 9's dnf
#   2025.04.10 - Set Debian frontend to noninteractive
#
function package_install (){
	echo "package_install: Installing $*..."

	if os_like_bsd -q; then
		pkg install -y $*
	elif os_like_debian -q; then
		DEBIAN_FRONTEND="noninteractive" apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install -y $*
	elif os_like_rhel -q; then
		if [ "$(os_version)" -ge 9 ]; then
			dnf install -y $*
		else
			yum install -y $*
		fi
	elif os_like_arch -q; then
		pacman -Syu --noconfirm $*
	elif os_like_suse -q; then
		zypper install -y $*
	else
		echo 'package_install: Unsupported or unknown OS' >&2
		echo 'Please report this at https://github.com/eVAL-Agency/ScriptsCollection/issues' >&2
		exit 1
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
# Arguments:
#   --no-overwrite       Skip download if destination file already exists
#
# CHANGELOG:
#   2025.12.15 - Use cmd_exists to fix regression bug
#   2025.12.04 - Add --no-overwrite option to allow skipping download if the destination file exists
#   2025.11.23 - Download to a temp location to verify download was successful
#              - use which -s for cleaner checks
#   2025.11.09 - Initial version
#
function download() {
	# Argument parsing
	local SOURCE="$1"
	local DESTINATION="$2"
	local OVERWRITE=1
	local TMP=$(mktemp)
	shift 2

	while [ $# -ge 1 ]; do
    		case $1 in
    			--no-overwrite)
    				OVERWRITE=0
    				;;
    		esac
    		shift
    	done

	if [ -z "$SOURCE" ] || [ -z "$DESTINATION" ]; then
		echo "download: Missing required parameters!" >&2
		return 1
	fi

	if [ -f "$DESTINATION" ] && [ $OVERWRITE -eq 0 ]; then
		echo "download: Destination file $DESTINATION already exists, skipping download." >&2
		return 0
	fi

	if cmd_exists curl; then
		if curl -fsL "$SOURCE" -o "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: curl failed to download $SOURCE" >&2
			return 1
		fi
	elif cmd_exists wget; then
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
# Checks NONINTERACTIVE, CI, DEBIAN_FRONTEND, and TERM.
#
# Returns 0 (true) if non-interactive, 1 (false) if interactive.
#
# CHANGELOG:
#   2025.12.16 - Remove TTY checks to avoid false positives in some environments
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

	# dumb terminal
	if [ "${TERM:-}" = "dumb" ]; then
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
#   2025.12.16 - Add text output for non-interactive and empty responses
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
		DEFAULT_TEXT="yes"
		DEFAULT="$YES"
		DEFAULT_CODE=$TRUE
		echo -n "> (Y/n): " >&2
	else
		DEFAULT_TEXT="no"
		DEFAULT="$NO"
		DEFAULT_CODE=$FALSE
		echo -n "> (y/N): " >&2
	fi

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		echo "$DEFAULT_TEXT (default non-interactive)" >&2
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
		"")
			echo "$DEFAULT_TEXT (default choice)" >&2
			if [ $QUIET -eq 0 ]; then
				echo $DEFAULT
			fi
			return $DEFAULT_CODE;;
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
##
# Install the management script from the project's repo
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#
# @param $1 Application Repo Name (e.g., user/repo)
# @param $2 Application Branch Name (default: main)
# @param $3 Warlock Manager Branch to use (default: release-v2)
#
# CHANGELOG:
#   20260325 - Update to install warlock-manager from PyPI if a version number is specified instead of a branch name
#   20260319 - Add third option to specify the version of Warlock Manager to use as the base
#   20260301 - Update to install warlock-manager from github (along with its dependencies) as a pip package
#
function install_warlock_manager() {
	print_header "Performing install_management"

	# Install management console and its dependencies

	# Source URL to download the application from
	local SRC=""
	# Github repository of the source application
	local REPO="$1"
	# Branch of the source application to download from (default: main)
	local BRANCH="${2:-main}"
	# Branch of Warlock Manager to install (default: release-v2)
	local MANAGER_BRANCH="${3:-release-v2}"
	local MANAGER_SOURCE

	if [[ "$MANAGER_BRANCH" =~ ^[0-9]+\.[0-9]+$ ]]; then
        MANAGER_SOURCE="pip"
        MANAGER_BRANCH=">=${MANAGER_BRANCH}.0,<=${MANAGER_BRANCH}.9999"
    else
        MANAGER_SOURCE="github"
    fi

	SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/dist/manage.py"

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
    group: Advanced
  - name: Allow Flight
    key: allow-flight
    type: bool
    default: false
    help: "Whether to allow players to fly."
    group: Basic
  - name: Broadcast Console to Ops
    key: broadcast-console-to-ops
    type: bool
    default: true
    help: "Whether to broadcast console messages to operators."
    group: Management
  - name: Broadcast RCON to Ops
    key: broadcast-rcon-to-ops
    type: bool
    default: true
    help: "Whether to broadcast RCON messages to operators."
    group: Management
  - name: Bug Report Link
    key: bug-report-link
    type: str
    default: ""
    help: "A link to your bug reporting platform, shown when players use the /bugreport command."
    group: Management
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
    group: Basic
  - name: Enable Code of Conduct
    key: enable-code-of-conduct
    type: bool
    default: false
    help: "Whether to enable the code of conduct enforcement."
    group: Security
  - name: Enable JMX Monitoring
    key: enable-jmx-monitoring
    type: bool
    default: false
    help: "Whether to enable JMX monitoring for the server."
    group: Advanced
  - name: Enable Query
    key: enable-query
    type: bool
    default: false
    help: "Whether to enable the query protocol."
    group: Network
  - name: Enable RCON
    key: enable-rcon
    type: bool
    default: false
    help: "Whether to enable RCON (Remote Console) for server management."
    group: Management
  - name: Enable Status
    key: enable-status
    type: bool
    default: true
    help: "Whether to enable the server status query."
    group: Network
  - name: Enable Secure Profile
    key: enable-secure-profile
    type: bool
    default: true
    help: "Whether to enable secure profile handling."
    group: Security
  - name: Enable Whitelist
    key: enable-whitelist
    type: bool
    default: false
    help: "Whether to enable the server whitelist."
    group: Basic
  - name: Enforce Whitelist on Login
    key: enforce-whitelist-on-login
    type: bool
    default: false
    help: "Whether to enforce the whitelist when players log in."
    group: Security
  - name: Entity Broadcast Range Percentage
    key: entity-broadcast-range-percentage
    type: int
    default: 100
    help: "Sets the percentage of the entity broadcast range."
    group: Advanced
  - name: Force Gamemode
    key: force-gamemode
    type: bool
    default: false
    help: "Whether to force players into the default gamemode upon joining."
    group: Basic
  - name: Function Permission Level
    key: function-permission-level
    type: int
    default: 2
    help: "Sets the permission level required to use server functions."
    group: Management
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
    group: Basic
  - name: Generate Structures
    key: generate-structures
    type: bool
    default: true
    help: "Whether to generate structures like villages and temples."
    group: World
  - name: Generator Settings
    key: generator-settings
    type: str
    default: "{}"
    help: "Custom settings for world generation."
    group: World
  - name: Hardcore
    key: hardcore
    type: bool
    default: false
    help: "Whether to enable hardcore mode."
    group: Basic
  - name: Hide Online Players
    key: hide-online-players
    type: bool
    default: false
    help: "Whether to hide the number of online players from the server list."
    group: Security
  - name: Initial Disabled Packs
    key: initial-disabled-packs
    type: str
    default: ""
    help: "A comma-separated list of data packs to be disabled when the world is created."
    group: World
  - name: Initial Enabled Packs
    key: initial-enabled-packs
    type: str
    default: "vanilla"
    help: "A comma-separated list of data packs to be enabled when the world is created."
    group: World
  - name: Level Name
    key: level-name
    type: str
    default: world
    help: "The name of the world folder."
    group: Basic
  - name: Level Seed
    key: level-seed
    type: str
    default: ""
    help: "The seed used to generate the world."
    group: Basic
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
    group: World
  - name: Log IPs
    key: log-ips
    type: bool
    default: true
    help: "Whether to log player IP addresses."
    group: Security
  - name: Management Server Enabled
    key: management-server-enabled
    type: bool
    default: false
    help: "Whether to enable the management server for remote administration."
    group: Management
  - name: Management Server Host
    key: management-server-host
    type: str
    default: "localhost"
    help: "The host address for the management server."
    group: Management
  - name: Management Server Port
    key: management-server-port
    type: int
    default: 0
    help: "The port number for the management server."
    group: Management
  - name: Management Server Secret
    key: management-server-secret
    type: str
    default: ""
    help: "The secret key for authenticating with the management server."
    group: Security
  - name: Management Server TLS Enabled
    key: management-server-tls-enabled
    type: bool
    default: true
    help: "Whether to enable TLS for the management server."
    group: Security
  - name: Management Server TLS Keystore
    key: management-server-tls-keystore
    type: str
    default: ""
    help: "The keystore file for TLS on the management server."
    group: Security
  - name: Management Server TLS Keystore Password
    key: management-server-tls-keystore-password
    type: str
    default: ""
    help: "The password for the TLS keystore on the management server."
    group: Security
  - name: Max Chained Neighbor Updates
    key: max-chained-neighbor-updates
    type: int
    default: 1000000
    help: "The maximum number of block updates that can be chained together."
    group: Advanced
  - name: Max Players
    key: max-players
    type: int
    default: 20
    help: "The maximum number of players allowed on the server."
    group: Basic
  - name: Max Tick Time
    key: max-tick-time
    type: int
    default: 60000
    help: "The maximum time (in milliseconds) a single tick can take before the server is considered frozen."
    group: Advanced
  - name: Max World Size
    key: max-world-size
    type: int
    default: 29999984
    help: "The maximum size of the world in blocks."
    group: World
  - name: MOTD
    key: motd
    type: str
    default: A Minecraft Server
    help: "The message of the day displayed in the server list."
    group: Basic
  - name: Network Compression Threshold
    key: network-compression-threshold
    type: int
    default: 256
    help: "The threshold (in bytes) for network compression."
    group: Network
  - name: Online Mode
    key: online-mode
    type: bool
    default: true
    help: "Whether to enable online mode (authentication with Mojang servers)."
    group: Security
  - name: Op Permission Level
    key: op-permission-level
    type: int
    default: 4
    help: "Sets the permission level for server operators."
    group: Management
  - name: Pause When Empty Seconds
    key: pause-when-empty-seconds
    type: int
    default: 60
    help: "The number of seconds to wait before pausing the server when no players are online."
    group: Advanced
  - name: Player Idle Timeout
    key: player-idle-timeout
    type: int
    default: 0
    help: "The time (in minutes) before an idle player is kicked from the server. 0 disables this feature."
    group: Basic
  - name: Prevent Proxy Connections
    key: prevent-proxy-connections
    type: bool
    default: false
    help: "Whether to prevent connections from known proxy servers."
    group: Security
  - name: Query Port
    key: query.port
    type: int
    default: 25565
    help: "The port number for the query protocol."
    group: Network
  - name: Rate Limit
    key: rate-limit
    type: int
    default: 0
    help: "The maximum number of packets per second a player can send. 0 disables rate limiting."
    group: Network
  - name: RCON Password
    key: rcon.password
    type: str
    default: ""
    help: "The password for RCON access."
    group: Management
  - name: RCON Port
    key: rcon.port
    type: int
    default: 25575
    help: "The port number for RCON access."
    group: Management
  - name: Region File Compression
    key: region-file-compression
    type: str
    default: deflate
    options:
      - none
      - zlib
      - deflate
    help: "The algorithm used for compressing chunks in regions."
    group: Advanced
  - name: Require Resource Pack
    key: require-resource-pack
    type: bool
    default: false
    help: "Whether to require players to use the server's resource pack."
    group: Resource Pack
  - name: Resource Pack
    key: resource-pack
    type: str
    default: ""
    help: "The URL of the resource pack to be used by players."
    group: Resource Pack
  - name: Resource Pack ID
    key: resource-pack-id
    type: str
    default: ""
    help: "An optional UUID for the resource pack set by resource-pack to identify the pack with clients. "
    group: Resource Pack
  - name: Resource Pack Prompt
    key: resource-pack-prompt
    type: str
    default: ""
    help: "The message shown to players when asking them to accept the resource pack."
    group: Resource Pack
  - name: Resource Pack SHA1
    key: resource-pack-sha1
    type: str
    default: ""
    help: "The SHA-1 hash of the resource pack file for integrity verification."
    group: Resource Pack
  - name: Server IP
    key: server-ip
    type: str
    default: ""
    help: "The IP address the server listens on."
    group: Network
  - name: Server Port
    key: server-port
    type: int
    default: 25565
    help: "The port number the server listens on."
    group: Basic
  - name: Simulation Distance
    key: simulation-distance
    type: int
    default: 10
    help: "The distance (in chunks) that the server simulates around each player."
    group: World
  - name: Spawn Protection
    key: spawn-protection
    type: int
    default: 16
    help: "The radius (in blocks) around the world spawn point that is protected from player modifications."
    group: World
  - name: Status Heartbeat Interval
    key: status-heartbeat-interval
    type: int
    default: 5
    help: "The interval (in seconds) between status heartbeats."
    group: Advanced
  - name: Sync Chunk Writes
    key: sync-chunk-writes
    type: bool
    default: true
    help: "Whether to synchronize chunk writes to disk."
    group: Advanced
  - name: Text Filtering Config
    key: text-filtering-config
    type: str
    default: ""
    help: "The configuration for text filtering."
    group: Filtering
  - name: Text Filtering Version
    key: text-filtering-version
    type: int
    default: 0
    help: "The version of the text filtering configuration."
    group: Filtering
  - name: Use Native Transport
    key: use-native-transport
    type: bool
    default: true
    help: "Whether to use native transport libraries for better performance."
    group: Advanced
  - name: View Distance
    key: view-distance
    type: int
    default: 10
    help: "The distance (in chunks) that players can see."
    group: Basic
  - name: Whitelist
    key: white-list
    type: bool
    default: false
    help: "Whether the whitelist is enabled."
    group: Basic
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
service:
  - name: Service Java Path
    section: System
    key: java-path
    type: str
    default: /usr/bin/java
    help: "The path to the Java executable used to run the Minecraft server."
    group: Settings
  - name: Service Game Version
    section: System
    key: game-version
    type: str
    default: latest
    help: "The version of Minecraft to run on the server."
    group: Settings
  - name: Service Fabric Mod Loader
    section: System
    key: fabric-mod-version
    type: str
    default: none
    help: "If you want to use the Fabric mod loader, specify the version here."
    group: Settings
EOF
	chown $GAME_USER:$GAME_USER "$GAME_DIR/configs.yaml"

	# Most games use .settings.ini for manager settings
	touch "$GAME_DIR/.settings.ini"
	chown $GAME_USER:$GAME_USER "$GAME_DIR/.settings.ini"

	# A python virtual environment is now required by Warlock-based managers.
	sudo -u $GAME_USER python3 -m venv "$GAME_DIR/.venv"
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install --upgrade pip
	if [ "$MANAGER_SOURCE" == "pip" ]; then
		# Install from PyPI with version specifier
		sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install "warlock-manager${MANAGER_BRANCH}"
	else
		# Install directly from GitHub
		sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install warlock-manager@git+https://github.com/BitsNBytes25/Warlock-Manager.git@$MANAGER_BRANCH
	fi
}


##
# Install OpenJDK from Eclipse Adoptium
#
# https://github.com/adoptium
#
# @arg $1 string OpenJDK version to install
#
# Will print the directory where OpenJDK was installed.
#
# CHANGELOG:
#   2026.04.13 - Mute curl output
#   2026.03.07 - Bugfix to fix 'path-jre//bin/java'
#   2026.03.05 - Add support for update-alternatives / alternatives.
#   2026.03.03 - Bugfix, return the correct JDK directory.
#   2026.01.13 - Initial version
#
function install_openjdk() {
	local VERSION="${1:-25}"

	# Validate version input
	if ! echo "$VERSION" | grep -E -q '^(8|11|16|17|18|19|20|21|22|23|24|25|26|27)$'; then
		echo "install_openjdk: Invalid OpenJDK version specified: $VERSION" >&2
		echo "Supported versions are: 8, 11, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27" >&2
		return 1
	fi

	if ! cmd_exists curl; then
		package_install curl
	fi

	# We will use this directory as a working directory for source files that need downloaded.
	[ -d /opt/script-collection ] || mkdir -p /opt/script-collection

	local DOWNLOAD_URL="$(curl -s https://api.github.com/repos/adoptium/temurin${VERSION}-binaries/releases/latest \
	  | grep browser_download_url \
	  | grep jre_x64_linux \
	  | grep 'tar\.gz"' \
	  | cut -d : -f 2,3 \
	  | tr -d \"\
	  | sed 's:\s*::')"

	local JDK_TGZ="$(basename "$DOWNLOAD_URL")"

	if ! download "$DOWNLOAD_URL" "/opt/script-collection/$JDK_TGZ" --no-overwrite; then
		echo "install_openjdk: Cannot download OpenJDK from ${DOWNLOAD_URL}!" >&2
		return 1
	fi

	local JDK_DIR="$(tar -zf "/opt/script-collection/$JDK_TGZ" --list | head -1)"
	# Remove any trailing '/'
	JDK_DIR="${JDK_DIR%/}"

	if [ ! -e "/opt/script-collection/$JDK_DIR" ]; then
		tar -x -C /opt/script-collection/ -f "/opt/script-collection/$JDK_TGZ"
	fi

	# Update distro registrations for alternative software.
	if os_like debian; then
		update-alternatives --install "/usr/bin/java" "java" "/opt/script-collection/$JDK_DIR/bin/java" 1
	elif os_like rhel; then
		alternatives --install "/usr/bin/java" "java" "/opt/script-collection/$JDK_DIR/bin/java" 1
	elif os_like suse; then
		update-alternatives --install "/usr/bin/java" "java" "/opt/script-collection/$JDK_DIR/bin/java" 1
	fi

	echo "/opt/script-collection/$JDK_DIR"
}


print_header "$GAME_DESC *unofficial* Installer ${INSTALLER_VERSION}"

############################################
## Installer Actions
############################################

##
# Perform any steps necessary for upgrading an existing installation.
#
function upgrade_application() {
	print_header "Existing installation detected, performing upgrade"

	if [ -e "$GAME_DIR/AppFiles/eula.txt" ]; then
		print_header 'Upgrading to multi-instance support'
		sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles/minecraft-server"
		sudo -u $GAME_USER mv $GAME_DIR/AppFiles/* $GAME_DIR/AppFiles/minecraft-server/
		mkdir $GAME_DIR/Environments
		egrep '^Environment' /etc/systemd/system/minecraft-server.service | sed 's:^Environment=::g' > $GAME_DIR/Environments/minecraft-server.env
		chown -R $GAME_USER:$GAME_USER "$GAME_DIR/Environments"
		sed -i "s:WorkingDirectory=.*:WorkingDirectory=$GAME_DIR/AppFiles/minecraft-server:" /etc/systemd/system/minecraft-server.service
	fi
}

##
# Install the VEIN game server using Steam
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#   STEAM_ID     - Steam App ID of the game
#   GAME_DESC    - Description of the game (for logging purposes)
#   SAVE_DIR     - Directory to store game save files
#
function install_application() {
	print_header "Performing install_application"

	# Create the game user account
	# This will create the account with no password, so if you need to log in with this user,
	# run `sudo passwd $GAME_USER` to set a password.
	if [ -z "$(getent passwd $GAME_USER)" ]; then
		useradd -m -U $GAME_USER
	fi

	if [ ! -d "/home/${GAME_USER}" ]; then
		mkdir -p "/home/${GAME_USER}"
		chown $GAME_USER:$GAME_USER "/home/${GAME_USER}"
	fi

	# Preliminary requirements
	package_install curl sudo python3-venv

	# Install the various versions of Java required by Minecraft.
	# required because the user may change the version of Minecraft they want to run.
	# Minecraft Version | Java Version
	# 1.7.10 - 1.11.2   | Java 8
	# 1.12.0 - 1.16.5   | Java 11
	# 1.17 - 1.20.4     | Java 17
	# 1.20.5 +          | Java 21

	install_openjdk 8
	install_openjdk 11
	install_openjdk 17
	install_openjdk 21

	if [ "$FIREWALL" == "1" ]; then
		if [ "$(get_enabled_firewall)" == "none" ]; then
			# No firewall installed, go ahead and install UFW
			install_ufw
		fi
	fi

	[ -e "$GAME_DIR/AppFiles" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles"
	[ -e "$GAME_DIR/Environments" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/Environments"

	# EULA Agreement, (because Microsoft is fun like that)
	if ! prompt_yn -q --default-yes "By continuing you agree to the Minecraft EULA located at https://aka.ms/MinecraftEULA"; then
		echo "You must agree to the EULA to continue, exiting." >&2
		exit 1
	fi

	# Install the management script
	install_warlock_manager "$REPO" "$BRANCH" "2.1"

	# Install installer (this script) for uninstallation or manual work
	download "https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/dist/installer.sh" "$GAME_DIR/installer.sh"
	chmod +x "$GAME_DIR/installer.sh"
	chown $GAME_USER:$GAME_USER "$GAME_DIR/installer.sh"

	if [ -n "$WARLOCK_GUID" ]; then
		# Register Warlock
		[ -d "/var/lib/warlock" ] || mkdir -p "/var/lib/warlock"
		echo -n "$GAME_DIR" > "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

function postinstall() {
	print_header "Performing postinstall"

	# First run setup
	$GAME_DIR/manage.py first-run
}

##
# Uninstall the game server
#
# Expects the following variables:
#   GAME_DIR     - Directory where the game is installed
#   SAVE_DIR     - Directory where game save files are stored
#
function uninstall_application() {
	print_header "Performing uninstall_application"

	$GAME_DIR/manage.py remove --confirm

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


if [ -e "$GAME_DIR/Environments" ]; then
	# Check for existing service files to determine if the service is running.
	# This is important to prevent conflicts with the installer trying to modify files while the service is running.
	for envfile in "$GAME_DIR/Environments/"*.env; do
		SERVICE="$(basename "$envfile" .env)"
		if [ "$SERVICE" != "*" ]; then
			if systemctl -q is-active $SERVICE; then
				echo "$GAME_DESC service is currently running, please stop all instances before running this installer."
				echo "You can do this with: sudo systemctl stop $SERVICE"
				exit 1
			fi
		fi
	done
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

if [ -e "$GAME_DIR/AppFiles" ]; then
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

	if [ $EXISTING -eq 1 ]; then
		upgrade_application
	fi

	install_application

	postinstall

	# Print some instructions and useful tips
    print_header "$GAME_DESC Installation Complete"
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
		$GAME_DIR/manage.py backup
	fi

	uninstall_application
fi
