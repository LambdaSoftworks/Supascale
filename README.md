# Supascale

A bash script for managing multiple self-hosted Supabase instances on a single machine. This tool automates the setup, configuration, and management of separate Supabase environments, each with its own set of ports and configurations. Includes comprehensive backup and restore capabilities with encryption, validation, dry-run testing, and cloud storage support.

## Features

-  **Easy Project Creation**: Automated setup of new Supabase instances with unique configurations
-  **Secure by Default**: Automatic generation of secure passwords and secrets
-  **Port Management**: Intelligent port allocation for multiple services
-  **Container Management**: Simple commands to start, stop, and manage Docker containers
-  **Configuration Management**: Centralized JSON-based configuration storage
-  **Docker Integration**: Seamless integration with Docker Compose
-  **Container Updates**: Update Supabase containers to latest versions with automatic backup and rollback
-  **Health Checks**: Automatic health verification after updates with auto-rollback on failure
-  **Selective Updates**: Update specific services using `--only` flag
-  **Comprehensive Backups**: Full project backups including database, storage, functions, and config
-  **Backup Validation**: SHA256 checksums and manifest verification for backup integrity
-  **Dry-Run Restore**: Test restore operations without modifying live data
-  **Encrypted Backups**: Optional AES-256 encryption for sensitive data
-  **S3 Integration**: Upload backups to AWS S3 or compatible storage
-  **Retention Policies**: Automatic cleanup of old backups
-  **Custom Domain Support**: Configure custom domains with automatic SSL certificate provisioning
-  **Multi-Server Support**: Works with Nginx, Apache, and Caddy web servers
-  **Auto-SSL**: Let's Encrypt integration via Certbot with automatic renewal

## Prerequisites

- Docker and Docker Compose
- `jq` (JSON processor)
- Git
- Bash shell environment
- Sudo privileges (required for Docker operations)
- `curl` or `wget` (for fetching updates)
- `openssl` (for backup encryption, usually pre-installed)
- `aws-cli` (optional, for S3 backup storage)

