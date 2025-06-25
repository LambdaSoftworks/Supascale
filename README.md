# Supabase Multi-Manager

A powerful bash script for managing multiple self-hosted Supabase instances on a single machine. This tool automates the setup, configuration, and management of separate Supabase environments, each with its own set of ports and configurations.

## Features

- 🚀 **Easy Project Creation**: Automated setup of new Supabase instances with unique configurations
- 🔐 **Secure by Default**: Automatic generation of secure passwords and secrets
- 🎯 **Port Management**: Intelligent port allocation for multiple services
- 🔄 **Container Management**: Simple commands to start, stop, and manage Docker containers
- 📝 **Configuration Management**: Centralized JSON-based configuration storage
- 🛠️ **Docker Integration**: Seamless integration with Docker Compose

## Prerequisites

- Docker and Docker Compose
- `jq` (JSON processor)
- Git
- Bash shell environment
- Sudo privileges (required for Docker operations)
- Supabase CLI (must be in your PATH)

## Installation

1. Clone this repository:
```bash
git clone [repository-url]
```

2. Make the script executable:
```bash
chmod +x supascale-cli.sh
```

3. Optionally, add to your PATH for easier access:
```bash
ln -s $(pwd)/supascale-cli.sh /usr/local/bin/supascale-cli
```

## Usage

### Available Commands

```bash
supascale-cli [command] [options]
```

- `list`: Display all configured projects
- `add`: Create a new Supabase instance
- `start <project_id>`: Start a specific project
- `stop <project_id>`: Stop a specific project
- `remove <project_id>`: Remove a project from the configuration
- `help`: Show help message

### Examples

1. **Create a new project**:
```bash
supascale-cli add
```

2. **List all projects**:
```bash
supascale-cli list
```

3. **Start a project**:
```bash
supascale-cli start my-project
```

4. **Stop a project**:
```bash
supascale-cli stop my-project
```

## Project Structure

When you create a new project, the following structure is set up:

```
$HOME/<project_id>/
└── supabase/
    ├── docker/
    │   ├── docker-compose.yml
    │   ├── .env
    │   └── volumes/
    └── supabase/
        └── config.toml
```

## Configuration

The script uses two main configuration files:

1. **Central Configuration** (`$HOME/.supabase_multi_manager.json`):
   ```json
   {
     "projects": {
       "project-id": {
         "directory": "/path/to/project",
         "ports": {
           "api": 54321,
           "db": 54322,
           "shadow": 54320,
           "studio": 54323,
           "inbucket": 54324,
           "smtp": 54325,
           "pop3": 54326,
           "analytics": 54327,
           "pooler": 54329,
           "kong_https": 54764
         }
       }
     },
     "last_port_assigned": 54321
   }
   ```

2. **Project-specific Environment** (`.env` files):
   - Generated secrets:
     - `POSTGRES_PASSWORD`
     - `JWT_SECRET`
     - `DASHBOARD_PASSWORD`
     - `VAULT_ENC_KEY`
   - Manual configuration required:
     - `ANON_KEY`
     - `SERVICE_ROLE_KEY`

## Port Allocation

The script uses a base port of 54321 and increments by 10000 for each new project. For each project:

- Shadow Port: Base port - 1
- API Port (Kong): Base port
- Database Port: Base port + 1
- Studio Port: Base port + 2
- Inbucket Port: Base port + 3
- SMTP Port: Base port + 4
- POP3 Port: Base port + 5
- Analytics Port: Base port + 6
- Pooler Port: Base port + 8
- Kong HTTPS Port: Base port + 443

## Security Notes

- Passwords and secrets are automatically generated using `/dev/urandom` (40 characters, alphanumeric)
- JWT secrets must be manually configured after project creation
- Environment variables are stored locally in project-specific `.env` files
- Each project runs in isolated Docker containers
- Docker operations require sudo privileges

## Access URLs

When a project is started, the script automatically:
- Detects the host IP address (falls back to localhost if not found)
- Provides URLs for accessing:
  - Studio UI: `http://<host-ip>:<studio-port>`
  - API: `http://<host-ip>:<api-port>`

## Troubleshooting

1. **Port Conflicts**
   - Each project uses a different port range (10000 ports apart)
   - If you encounter port conflicts, check running Docker containers
   - Use `sudo docker ps` to verify running instances

2. **Docker Issues**
   - Ensure Docker daemon is running
   - Check Docker logs for specific container issues
   - Use `sudo docker compose logs` in project directory for detailed logs
   - Make sure you have sudo privileges

3. **Common Issues**
   - If `jq` is missing: Install using package manager
   - If ports are already in use: Stop conflicting services
   - If Docker fails to start: Check Docker daemon status
   - If permission denied: Make sure you're using sudo with Docker commands

## Cleanup

1. **Removing a Project**
   - Use `supascale-cli remove <project_id>` to remove project from configuration
   - Note: This doesn't delete project files or Docker containers
   - To clean up Docker containers: `docker container prune`
   - To completely remove a project, manually delete the project directory

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - Copyright (c) 2025 Lambda Softworks

## Acknowledgments

- Original development by Lambda Softworks
- Built on top of [Supabase](https://supabase.com/) 
