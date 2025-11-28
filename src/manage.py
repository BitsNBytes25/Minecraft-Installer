#!/usr/bin/env python3
import pwd
from scriptlets._common.firewall_allow import *
from scriptlets._common.firewall_remove import *
from scriptlets.bz_eval_tui.prompt_yn import *
from scriptlets.bz_eval_tui.prompt_text import *
from scriptlets.bz_eval_tui.table import *
from scriptlets.bz_eval_tui.print_header import *
from scriptlets._common.get_wan_ip import *
# import:org_python/venv_path_include.py
import yaml
import random
import string
from scriptlets.warlock.base_app import *
from scriptlets.warlock.rcon_service import *
from scriptlets.warlock.ini_config import *
from scriptlets.warlock.properties_config import *
from scriptlets.warlock.default_run import *
from scriptlets.steam.steamcmd_check_app_update import *

here = os.path.dirname(os.path.realpath(__file__))

# Require sudo / root for starting/stopping the service
IS_SUDO = os.geteuid() == 0


def format_seconds(seconds: int) -> dict:
	hours = int(seconds // 3600)
	minutes = int((seconds - (hours * 3600)) // 60)
	seconds = int(seconds % 60)

	short_minutes = ('0' + str(minutes)) if minutes < 10 else str(minutes)
	short_seconds = ('0' + str(seconds)) if seconds < 10 else str(seconds)

	if hours > 0:
		short = '%s:%s:%s' % (str(hours), short_minutes, short_seconds)
	else:
		short = '%s:%s' % (str(minutes), short_seconds)

	return {
		'h': hours,
		'm': minutes,
		's': seconds,
		'full': '%s hrs %s min %s sec' % (str(hours), str(minutes), str(seconds)),
		'short': short
	}


class GameAPIException(Exception):
	pass


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
		Check if a SteamCMD update is available for this game

		:return:
		"""
		# @todo Implement update check for Minecraft
		return False

	def get_save_files(self) -> Union[list, None]:
		"""
		Get a list of save files / directories for the game server

		:return:
		"""
		files = ['banned-ips.json', 'banned-players.json', 'ops.json', 'whitelist.json', 'server.properties']
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
		except GameAPIException:
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

	def post_start(self) -> bool:
		"""
		Perform the necessary operations for after a game has started
		:return:
		"""
		if self.is_api_enabled():
			counter = 0
			print('Waiting for API to become available...')
			while counter < 24:
				players = self.get_player_count()
				if players is not None:
					msg = self.game.get_option_value('Instance Started (Discord)')
					if '{instance}' in msg:
						msg = msg.replace('{instance}', self.get_name())
					self.game.send_discord_message(msg)
					return True
				else:
					print('API not available yet')

				time.sleep(10)
				counter += 1

			print('API did not reply within the allowed time!', file=sys.stderr)
			return False
		else:
			# API not available, so nothing to check.
			return True

	def pre_stop(self) -> bool:
		"""
		Perform operations necessary for safely stopping a server

		Called automatically via systemd
		:return:
		"""
		msg = self.game.get_option_value('Instance Stopping (Discord)')
		if '{instance}' in msg:
			msg = msg.replace('{instance}', self.get_name())
		self.game.send_discord_message(msg)

		if self.is_api_enabled():
			timers = (
				(self.game.get_option_value('Shutdown Warning 5 Minutes'), 60),
				(self.game.get_option_value('Shutdown Warning 4 Minutes'), 60),
				(self.game.get_option_value('Shutdown Warning 3 Minutes'), 60),
				(self.game.get_option_value('Shutdown Warning 2 Minutes'), 60),
				(self.game.get_option_value('Shutdown Warning 1 Minute'), 30),
				(self.game.get_option_value('Shutdown Warning 30 Seconds'), 30),
				(self.game.get_option_value('Shutdown Warning NOW'), 0),
			)
			for timer in timers:
				players = self.get_player_count()
				if players is not None and players > 0:
					print('Players are online, sending warning message: %s' % timer[0])
					self.send_message(timer[0])
					if timer[1]:
						time.sleep(timer[1])
				else:
					break

			print('Forcing server save')
			self._api_cmd('save-all flush')
			time.sleep(5)
		return True


def menu_first_run(game: GameApp):
	"""
	Perform first-run configuration for setting up the game server initially

	:param game:
	:return:
	"""
	print_header('First Run Configuration')

	if not IS_SUDO:
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
