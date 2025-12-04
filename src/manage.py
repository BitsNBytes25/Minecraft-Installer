#!/usr/bin/env python3
import pwd
import sys
from scriptlets._common.firewall_allow import *
from scriptlets._common.firewall_remove import *
from scriptlets.bz_eval_tui.prompt_yn import *
from scriptlets.bz_eval_tui.prompt_text import *
from scriptlets.bz_eval_tui.table import *
from scriptlets.bz_eval_tui.print_header import *
from scriptlets._common.get_wan_ip import *
# import:org_python/venv_path_include.py
import yaml
import json
import random
import string
from scriptlets.warlock.base_app import *
from scriptlets.warlock.rcon_service import *
from scriptlets.warlock.ini_config import *
from scriptlets.warlock.properties_config import *
from scriptlets.warlock.default_run import *
from urllib import request
from urllib import error as urllib_error

here = os.path.dirname(os.path.realpath(__file__))


class GameApp(BaseApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'Minecraft'
		self.desc = 'Minecraft Java Edition'
		self.services = ('minecraft-server',)
		self._svcs = None

		self.configs = {
			'manager': INIConfig('manager', os.path.join(here, '.settings.ini'))
		}
		self.load()

	def check_update_available(self) -> bool:
		"""
		Check if an update is available for this game

		:return:
		"""
		if os.path.exists(os.path.join(here, '.version')):
			with open(os.path.join(here, '.version'), 'r') as f:
				current_version = f.read().strip()
			try:
				with request.urlopen('https://net-secondary.web.minecraft-services.net/api/v1.0/download/latest') as resp:
					dat = json.loads(resp.read().decode('utf-8'))
					return 'result' in dat and dat['result'] != current_version
			except urllib_error.HTTPError:
				return False
			except urllib_error.URLError:
				return False
		else:
			return True

	def update(self):
		"""
		Update the game server to the latest version

		:return:
		"""
		print_header('Updating Minecraft Server')

		try:
			latest_version = None
			with request.urlopen('https://net-secondary.web.minecraft-services.net/api/v1.0/download/latest') as resp:
				dat = json.loads(resp.read().decode('utf-8'))
				if 'result' in dat:
					latest_version = dat['result']

			if latest_version is None:
				print('Failed to retrieve latest version information.', file=sys.stderr)
				return False

			download_url = None
			with request.urlopen('https://net-secondary.web.minecraft-services.net/api/v1.0/download/links') as resp:
				dat = json.loads(resp.read().decode('utf-8'))
				if 'result' in dat and 'links' in dat['result']:
					for link in dat['result']['links']:
						if link['downloadType'] == 'serverJar':
							download_url = link['downloadUrl']
							break

			if download_url is None:
				print('Failed to retrieve download URL for latest version.', file=sys.stderr)
				return False

			print('Downloading Minecraft Server version %s...' % latest_version)
			with request.urlopen(download_url) as download_resp:
				with open(os.path.join(here, 'AppFiles/minecraft_server.jar'), 'wb') as out_file:
					out_file.write(download_resp.read())
			with open(os.path.join(here, '.version'), 'w') as f:
				f.write(latest_version)
			print('Update complete.')

			if os.geteuid == 0:
				stat_info = os.stat(here)
				uid = stat_info.st_uid
				gid = stat_info.st_gid
				os.chown(os.path.join(here, 'AppFiles/minecraft_server.jar'), uid, gid)
				os.chown(os.path.join(here, '.version'), uid, gid)
			return True

		except urllib_error.HTTPError:
			print('Failed to download the latest version (HTTP Error).', file=sys.stderr)
			return False
		except urllib_error.URLError:
			print('Failed to download the latest version (URL Error).', file=sys.stderr)
			return False

	def get_save_files(self) -> Union[list, None]:
		"""
		Get a list of save files / directories for the game server

		:return:
		"""
		files = ['banned-ips.json', 'banned-players.json', 'ops.json', 'whitelist.json']
		for service in self.get_services():
			files.append(service.get_name())
		return files

	def get_save_directory(self) -> Union[str, None]:
		"""
		Get the save directory for the game server

		:return:
		"""
		return os.path.join(here, 'AppFiles')


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
			'server': PropertiesConfig('server', os.path.join(here, 'AppFiles/server.properties'))
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
				firewall_remove(int(previous_value), 'tcp')
			firewall_allow(int(new_value), 'tcp', 'Allow %s game port' % self.game.desc)
		elif option == 'Query Port':
			# Update firewall for game port change
			if previous_value:
				firewall_remove(int(previous_value), 'udp')
			firewall_allow(int(new_value), 'udp', 'Allow %s query port' % self.game.desc)

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

	def get_player_count(self) -> Union[int, None]:
		"""
		Get the current player count on the server, or None if the API is unavailable
		:return:
		"""
		try:
			ret = self._api_cmd('/list')
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

	def get_port(self) -> Union[int, None]:
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
		self._api_cmd('/say %s' % message)

	def save_world(self):
		"""
		Force the game server to save the world via the game API
		:return:
		"""
		self._api_cmd('save-all flush')


def menu_first_run(game: GameApp):
	"""
	Perform first-run configuration for setting up the game server initially

	:param game:
	:return:
	"""
	print_header('First Run Configuration')

	if os.geteuid() != 0:
		print('ERROR: Please run this script with sudo to perform first-run configuration.')
		sys.exit(1)

	svc = game.get_services()[0]

	svc.option_ensure_set('Level Name')
	svc.option_ensure_set('Server Port')
	svc.option_ensure_set('RCON Port')
	if not svc.option_has_value('RCON Password'):
		# Generate a random password for RCON
		random_password = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
		svc.set_option('RCON Password', random_password)
	if not svc.option_has_value('Enable RCON'):
		svc.set_option('Enable RCON', True)

if __name__ == '__main__':
	game = GameApp()
	run_manager(game)
