#!/usr/bin/env python3
import sys
import os
import random
import string

# import:org_python/venv_path_include.py
from warlock_manager.apps.manual_app import ManualApp
from warlock_manager.config.ini_config import INIConfig
from warlock_manager.config.properties_config import PropertiesConfig
from warlock_manager.libs.app_runner import app_runner
from warlock_manager.libs.firewall import Firewall
from warlock_manager.libs.java import find_java_version
from warlock_manager.libs.tui import print_header
from warlock_manager.services.rcon_service import RCONService
from warlock_manager.libs.version import is_version_older, is_version_compatible

here = os.path.dirname(os.path.realpath(__file__))


class GameApp(ManualApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'Minecraft'
		self.service_prefix = 'minecraft-'
		self.desc = 'Minecraft Java Edition'
		self.services = self.detect_services()
		self.service_handler = GameService
		self.multi_binary = True
		self._latest_version = None

		self.configs = {
			'manager': INIConfig('manager', os.path.join(here, '.settings.ini'))
		}
		self.load()

	def check_update_available(self) -> bool:
		"""
		Check if an update is available for this game

		:return:
		"""
		for svc in self.get_services():
			if svc.check_update_available():
				return True
		return False

	def update(self):
		"""
		Update the game server to the latest version

		:return:
		"""
		print_header('Updating all Minecraft Services')
		for svc in self.get_services():
			svc.update()

	def get_save_files(self) -> list | None:
		"""
		Get a list of save files / directories for the game server

		:return:
		"""
		files = ['banned-ips.json', 'banned-players.json', 'ops.json', 'whitelist.json', 'plugins']
		for service in self.get_services():
			files.append(service.get_name())
			files.append(service.get_name() + '_nether')
			files.append(service.get_name() + '_the_end')
		return files

	def get_save_directory(self) -> str | None:
		"""
		Get the save directory for the game server

		:return:
		"""
		return os.path.join(here, 'AppFiles')

	def first_run(self) -> bool:
		"""
		Perform first-run configuration for setting up the game server initially

		:param game:
		:return:
		"""
		print_header('First Run Configuration')

		if os.geteuid() != 0:
			print('ERROR: Please run this script with sudo to perform first-run configuration.')
			return False

		services = self.get_services()
		if len(services) == 0:
			# No services detected, create one.
			self.create_service('server')
		return True

	def get_latest_version(self) -> str | None:
		"""
		Get the latest released version available for the game server

		Pulls the data live from Mojang's version manifest, which is updated with every release.
		:return:
		"""
		if self._latest_version is not None:
			return self._latest_version

		src_manifest = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
		dat = self.download_json(src_manifest)
		if 'latest' in dat and 'release' in dat['latest']:
			self._latest_version = dat['latest']['release']
			return self._latest_version

		return None

	def get_versions_available(self) -> list:
		"""
		Get a list of all released versions available for the game server

		Pulls the data live from Mojang's version manifest, which is updated with every release.
		:return:
		"""
		src_manifest = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
		dat = self.download_json(src_manifest)
		versions = ['latest']
		for version in dat['versions']:
			if version['type'] == 'release':
				versions.append(version['id'])
		return versions

	def get_download_url(self, version: str) -> str | None:
		"""
		Get the download URL for the server for a specific version.

		Pulls live data from the Mojang version manifest.
		:return:
		"""
		src_manifest = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
		meta_url = None
		dat = self.download_json(src_manifest)
		for version in dat['versions']:
			if version['id'] == version:
				meta_url = version['url']
				break

		if meta_url is None:
			print('Version %s not found in version manifest.' % version, file=sys.stderr)
			return None

		# Now that the meta_url for the package is ready, grab that which will contain the download URL for the server
		dat = self.download_json(meta_url)
		if 'downloads' in dat and 'server' in dat['downloads'] and 'url' in dat['downloads']['server']:
			return dat['downloads']['server']['url']

		print('Version %s did not appear to have a server download URL.' % version, file=sys.stderr)
		return None


class GameService(RCONService):
	"""
	Service definition and handler
	"""
	def __init__(self, service: str, game: GameApp):
		"""
		Initialize and load the service definition
		:param file:
		"""
		super().__init__(service, game)
		self.service = service
		self.game = game
		self.configs = {
			'server': PropertiesConfig('server', os.path.join(self.get_app_directory(), 'server.properties')),
			'service': INIConfig('service', os.path.join(self.get_app_directory(), '.service.ini'))
		}
		self.load()

	def option_value_updated(self, option: str, previous_value, new_value):
		"""
		Handle any special actions needed when an option value is updated
		:param option:
		:param previous_value:
		:param new_value:
		:return:
		"""

		# Special option actions
		if option == 'Server Port':
			# Update firewall for game port change
			if previous_value:
				Firewall.remove(int(previous_value), 'tcp')
			Firewall.allow(int(new_value), 'tcp', 'Allow %s game port' % self.game.desc)
		elif option == 'Query Port':
			# Update firewall for game port change
			if previous_value:
				Firewall.remove(int(previous_value), 'udp')
			Firewall.allow(int(new_value), 'udp', 'Allow %s query port' % self.game.desc)
		elif option == 'Service Game Version':
			# If the game version is updated, we should also update the server to match that version
			# and change the Java runtime to match the appropriate version for that game version.
			try:
				self.assign_java_path()
			except OSError as e:
				print('WARNING: Failed to find Java installation for game version %s: %s' % (new_value, str(e)), file=sys.stderr)
			self.update()
		elif option == 'Service Java Path':
			# If the Java path is updated, generate a new systemd service file.
			self.build_systemd_config()
			self.reload()

	def is_api_enabled(self) -> bool:
		"""
		Check if API is enabled for this service
		:return:
		"""
		return (
			self.get_option_value('Enable RCON') and
			self.get_option_value('RCON Port') != '' and
			self.get_option_value('RCON Password') != ''
		)

	def get_api_port(self) -> int:
		"""
		Get the API port from the service configuration
		:return:
		"""
		return self.get_option_value('RCON Port')

	def get_api_password(self) -> str:
		"""
		Get the API password from the service configuration
		:return:
		"""
		return self.get_option_value('RCON Password')

	def get_player_count(self) -> int | None:
		"""
		Get the current player count on the server, or None if the API is unavailable
		:return:
		"""
		try:
			ret = self.cmd('/list')
			# ret should contain 'There are N of a max...' where N is the player count.
			if ret is None:
				return None
			elif 'There are ' in ret:
				return int(ret[10:ret.index(' of a max')].strip())
			else:
				return None
		except:
			return None

	def get_player_max(self) -> int:
		"""
		Get the maximum player count allowed on the server
		:return:
		"""
		return self.get_option_value('Max Players')

	def get_name(self) -> str:
		"""
		Get the name of this game server instance
		:return:
		"""
		return self.get_option_value('Level Name')

	def get_port(self) -> int | None:
		"""
		Get the primary port of the service, or None if not applicable
		:return:
		"""
		return self.get_option_value('Server Port')

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""

		# This service does not have a helper wrapper, so it's the same as the process PID
		return self.get_pid()

	def send_message(self, message: str):
		"""
		Send a message to all players via the game API
		:param message:
		:return:
		"""
		self.cmd('/say %s' % message)

	def save_world(self):
		"""
		Force the game server to save the world via the game API
		:return:
		"""
		self.cmd('save-all flush')

	def get_port_definitions(self) -> list:
		"""
		Get a list of port definitions for this service
		:return:
		"""
		return [
			('Query Port', 'udp', '%s query port' % self.game.desc),
			('Server Port', 'tcp', '%s game port' % self.game.desc),
			('RCON Port', 'tcp', '%s RCON port' % self.game.desc)
		]

	def get_commands(self) -> None | list[str]:
		"""
		Get a list of custom command strings to display in the UI for this service, or None for no custom commands
		:return:
		"""
		cmds = self.cmd('/help')
		if cmds is None:
			print('Failed to retrieve command list from server.', file=sys.stderr)
			return None

		# Minecraft jumbles all the commands on a single line, (for whatever reason...)
		commands = []
		for cmd in cmds.split('/'):
			commands.append('/' + cmd)

		return commands

	def get_executable(self) -> str:
		"""
		Get the full executable for this game service
		:return:
		"""
		return '%s -Xmx1G -Xms1G -jar minecraft_server.jar nogui' % self.get_option_value('Service Java Path')

	def get_target_version(self) -> str:
		"""
		Get the target version of the game server

		This is the version of the game server that _should_ be installed (or will be installed).
		:return:
		"""
		target_version = self.get_option_value('Service Game Version')
		if target_version == 'latest':
			target_version = self.game.get_latest_version()

		return target_version

	def assign_java_path(self):
		"""
		Assign the appropriate Java version for the currently selected game version and set the Java path option accordingly.
		:return:
		"""
		target_version = self.get_target_version()

		if is_version_older(target_version, '1.12.0'):
			java_version = 8
		elif is_version_compatible(target_version, '1.12.0', '1.16.5'):
			java_version = 11
		elif is_version_compatible(target_version, '1.17.0', '1.20.4'):
			java_version = 17
		else:
			java_version = 21

		java_path = find_java_version(java_version)
		self.set_option('Service Java Path', java_path)

	def create_service(self):
		super().create_service()

		# User accepted the EULA during installation, so forward that for this service
		eula = os.path.join(self.get_app_directory(), 'eula.txt')
		with open(eula, 'w') as f:
			f.write('eula=true\n')
		self.game.ensure_file_ownership(eula)

		if not self.option_has_value('Level Name'):
			# Trim the prefix off the service name to get the default level name
			level_name = self.service[len(self.game.service_prefix):] if self.game.service_prefix != '' else self.service
			self.set_option('Level Name', level_name)
		self.option_ensure_set('Server Port')
		self.option_ensure_set('RCON Port')
		if not self.option_has_value('RCON Password'):
			# Generate a random password for RCON
			random_password = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
			self.set_option('RCON Password', random_password)
		if not self.option_has_value('Enable RCON'):
			self.set_option('Enable RCON', True)

		# Set the correct version of Java for the default game version
		self.assign_java_path()

	def check_update_available(self) -> bool:
		"""
		Check if an update is available for this game

		:return:
		"""
		version_file = os.path.join(self.get_app_directory(), '.version')
		target_version = self.get_target_version()

		if os.path.exists(version_file):
			with open(version_file, 'r') as f:
				current_version = f.read().strip()

			return current_version != target_version
		else:
			return True

	def update(self):
		"""
		Update the game server to the latest version

		:return:
		"""
		print_header('Updating Minecraft Server')

		version_file = os.path.join(self.get_app_directory(), '.version')
		target_version = self.get_target_version()
		download_url = self.game.get_download_url(target_version)

		if download_url is None:
			print('Failed to retrieve download URL for latest version.', file=sys.stderr)
			return False

		print('Downloading Minecraft Server version %s...' % target_version)
		self.game.download_file(download_url, os.path.join(self.get_app_directory(), 'minecraft_server.jar'))

		with open(version_file, 'w') as f:
			f.write(target_version)
		self.game.ensure_file_ownership(version_file)
		print('Update complete.')
		return True


if __name__ == '__main__':
	app = app_runner(GameApp())
	app()
