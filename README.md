## Minecraft-Installer

An unofficial, open-source installer and management toolkit for deploying and maintaining Minecraft Java Edition servers on Linux. 
Supports multi-instance management, advanced configuration, and integrates with Warlock Manager for remote administration.

---

### Features

- Automated installation and uninstallation of Minecraft Java Edition servers
- Multi-instance support for running multiple servers
- Advanced configuration options (see `scripts/configs.yaml`)
- Firewall setup and management (UFW integration)
- Management console for server operations
- Remote administration via Warlock Manager
- Supports Debian 12, 13 and Ubuntu 24.04
- Customizable install directory and non-interactive/scripted installs

---

### Supported Platforms

- **Debian**: 12, 13
- **Ubuntu**: 24.04

---

### Installation

#### Quick Install

Run the installer script as root (or with sudo):

```bash
sudo bash src/installer.sh
```

#### Development Setup

To set up a development environment:

```bash
./setup-dev.sh
```

This will create a Python virtual environment and install dependencies.

---

### Usage

Installer options:

```
--uninstall         Perform an uninstallation
--dir=<str>         Use a custom installation directory (optional)
--skip-firewall     Do not install or configure a system firewall
--non-interactive   Run installer in non-interactive mode (for scripted installs)
--branch=<str>      Use a specific branch of the management script repository (default: main)
```

After installation, use the management console:

```bash
python3 /home/minecraft/manage.py <command>
```

---

### Configuration

Server options are defined in [`scripts/configs.yaml`](scripts/configs.yaml). Examples:

- Difficulty: peaceful, easy, normal, hard
- Enable RCON, Query, Secure Profile, Whitelist, etc.
- World settings: seed, type, name
- Management server options: enable, host, port, TLS

---

### Directory Structure

- `src/installer.sh`        Main installer script
- `src/manage.py`          Management console for server operations
- `scripts/configs.yaml`   Server configuration definitions
- `media/`                 Images/icons for Warlock integration
- `scriptlets/`            Common shell utilities and helpers
- `setup-dev.sh`           Development environment setup
- `compile.py`             Script compiler and documentation generator

---

### License

This project is licensed under the [AGPLv3](https://www.gnu.org/licenses/agpl-3.0.html).

---

### Author

Charlie Powell (<cdp1337@bitsnbytes.dev>)

---

### Contributing

Contributions are welcome! Please open issues or pull requests on GitHub.
