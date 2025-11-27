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
from scriptlets.warlock.base_app import *
from scriptlets.warlock.http_service import *
from scriptlets.warlock.ini_config import *
from scriptlets.warlock.unreal_config import *
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

		self.name = 'GameName'
		self.desc = 'Longer identifier for the game server'
		self.steam_id = '123456789'
		self.services = ('list-of-services',)
		self._svcs = None

		uid = os.stat(here).st_uid
		self.save_dir = '%s/.config/Epic/Vein/Saved/SaveGames/' % pwd.getpwuid(uid).pw_dir
		# VEIN uses the default Epic save handler which stores saves in ~/.config

		self.configs = {
			'manager': INIConfig('manager', os.path.join(here, '.settings.ini'))
		}
		self.load()

	def check_update_available(self) -> bool:
		"""
		Check if a SteamCMD update is available for this game

		:return:
		"""
		return steamcmd_check_app_update(os.path.join(here, 'AppFiles', 'steamapps', 'appmanifest_%s.acf' % self.steam_id))

	def backup(self, max_backups: int = 0) -> bool:
		"""
		Backup the game server files

		:param max_backups: Maximum number of backups to keep (0 = unlimited)
		:return:
		"""
		temp_store = self.prepare_backup()

		if not os.path.exists(self.save_dir):
			print('Save directory %s does not exist, cannot continue!' % self.save_dir, file=sys.stderr)
			return False

		# Copy all files from the save directory
		for f in os.listdir(self.save_dir):
			src = os.path.join(self.save_dir, f)
			dst = os.path.join(temp_store, 'save', f)
			if not os.path.isdir(src):
				shutil.copy(src, dst)

		backup_path = game.complete_backup(max_backups)

		print('Backup saved to %s' % backup_path)
		return True

	def restore(self, path: str) -> bool:
		"""
		Restore the game server files

		:param path: Path to the backup archive
		:return:
		"""
		temp_store = self.prepare_restore(path)
		if temp_store is False:
			return False

		# Restore save content to self.save_dir
		save_src = os.path.join(temp_store, 'save')
		print('Restoring save data...')
		shutil.copytree(
			os.path.join(save_src),
			os.path.join(self.save_dir),
			dirs_exist_ok=True
		)

		self.complete_restore()
		return True


class GameService(HTTPService):
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
			'game': UnrealConfig('game', os.path.join(here, 'AppFiles/Vein/Saved/Config/LinuxServer/Game.ini')),
			'gus': UnrealConfig('gus', os.path.join(here, 'AppFiles/Vein/Saved/Config/LinuxServer/GameUserSettings.ini')),
			'engine': UnrealConfig('engine', os.path.join(here, 'AppFiles/Vein/Saved/Config/LinuxServer/Engine.ini'))
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
		if option == 'GamePort':
			# Update firewall for game port change
			if previous_value:
				firewall_remove(int(previous_value), 'udp')
			firewall_allow(int(new_value), 'udp', 'Allow %s game port' % self.game.desc)
		elif option == 'SteamQueryPort':
			# Update firewall for game port change
			if previous_value:
				firewall_remove(int(previous_value), 'udp')
			firewall_allow(int(new_value), 'udp', 'Allow %s Steam query port' % self.game.desc)

	def is_api_enabled(self) -> bool:
		"""
		Check if API is enabled for this service
		:return:
		"""
		return self.get_option_value('APIPort') != ''

	def get_api_port(self) -> int:
		"""
		Get the API port from the service configuration
		:return:
		"""
		return self.get_option_value('APIPort')

	def get_players(self) -> Union[list, None]:
		"""
		Get the current players on the server, or None if the API is unavailable
		:return:
		"""
		try:
			ret = self._http_cmd('/players')
			return ret['players']
		except GameAPIException:
			return None

	def get_player_count(self) -> Union[int, None]:
		"""
		Get the current player count on the server, or None if the API is unavailable
		:return:
		"""
		status = self.get_status()
		if status is None:
			return None
		else:
			return len(status['onlinePlayers'])

	def get_player_max(self) -> int:
		"""
		Get the maximum player count allowed on the server
		:return:
		"""
		return self.get_option_value('MaxPlayers')

	def get_status(self) -> Union[dict, None]:
		"""
		Get the current server status from the API, or None if the API is unavailable

		Returns a dictionary with the following keys
		'uptime' - float: Uptime in seconds
		'onlinePlayers' - dict: Dictionary of online players

		Each player will be tagged with its PlayerID as the key, and a dictionary with the following keys:
		'name' - str: Player name
		'timeConnected' - float: Time connected in seconds
		'characterId' - str: Unique character ID
		'status' - str: Player status/role

		:return:
		"""
		try:
			ret = self._http_cmd('/status')
			return ret
		except GameAPIException:
			return None

	def get_weather(self) -> Union[dict, None]:
		"""
		Get the current weather from the API, or None if the API is unavailable

		Returns a dictionary with the following keys
		'temperature' - float: Temperature in Celsius
		'precipitation' - int: Precipitation level
		'cloudiness' - int: Cloudiness level
		'fog' - int: Fog level
		'pressure' - float: Atmospheric pressure in hPa
		'relativeHumidity' - int: Relative humidity percentage
		'windDirection' - float: Wind direction in degrees
		'windForce' - float: Wind force in m/s

		:return:
		"""
		try:
			ret = self._http_cmd('/weather')
			return ret
		except GameAPIException:
			return None

	def get_name(self) -> str:
		"""
		Get the name of this game server instance
		:return:
		"""
		return self.get_option_value('ServerName')

	def get_port(self) -> Union[int, None]:
		"""
		Get the primary port of the service, or None if not applicable
		:return:
		"""
		return self.get_option_value('GamePort')

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""

		# There's no quick way to get the game process PID from systemd,
		# so use ps to find the process based on the map name
		processes = subprocess.run([
			'ps', 'axh', '-o', 'pid,cmd'
		], stdout=subprocess.PIPE).stdout.decode().strip()
		exe = os.path.join(here, 'AppFiles/Vein/Binaries/Linux/VeinServer-Linux-')
		for line in processes.split('\n'):
			pid, cmd = line.strip().split(' ', 1)
			if cmd.startswith(exe):
				return int(line.strip().split(' ')[0])
		return 0

	def send_message(self, message: str):
		"""
		Send a message to all players via the game API
		:param message:
		:return:
		"""

		pass
		# @todo Vein just implemented this but is yet to publish documentation on how to use it.
		#try:
		#	self._api_cmd('/notification', method='POST', data={'message': message})
		#except GameAPIException as e:
		#	print('Failed to send message via API: %s' % str(e))

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

		# Disabling until VEIN publishes their documentation on notifications
		'''
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
			self.save_world()
		'''
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

	if not svc.option_has_value('ServerName'):
		svc.set_option_value('ServerName', 'My VEIN Server')
	if not svc.option_has_value('GamePort'):
		svc.set_option_value('GamePort', '7777')
	if not svc.option_has_value('SteamQueryPort'):
		svc.set_option_value('SteamQueryPort', '27015')
	if not svc.option_has_value('APIPort'):
		svc.set_option_value('APIPort', '8080')

if __name__ == '__main__':
	game = GameApp()
	run_manager(game)