**For Custom Domain Support (optional):**
- A domain name with DNS pointing to your server (A record)
- `certbot` (for Let's Encrypt SSL certificates)
- One of: `nginx`, `apache2`, or `caddy` web server
- Ports 80 and 443 available (for HTTP/HTTPS)

## Installation

1. Clone this repository:
```bash
git clone [repository-url]
```

2. Make the script executable:
```bash
chmod +x supascale.sh
```

## Usage

### Available Commands

```bash
./supascale.sh [command] [options]
```

**Project Management:**
- `list`: Display all configured projects
- `add <project_id>`: Create a new Supabase instance
- `start <project_id>`: Start a specific project
- `stop <project_id>`: Stop a specific project
- `remove <project_id>`: Remove a project from the configuration

**Container Updates:**
- `update-containers <project_id>`: Update containers for a specific project
- `update-containers --all`: Update containers for all projects
- `check-updates <project_id>`: Check available updates (dry run)
- `container-versions <project_id>`: Show current container versions

**Script Management:**
- `update`: Update Supascale script to latest version
- `version`: Show current version
- `help`: Show help message

**Backup & Restore:**
- `backup <project_id> [options]`: Create a backup
- `restore <project_id> --from <path> [options]`: Restore from a backup
- `list-backups <project_id>`: List available backups
- `verify-backup <path>`: Verify backup integrity
- `backup-info <path>`: Show backup metadata
- `setup-backup-schedule <project_id>`: Show cron examples

**Update Flags:**
- `--only=service1,service2`: Only update specific services (e.g., `--only=db,studio`)

**Custom Domain:**
- `setup-domain <project_id>`: Configure custom domain with SSL certificate
- `remove-domain <project_id>`: Remove custom domain configuration

### Examples

1. **Create a new project**:
```bash
./supascale.sh add my-project
```

2. **List all projects**:
```bash
./supascale.sh list
```

3. **Start a project**:
```bash
./supascale.sh start my-project
```

4. **Stop a project**:
```bash
./supascale.sh stop my-project
```

5. **Check for container updates**:
```bash
./supascale.sh check-updates my-project
```

6. **Update all containers**:
```bash
./supascale.sh update-containers my-project
```

7. **Update specific containers only**:
```bash
./supascale.sh update-containers my-project --only=db,studio,kong
```

8. **Update all projects**:
```bash
./supascale.sh update-containers --all
```

9. **View current container versions**:
```bash
./supascale.sh container-versions my-project
```

10. **Create a full backup**:
```bash
./supascale.sh backup my-project --type full
```

11. **Create an encrypted database backup to S3**:
```bash
./supascale.sh backup my-project --type database --destination s3://my-bucket/backups --encrypt --password-file ~/.backup.key
```

12. **Test a restore (dry-run)**:
```bash
./supascale.sh restore my-project --from ~/.supascale_backups/my-project/backups/my-project_full_20260118_143022.supascale.tar.gz --dry-run
```

13. **Restore from backup**:
```bash
./supascale.sh restore my-project --from backup.tar.gz --confirm
```

14. **List available backups**:
```bash
./supascale.sh list-backups my-project
```

15. **Configure a custom domain**:
```bash
./supascale.sh setup-domain my-project
```

16. **Remove custom domain**:
```bash
./supascale.sh remove-domain my-project
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

1. **Central Configuration** (`$HOME/.supascale_database.json`):
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
     - `ANON_KEY`
     - `SERVICE_ROLE_KEY`

## Port Allocation

The script uses a base port of 54321 and increments by 1000 for each new project. For each project:

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

## Container Updates

Supascale can update your Supabase containers to the latest versions with automatic backup and rollback capabilities.

### Update Process

1. **Pre-update Snapshot**: Creates a full backup of your project (docker-compose.yml, .env, all volumes)
2. **Version Fetch**: Retrieves latest versions from GitHub and Docker Hub
3. **Update docker-compose.yml**: Updates image tags in dependency order
4. **Pull & Restart**: Pulls new images and restarts containers
5. **Health Check**: Verifies all containers are running and API is responding
   - If health check fails: **Automatic rollback** with error details
6. **User Confirmation**: Asks if everything is working
   - If yes: Saves versioned backup, cleans up snapshot
   - If no: Rolls back to pre-update state

### Available Services

The following services can be updated (use with `--only` flag):

| Service | Description |
|---------|-------------|
| `studio` | Supabase Studio dashboard |
| `kong` | API gateway |
| `auth` | Authentication service (GoTrue) |
| `rest` | REST API (PostgREST) |
| `realtime` | Real-time subscriptions |
| `storage` | File storage API |
| `imgproxy` | Image transformation |
| `meta` | Postgres metadata API |
| `functions` | Edge functions runtime |
| `analytics` | Logging & analytics (Logflare) |
| `db` | PostgreSQL database |
| `vector` | Log aggregation |
| `supavisor` | Connection pooler |

### Backup Storage

Backups are stored in `~/.supascale_backups/`:

```
~/.supascale_backups/
└── <project_id>/
    ├── snapshots/                    # Pre-update snapshots (temporary)
    │   └── 20260118_143022_pre_update/
    │       ├── docker-compose.yml
    │       ├── .env
    │       ├── volumes.tar.gz
    │       ├── versions.json
    │       └── metadata.json
    └── versions/                     # Post-update backups (permanent)
        └── 20260118_151234/
            ├── volumes.tar.gz
            ├── versions.json
            └── metadata.json
```

## Backup & Restore

Supascale provides comprehensive backup and restore capabilities with validation, encryption, and cloud storage support.

### Backup Types

| Type | Description |
|------|-------------|
| `full` | Complete project backup (database, storage, functions, config, volumes) |
| `database` | PostgreSQL database only (custom format + SQL dump) |
| `storage` | Storage buckets and files |
| `functions` | Edge functions code |
| `config` | docker-compose.yml, .env, and config.toml |

### Backup Options

| Option | Description |
|--------|-------------|
| `--type=TYPE` | Backup type: full, database, storage, functions, config (default: full) |
| `--destination=DEST` | Storage destination: local, s3://bucket/path (default: local) |
| `--encrypt` | Enable AES-256 encryption |
| `--password=PASS` | Encryption password |
| `--password-file=PATH` | Read password from file |
| `--retention=N` | Keep only the last N backups (auto-delete older) |
| `--silent` | Minimal output for cron jobs |

### Restore Options

| Option | Description |
|--------|-------------|
| `--from=PATH` | Backup source (local path or s3:// URL) |
| `--dry-run` | Validate backup and test restore without modifying data |
| `--confirm` | Skip confirmation prompt |
| `--password=PASS` | Decryption password for encrypted backups |

### Backup Process

1. **Prepare**: Creates temporary working directory
2. **Stop Containers**: Stops database for consistent backup (full/database only)
3. **Backup Components**: Executes component-specific backup functions
4. **Create Manifest**: Generates SHA256 checksums for all files
5. **Compress**: Creates .tar.gz archive
6. **Encrypt**: Applies AES-256-CBC encryption (if --encrypt)
7. **Upload/Save**: Stores to local filesystem or S3
8. **Retention**: Deletes old backups beyond retention count

### Restore Process

1. **Download**: Fetches backup from S3 if needed
2. **Decrypt**: Decrypts backup if encrypted
3. **Extract**: Extracts archive to temporary directory
4. **Validate**: Verifies manifest and all checksums
5. **Dry-run (optional)**: Tests database restore to temporary database
6. **Stop Containers**: Stops all containers for restore
7. **Restore Components**: Restores each component
8. **Start Containers**: Starts all containers

### Dry-Run Restore

The `--dry-run` flag performs full validation without modifying live data:

- Extracts and validates backup archive
- Verifies all file checksums against manifest
- Creates temporary database and tests pg_restore
- Validates storage and function archives
- Reports success/failure with detailed output

```bash
# Test restore without modifying anything
./supascale.sh restore my-project --from backup.tar.gz --dry-run
```

### Backup Archive Structure

```
my-project_full_20260118_143022.supascale.tar.gz
├── manifest.json           # Checksums + metadata
├── database/
│   ├── database.dump       # pg_dump custom format
│   ├── database.sql        # Plain SQL format
│   └── schema_only.sql     # Schema reference
├── storage/
│   └── storage.tar.gz      # Storage buckets
├── functions/
│   └── functions.tar.gz    # Edge functions
├── config/
│   ├── docker-compose.yml
│   ├── .env
│   └── config.toml
└── volumes/
    ├── volumes.tar.gz      # ./volumes/ directory
    └── volume_*.tar.gz     # Named Docker volumes
```

### Backup Storage Locations

**Local Storage:**
```
~/.supascale_backups/
└── <project_id>/
    └── backups/
        ├── my-project_full_20260118_143022.supascale.tar.gz
        ├── my-project_database_20260118_150000.supascale.tar.gz.enc
        └── ...
```

**S3 Storage:**
```
s3://bucket/path/my-project_full_20260118_143022.supascale.tar.gz
```

### Scheduled Backups (Cron)

Use `setup-backup-schedule` to generate cron examples:

```bash
./supascale.sh setup-backup-schedule my-project
```

Example cron entries:

```bash
# Daily full backup at 2 AM
0 2 * * * /path/to/supascale.sh backup my-project --type full --silent

# Daily database backup with 30-day retention
0 3 * * * /path/to/supascale.sh backup my-project --type database --silent --retention 30

# Weekly encrypted backup to S3
0 1 * * 0 /path/to/supascale.sh backup my-project --type full --destination s3://my-bucket/backups --encrypt --password-file /secure/backup.key --silent
```

### S3 Configuration

For S3 backups, ensure AWS CLI is installed and configured:

```bash
# Install AWS CLI
sudo apt install awscli  # Ubuntu/Debian
brew install awscli      # macOS

# Configure credentials
aws configure
```

## Custom Domain Configuration

Supascale supports custom domains with automatic SSL certificate provisioning via Let's Encrypt. This allows you to access your Supabase instances using friendly URLs like `https://myapp.example.com`.

### Prerequisites

Before configuring a custom domain, ensure you have:

1. **A domain name** pointing to your server's IP address (A record)
2. **A web server** installed (Nginx, Apache, or Caddy)
3. **Certbot** installed for SSL certificate generation
4. **Ports 80 and 443** available and not blocked by firewall

### DNS Setup

Before running the setup, create a DNS A record pointing your domain to your server:

```
Type: A
Name: myapp (or @ for root domain)
Value: <your-server-ip>
TTL: 300 (or lower for faster propagation)
```

The script will display your server's public IP address during setup to help you configure DNS.

### Setup Process

The `setup-domain` command guides you through the domain configuration:

```bash
./supascale.sh setup-domain my-project
```

The setup process:
1. Displays your server's public IP for DNS configuration
2. Prompts for your domain name
3. Validates DNS resolution
4. Auto-detects installed web server (or prompts to select one)
5. Creates reverse proxy configuration
6. Generates Let's Encrypt SSL certificate
7. Enables automatic certificate renewal
8. Updates project configuration

### Web Server Support

| Web Server | Auto-Detection | SSL Mode | Notes |
|------------|----------------|----------|-------|
| Nginx | ✓ | Certbot webroot | Sites-available/sites-enabled pattern |
| Apache | ✓ | Certbot webroot | Enables required modules automatically |
| Caddy | ✓ | Automatic | Built-in automatic HTTPS, simplest setup |

If no web server is detected, you'll be prompted to select one and given installation instructions.

### Domain Routing

Custom domains use path-based routing to direct traffic:

| Path | Destination | Description |
|------|-------------|-------------|
| `/` | Studio | Supabase Studio dashboard |
| `/rest/v1/*` | Kong API | REST API endpoints |
| `/auth/v1/*` | Kong API | Authentication endpoints |
| `/storage/v1/*` | Kong API | Storage endpoints |
| `/realtime/v1/*` | Kong API | Real-time WebSocket connections |
| `/functions/v1/*` | Kong API | Edge Functions |
| `/graphql/v1*` | Kong API | GraphQL endpoint |

### Example Workflow

```bash
# 1. Create a new project
./supascale.sh add my-project

# 2. Start the project
./supascale.sh start my-project

# 3. Configure custom domain
./supascale.sh setup-domain my-project

# Example interactive session:
# Server IP: 203.0.113.50
# Create DNS A record: myapp.example.com -> 203.0.113.50
# Enter domain: myapp.example.com
# Detected web server: nginx
# Generating SSL certificate...
#
# Your Supabase instance is now available at:
#   Studio: https://myapp.example.com
#   API: https://myapp.example.com/rest/v1/
```

### Removing a Domain

To remove the custom domain configuration:

```bash
./supascale.sh remove-domain my-project
```

This will:
- Remove the web server configuration
- Optionally revoke the SSL certificate
- Update the project configuration
- Display fallback IP:port access URLs

### Database Schema Extension

When a domain is configured, the project entry in `~/.supascale_database.json` is extended:

```json
{
  "projects": {
    "my-project": {
      "directory": "/home/user/my-project",
      "ports": { ... },
      "domain": {
        "name": "myapp.example.com",
        "web_server": "nginx",
        "ssl_enabled": true,
        "ssl_cert_path": "/etc/letsencrypt/live/myapp.example.com/fullchain.pem",
        "ssl_key_path": "/etc/letsencrypt/live/myapp.example.com/privkey.pem",
        "configured_at": "2026-01-18T14:30:00Z"
      }
    }
  }
}
```

### Installing Web Servers

**Nginx (Ubuntu/Debian):**
```bash
sudo apt update && sudo apt install nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

**Apache (Ubuntu/Debian):**
```bash
sudo apt update && sudo apt install apache2
sudo a2enmod proxy proxy_http proxy_wstunnel rewrite ssl headers
sudo systemctl enable apache2
sudo systemctl start apache2
```

**Caddy (Ubuntu/Debian):**
```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy
```

**Certbot (Ubuntu/Debian):**
```bash
sudo apt update && sudo apt install certbot
# For Nginx: sudo apt install python3-certbot-nginx
# For Apache: sudo apt install python3-certbot-apache
```

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

If a custom domain is configured:
- Shows HTTPS URLs for the configured domain
- Always displays fallback IP:port URLs for direct access

## Troubleshooting

1. **Port Conflicts**
   - Each project uses a different port range (1000 ports apart)
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

4. **Container Update Issues**
   - If health check fails: Review the error output, check container logs with `docker compose logs`
   - If auto-rollback occurs: The project is restored to pre-update state automatically
   - If update shows "already at latest": Your containers are up to date
   - If version fetch fails: Check internet connection and GitHub/Docker Hub availability
   - To manually rollback: Snapshots are stored in `~/.supascale_backups/<project>/snapshots/`

5. **Backup & Restore Issues**
   - If backup fails on database: Ensure the database container is running
   - If encryption fails: Verify openssl is installed
   - If S3 upload fails: Check AWS CLI configuration with `aws configure`
   - If restore validation fails: The backup may be corrupted, check checksum errors
   - If dry-run fails: Review specific component errors before attempting live restore
   - For encrypted backups: Ensure you have the correct password

6. **Custom Domain Issues**
   - If DNS validation fails: Ensure your A record is properly configured and has propagated (use `dig your-domain.com` to verify)
   - If SSL certificate generation fails: Ensure ports 80/443 are open and the web server is running
   - If web server reload fails: Check the generated config with `nginx -t` (Nginx) or `apachectl configtest` (Apache)
   - If domain shows connection refused: Verify the Supabase containers are running with `docker ps`
   - If WebSocket connections fail: Ensure proxy_wstunnel (Apache) or proper proxy headers (Nginx) are configured
   - For Caddy issues: Check logs with `journalctl -u caddy`
   - To test DNS propagation: Use `dig +short your-domain.com` or online tools like dnschecker.org

## Cleanup

1. **Removing a Project**
   - Use `./supascale.sh remove <project_id>` to remove project from configuration
   - Note: This doesn't delete project files or Docker containers
   - To clean up Docker containers: `docker container prune`
   - To completely remove a project, manually delete the project directory

## License

GPL V3 License - Copyright (c) 2025 Frog Byte, LLC

## Acknowledgments

- Original development by Frog Byte, LLC
- Built on top of [Supabase](https://supabase.com/) 
