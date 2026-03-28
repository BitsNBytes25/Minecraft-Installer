#!/usr/bin/env python3
import json
import logging
import shutil
import sys
import os
import random
import string
import zipfile
import tomllib
# Include the virtual environment site-packages in sys.path
here = os.path.dirname(os.path.realpath(__file__))
if not os.path.exists(os.path.join(here, '.venv')):
	print('Python environment not setup')
	exit(1)
sys.path.insert(
	0,
	os.path.join(
		here,
		'.venv',
		'lib',
		'python' + '.'.join(sys.version.split('.')[:2]), 'site-packages'
	)
)
from warlock_manager.apps.manual_app import ManualApp
from warlock_manager.config.ini_config import INIConfig
from warlock_manager.config.properties_config import PropertiesConfig
from warlock_manager.libs.download import download_json, download_file
from warlock_manager.libs.java import find_java_version, get_java_paths
from warlock_manager.services.rcon_service import RCONService
from warlock_manager.libs.version import is_version_older, is_version_compatible, is_version_newer
from warlock_manager.libs.app_runner import app_runner
from warlock_manager.libs.firewall import Firewall
from warlock_manager.libs import utils
from warlock_manager.mods.base_mod import BaseMod

# Load the application runner responsible for interfacing with CLI arguments
# and providing default functionality for running the manager.

# If your script manages the firewall, (recommended), import the Firewall library

# Utilities provided by Warlock that are common to many applications

# This game supports full mod support

here = os.path.dirname(os.path.realpath(__file__))


class GameMod(BaseMod):
	@classmethod
	def from_jar(cls, jar_file: str) -> 'GameMod':
		"""
		Generate a Mod entry based on data from a Minecraft jar

		:param data:
		:param version:
		:return:
		"""
		basename = os.path.basename(jar_file)
		registered_mods = cls.get_registered_mods()
		for mod in registered_mods:
			if mod.package == basename:
				return mod

		mod_data = None
		manifest_data = None
		jar_data = {}
		with zipfile.ZipFile(jar_file, 'r') as jar:
			if 'fabric.mod.json' in jar.namelist():
				with jar.open('fabric.mod.json') as f:
					mod_data = json.load(f)
			elif 'META-INF/mods.toml' in jar.namelist():
				with jar.open('META-INF/mods.toml') as f:
					mod_data = tomllib.load(f)
			elif 'META-INF/neoforge.mods.toml' in jar.namelist():
				with jar.open('META-INF/neoforge.mods.toml') as f:
					mod_data = tomllib.load(f)
			elif 'mcmod.info' in jar.namelist():
				with jar.open('mcmod.info') as f:
					mod_data = json.load(f)

			if 'META-INF/MANIFEST.MF' in jar.namelist():
				with jar.open('META-INF/MANIFEST.MF') as f:
					manifest_data = f.read().decode('utf-8')

		# Ensure there's a cache of this mod
		package_path = os.path.join(utils.get_app_directory(), 'Packages', basename)
		if not os.path.exists(package_path):
			utils.ensure_file_parent_exists(package_path)
			shutil.copyfile(jar_file, package_path)
			utils.ensure_file_ownership(package_path)

		mod = GameMod()
		mod.package = basename
		mod.name = basename
		mod.files = ['mods/' + basename]

		if mod_data is None:
			mod.register()
			return mod

		# Load the MANIFEST into an object
		if manifest_data is not None:
			for line in manifest_data.splitlines():
				if line.startswith('Implementation-Title: '):
					jar_data['jarTitle'] = line[21:].strip()
				elif line.startswith('Implementation-Version: '):
					jar_data['jarVersion'] = line[24:].strip()
				elif line.startswith('Implementation-Vendor: '):
					jar_data['jarVendor'] = line[24:].strip()

		if 'authors' in mod_data:
			# Fabric
			mod.author = mod_data['authors'][0]
		elif 'mods' in mod_data and len(mod_data['mods']) > 0 and 'authors' in mod_data['mods'][0]:
			# Neoforge
			mod.author = mod_data['mods'][0]['authors']

		if 'contact' in mod_data and 'homepage' in mod_data['contact']:
			# Fabric
			mod.url = mod_data['contact']['homepage']
		elif 'mods' in mod_data and len(mod_data['mods']) > 0 and 'displayURL' in mod_data['mods'][0]:
			# Neoforge
			mod.url = mod_data['mods'][0]['displayURL']

		if 'description' in mod_data:
			# Fabric
			mod.description = mod_data['description']
		elif 'mods' in mod_data and len(mod_data['mods']) > 0 and 'description' in mod_data['mods'][0]:
			# Neoforge
			mod.description = mod_data['mods'][0]['description']

		if 'version' in mod_data:
			# Fabric
			mod.version = mod_data['version']
		elif 'mods' in mod_data and len(mod_data['mods']) > 0 and 'version' in mod_data['mods'][0]:
			# Neoforge
			mod.version = mod_data['mods'][0]['version']
			if mod.version == '${file.jarVersion}':
				mod.version = jar_data['jarVersion'] if 'jarVersion' in jar_data else None

		if 'name' in mod_data:
			# Fabric
			mod.name = mod_data['name']
		elif 'mods' in mod_data and len(mod_data['mods']) > 0 and 'displayName' in mod_data['mods'][0]:
			# Neoforge
			mod.name = mod_data['mods'][0]['displayName']

		if 'id' in mod_data:
			# Fabric
			mod.id = mod_data['id']
		elif 'mods' in mod_data and len(mod_data['mods']) > 0 and 'modId' in mod_data['mods'][0]:
			# Neoforge
			mod.id = mod_data['mods'][0]['modId']

		mod.register()
		return mod

	@classmethod
	def find_mods(cls, mod_lookup: str) -> list['BaseMod']:
		"""
		Search for a mod from mods present locally in Packages/
		:param mod_lookup:
		:return:
		"""
		all_mods = []
		matched_mods = []
		if os.path.exists(os.path.join(utils.get_app_directory(), 'Packages')):
			for file in os.listdir(os.path.join(utils.get_app_directory(), 'Packages')):
				if file.endswith('.jar'):
					all_mods.append(GameMod.from_jar(os.path.join(utils.get_app_directory(), 'Packages', file)))

		for mod in all_mods:
			if mod_lookup.lower() in mod.name.lower():
				matched_mods.append(mod)

		return matched_mods


