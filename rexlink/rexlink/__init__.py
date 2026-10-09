__version__ = "1.3.0"
APP_ID = "rexlink"
import os

# порты можно переопределить (например, для второго экземпляра): REXLINK_PORT, REXLINK_DISCOVERY_PORT
PORT = int(os.environ.get("REXLINK_PORT", 47820))                      # TLS: управление и потоки
DISCOVERY_PORT = int(os.environ.get("REXLINK_DISCOVERY_PORT", 47821))  # UDP: поиск ПК в локальной сети
