# ARK: Survival Ascended Docker Server

A complete Docker-based solution for running ARK: Survival Ascended dedicated servers on Linux.

## Features

- **Easy Configuration**: Simple JSON configuration file for all server settings
- **Automatic Updates**: Server checks for and applies updates
- **Automatic Restarts**: Monitors server health and automatically restarts when needed
- **Backup System**: Create and restore backups of your server data
- **RCON Support**: Remote administration through RCON
- **API Support**: Optional support for server API and plugins
- **Multi-Map Support**: Run any official or custom map
- **Mod Support**: Easy installation of workshop mods
- **Comprehensive CLI**: Simple command-line interface for server management

## Quick Start

```bash
# Create a configuration file
cp ark-server-config-example.json config/ark-server-config.json

# Edit the configuration file with your settings
vim config/ark-server-config.json

# Start the server with Docker Compose
docker-compose up -d
```

## Configuration

Edit `config/ark-server-config.json` to configure your server. Settings marked with `[REQUIRED]` must be set, while those with `[OPTIONAL]` have defaults or can be omitted.

### Example Configuration

```json
{
  "server": {
    "name": "My ARK Server",
    "map": "TheIsland_ASA",
    "session_name": "MyARKServer"
  },
  "network": {
    "port": "7777",
    "query_port": "27015",
    "rcon_port": "27020",
    "admin_password": "YourSecureAdminPassword"
  }
}
```

See `ark-server-config.json` for the full list of available settings.

## Server Management

The container includes a CLI tool for easy server management:

```bash
# Connect to the container
docker exec -it ark-server ark --help

# Common commands
docker exec -it ark-server ark status     # Check server status
docker exec -it ark-server ark logs       # View server logs
docker exec -it ark-server ark restart    # Restart the server
docker exec -it ark-server ark backup     # Create a backup
docker exec -it ark-server ark rcon       # RCON console
```

## Volume Mounts

The following volumes can be mounted:

- `/config`: Server configuration files
- `/backups`: Server backup files
- `/steam/steamapps/common/asa-server/ShooterGame/Saved`: Game save data

## Environment Variables

All settings in the configuration file can also be set via environment variables. Environment variables take precedence over the configuration file.

## Docker Compose Example

```yaml
version: '3'
services:
  ark-server:
    image: ark-server-asa
    container_name: ark-server
    ports:
      - "7777:7777/udp"      # Game port
      - "27015:27015/udp"    # Query port
      - "27020:27020/tcp"    # RCON port
    volumes:
      - ./config:/config
      - ./backups:/backups
      - ./saved:/steam/steamapps/common/asa-server/ShooterGame/Saved
    restart: unless-stopped
```

## Project Structure

```
/
├── scripts/
│   ├── entrypoint.sh       # Container entrypoint script
│   └── manager/            # Server management scripts
│       ├── ark-cli.sh      # CLI interface
│       ├── init.sh         # Server initialization
│       ├── start.sh        # Server startup
│       ├── stop.sh         # Server shutdown
│       ├── restart.sh      # Server restart
│       ├── update.sh       # Server update
│       ├── backup.sh       # Backup creation
│       ├── restore.sh      # Backup restoration
│       ├── logs.sh         # Log viewing
│       ├── status.sh       # Server status
│       ├── rcon.sh         # RCON client
│       ├── monitor.sh      # Server monitoring
│       ├── monitorManager.sh # Monitor management
│       ├── utils/          # Utility scripts
│       └── rconUtils/      # RCON utilities
├── Dockerfile              # Docker build file
├── docker-compose.yml      # Docker compose configuration
└── ark-server-config.json  # Example configuration
```

## Support

If you encounter issues, please check the logs for error messages:

```bash
docker exec -it ark-server ark logs
``` 