class GameApp(ManualApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'Minecraft'
		self.service_prefix = 'minecraft-'
		self.desc = 'Minecraft Java Edition'
		self.service_handler = GameService
		self.mod_handler = GameMod
		self.multi_binary = True
		self._latest_version = None

		self.configs = {
			'manager': INIConfig('manager', os.path.join(here, '.settings.ini'))
		}
		self.load()

	def first_run(self) -> bool:
		"""
		Perform first-run configuration for setting up the game server initially

		:param game:
		:return:
		"""

		if os.geteuid() != 0:
			logging.error('Please run this script with sudo to perform first-run configuration.')
			return False

		services = self.get_services()
		if len(services) == 0:
			# No services detected, create one.
			logging.info('No services detected, creating one...')
			self.create_service('server')
		else:
			logging.info('Detected %d services, skipping first-run creation.' % len(services))
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
		dat = download_json(src_manifest)
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
		dat = download_json(src_manifest)
		versions = ['latest']
		for version in dat['versions']:
			if version['type'] == 'release':
				versions.append(version['id'])
		return versions

	def get_fabric_versions_available(self) -> list:
		"""
		Get all versions of the Fabric mod loader available.
		:return:
		"""
		src = 'https://meta.fabricmc.net/v2/versions/loader'
		dat = download_json(src)
		versions = ['none']
		counter = 0
		for version in dat:
			versions.append(version['version'])
			counter += 1
			if counter > 30:
				break
		return versions

	def get_fabric_launcher_version(self) -> str | None:
		"""
		Get the latest stable version of the Fabric launcher.

		:return:
		"""
		src = 'https://meta.fabricmc.net/v2/versions/installer'
		dat = download_json(src)
		for version in dat:
			if version['stable']:
				return version['version']
		return None

	def get_download_url(self, version: str) -> str | None:
		"""
		Get the download URL for the server for a specific version.

		Pulls live data from the Mojang version manifest.
		:return:
		"""
		from pprint import pprint
		logging.debug('Searching for download URL for version %s...' % version)
		src_manifest = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
		meta_url = None
		dat = download_json(src_manifest)
		for version_dat in dat['versions']:
			if version_dat['id'] == version:
				meta_url = version_dat['url']
				break

		if meta_url is None:
			print('Version %s not found in version manifest.' % version, file=sys.stderr)
			return None

		# Now that the meta_url for the package is ready, grab that which will contain the download URL for the server
		logging.debug('Retrieving version metadata from %s...' % meta_url)
		dat = download_json(meta_url)
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
		elif option == 'Service Game Version' or option == 'Service Fabric Mod Loader':
			# If the game version is updated, we should also update the server to match that version
			# and change the Java runtime to match the appropriate version for that game version.
			try:
				self.assign_java_path()
			except OSError as e:
				print('WARNING: Failed to find Java installation for game version %s: %s' % (new_value, str(e)), file=sys.stderr)
			self.update()
			self.build_systemd_config()
		elif option == 'Service Java Path':
			# If the Java path is updated, generate a new systemd service file.
			self.build_systemd_config()
			self.reload()

	def get_option_options(self, option: str):
		"""
		Get a list of options for a specific configuration option, if applicable
		:param option:
		:return:
		"""
		if option == 'Service Game Version':
			return self.game.get_versions_available()
		elif option == 'Service Java Path':
			return get_java_paths()
		elif option == 'Service Fabric Mod Loader':
			return self.game.get_fabric_versions_available()
		else:
			return super().get_option_options(option)

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

		Each entry in the returned list should contain 3 items:

		* Config name or integer of port (for non-definable ports)
		* 'UDP' or 'TCP' to indicate protocol
		* Short description of the port purpose
		* Optional boolean to indicate if this is an optional port (ie: not checked at startup)

		Example:

		```python
		return [
			['Game Port', 'UDP', 'Primary game port for clients to connect to', False],
			[25565, 'TCP', 'RCON port, statically assigned and cannot be changed', True]
		]
		```

		:return:
		"""
		query_port_optional = not self.get_option_value('Enable Query')
		rcon_port_optional = not self.get_option_value('Enable RCON')

		return [
			('Query Port', 'udp', '%s query port' % self.game.name, query_port_optional),
			('Server Port', 'tcp', '%s game port' % self.game.name),
			('RCON Port', 'tcp', '%s RCON port' % self.game.name, rcon_port_optional)
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
		binary = 'minecraft_server.jar'

		target_fabric_version = self.get_option_value('Service Fabric Mod Loader')
		if target_fabric_version != 'none':
			target_version = self.get_target_version()
			launcher_version = self.game.get_fabric_launcher_version()
			if launcher_version is not None:
				binary = 'fabric-server-mc.%s-loader.%s-launcher.%s.jar' % (target_version, target_fabric_version, launcher_version)

		return '%s -Xmx1G -Xms1G -jar %s nogui' % (self.get_option_value('Service Java Path'), binary)

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

	def get_enabled_mods(self) -> list[GameMod]:
		"""
		Get all enabled mods that are locally available on this service

		:return:
		"""

		ret = []
		if not os.path.exists(os.path.join(self.get_app_directory(), 'mods')):
			return ret

		for file in os.listdir(os.path.join(self.get_app_directory(), 'mods')):
			if file.endswith('.jar'):
				ret.append(GameMod.from_jar(os.path.join(self.get_app_directory(), 'mods', file)))

		return ret

	def add_mod(self, mod: 'BaseMod') -> bool:
		"""
		Install a mod

		:param mod:
		:return:
		"""
		logging.info('Installing mod %s' % mod.name)
		enabled_mods = self.get_enabled_mods()
		for check_mod in enabled_mods:
			if check_mod.id == mod.id and check_mod.name == mod.name:
				if not is_version_newer(check_mod.version, mod.version):
					logging.error('Mod %s is already installed' % mod.name)
					return True
				else:
					# Remove old version of this mod
					os.remove(os.path.join(self.get_app_directory(), 'mods', check_mod.package))

		# Copy the package into the game executable directory.
		source_archive = os.path.join(utils.get_app_directory(), 'Packages', mod.package)
		target_archive = os.path.join(self.get_app_directory(), 'mods', mod.package)
		shutil.copy(source_archive, target_archive)
		return True

	def remove_mod(self, mod: 'BaseMod') -> bool:
		"""
		Remove a mod

		Will completely uninstall the requested mod

		:param mod:
		:return:
		"""
		target_archive = os.path.join(self.get_app_directory(), 'mods', mod.package)
		if os.path.exists(target_archive):
			os.remove(target_archive)
		return True

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
		elif is_version_compatible(target_version, '1.20.5', '25.99.99'):
			java_version = 21
		else:
			java_version = 25

		logging.debug('Assigning Java version %d for game version %s' % (java_version, target_version))
		java_path = find_java_version(java_version)
		self.set_option('Service Java Path', java_path)

	def create_service(self):
		super().create_service()

		# User accepted the EULA during installation, so forward that for this service
		eula = os.path.join(self.get_app_directory(), 'eula.txt')
		with open(eula, 'w') as f:
			f.write('eula=true\n')
		utils.ensure_file_ownership(eula)

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

		# Download the latest version of the game server
		self.update()

	def check_update_available(self) -> bool:
		"""
		Check if an update is available for this game

		:return:
		"""
		logging.debug('Checking for updates on %s' % self.get_name())
		version_file = os.path.join(self.get_app_directory(), '.version')
		target_version = self.get_target_version()

		if os.path.exists(version_file):
			with open(version_file, 'r') as f:
				current_version = f.read().strip()

			logging.debug('Current version: %s' % current_version)
			logging.debug('Target version: %s' % target_version)
			return current_version != target_version
		else:
			logging.debug('No version file found, assuming update is available.')
			return True

	def update(self):
		"""
		Update the game server to the latest version

		:return:
		"""
		version_file = os.path.join(self.get_app_directory(), '.version')
		target_version = self.get_target_version()
		download_url = self.game.get_download_url(target_version)

		if not self.is_stopped():
			logging.error('Cannot update while the server is running.')
			return False

		if download_url is None:
			logging.error('Failed to retrieve download URL for latest version.')
			return False

		if os.path.exists(version_file):
			with open(version_file, 'r') as f:
					current_version = f.read().strip()
		else:
			current_version = None

		if current_version == target_version:
			logging.info('Minecraft Server is already at the latest version (%s).' % target_version)
		else:
			logging.info('Updating Minecraft Server to version %s...' % target_version)
			download_file(download_url, os.path.join(self.get_app_directory(), 'minecraft_server.jar'))

			with open(version_file, 'w') as f:
				f.write(target_version)
			utils.ensure_file_ownership(version_file)

		# Check fabric too
		target_fabric_version = self.get_option_value('Service Fabric Mod Loader')
		if target_fabric_version != 'none':
			launcher_version = self.game.get_fabric_launcher_version()
			if launcher_version is None:
				logging.error('Failed to retrieve Fabric launcher version.')
				return False
			target_file = 'fabric-server-mc.%s-loader.%s-launcher.%s.jar' % (target_version, target_fabric_version, launcher_version)
			source_file = 'https://meta.fabricmc.net/v2/versions/loader/%s/%s/%s/server/jar' % (target_version, target_fabric_version, launcher_version)
			if not os.path.exists(os.path.join(self.get_app_directory(), target_file)):
				logging.info('Downloading Fabric server loader %s...' % target_file)
				download_file(source_file, os.path.join(self.get_app_directory(), target_file))
			else:
				logging.info('Fabric server loader %s already exists.' % target_file)
		print('Update complete.')
		return True

	def get_save_files(self) -> list | None:
		"""
		Get a list of save files / directories for the game server

		:return:
		"""
		return [
			'banned-ips.json',
			'banned-players.json',
			'ops.json',
			'whitelist.json',
			self.get_name(),
			self.get_name() + '_nether',
			self.get_name() + '_the_end'
		]


if __name__ == '__main__':
	app = app_runner(GameApp())
	app()
