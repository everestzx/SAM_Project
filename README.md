# ARALert Scripts

ARALert includes six Bash administration scripts for installing and operating the application on Ubuntu or WSL. The scripts require `sudo` unless they are invoked with `--help`.

## Layout

```text
scripts/    Administrative scripts
man/        Unix manual page
samples/    Sanitized test-data output
```

## Requirements

- Ubuntu or WSL with `systemd`
- `sudo` privileges
- Bash
- PostgreSQL, Python 3, Nginx, Gunicorn, and required build packages

The install script can install missing operating-system packages. It configures PostgreSQL, a Python virtual environment, Gunicorn, systemd, and Nginx.

## Scripts

### `aralert-install.sh`

Installs and configures ARALert.

```bash
sudo scripts/aralert-install.sh [SOURCE_DIR]
```

`SOURCE_DIR` is the application source directory. It defaults to the repository root relative to the scripts directory. The script:

- Creates `/etc/aralert/aralert.conf` with mode `600`
- Generates database and secret values for a new installation
- Installs missing packages
- Creates the `aralert` service account
- Creates or updates the PostgreSQL database and user
- Copies the application to `/opt/aralert`
- Creates `/opt/aralert/backend/.env`
- Creates the Python virtual environment and runs migrations and seeding
- Configures the `aralert` systemd service and Nginx
- Verifies the backend health endpoint and frontend HTTP response

### `aralert-maintenance.sh`

Toggles maintenance mode or reports the current state.

```bash
sudo scripts/aralert-maintenance.sh --on
sudo scripts/aralert-maintenance.sh --off
sudo scripts/aralert-maintenance.sh --status
```

- `--on`: Creates the maintenance flag and verifies HTTP `503`
- `--off`: Removes the maintenance flag and verifies HTTP `200`
- `--status`: Reports whether maintenance mode is enabled

### `aralert-pause.sh`

Suspends or resumes processes owned by the `aralert` account.

```bash
sudo scripts/aralert-pause.sh --pause
sudo scripts/aralert-pause.sh --resume
sudo scripts/aralert-pause.sh --status
```

- `--pause`: Sends `SIGSTOP` to the processes
- `--resume`: Sends `SIGCONT` to the processes
- `--status`: Displays process IDs, states, and commands

### `aralert-start-stop.sh`

Controls PostgreSQL, ARALert, and Nginx in dependency order.

```bash
sudo scripts/aralert-start-stop.sh --start
sudo scripts/aralert-start-stop.sh --stop
sudo scripts/aralert-start-stop.sh --restart
```

- `--start`: Starts PostgreSQL, ARALert, and Nginx, then checks backend health
- `--stop`: Resumes paused processes, stops Nginx, ARALert, and PostgreSQL, and removes the Gunicorn PID file
- `--restart`: Stops all services in reverse order and starts them again

### `aralert-status.sh`

Displays an operational status report.

```bash
sudo scripts/aralert-status.sh
sudo scripts/aralert-status.sh --save FILE
```

The report includes service state, listening ports, process CPU and memory usage, system resources, maintenance mode, and backend health.

`--save FILE` or `-o FILE` writes the report to a file, displays it, and sets the file mode to `640`.

### `aralert-update.sh`

Backs up and updates an installed ARALert deployment.

```bash
sudo scripts/aralert-update.sh UPDATE_DIR
sudo scripts/aralert-update.sh --simulate-broken
```

The update script:

- Creates an application archive under `/var/backups/aralert`
- Creates a PostgreSQL SQL dump
- Verifies the archive and SQL dump
- Copies files from `UPDATE_DIR` into `/opt/aralert`
- Preserves the installed `.env` file
- Restarts the ARALert service and checks backend health

If health verification fails, the script stops the service and prints a manual restore command. `--simulate-broken` is a controlled failure demonstration that modifies the application URL module and does not accept an update directory.

## Help

Every script supports `--help` or `-h`:

```bash
bash scripts/aralert-install.sh --help
bash scripts/aralert-maintenance.sh --help
bash scripts/aralert-pause.sh --help
bash scripts/aralert-start-stop.sh --help
bash scripts/aralert-status.sh --help
bash scripts/aralert-update.sh --help
```

## Manual Page

Open the local manual page with:

```bash
man ./man/aralert.1
```

## Protected Paths

- `/etc/aralert/aralert.conf`: installation configuration; mode `600`
- `/opt/aralert`: installed application
- `/var/backups/aralert`: database dumps and pre-update archives
- `/opt/aralert/backend/.env`: service environment file; mode `600`

Keep credentials and database dumps private. The scripts generate the installation database password and secret key rather than storing them directly in the script source.

## Sample Output

Only sanitized test-data output belongs in [samples/](samples/). Do not add real passwords, private keys, API keys, database dumps, client records, personal data, or identifying hostnames.
