# vps_vps_backup.sh

A quick and dirty backup script for saving my VPS. Creates compressed tar backups of specified directories with automatic rotation to save disk space.

> **Note:** This script was created with assistance from [aider.chat](https://github.com/Aider-AI/aider/).

## Features

- Backs up multiple directories into a single compressed tar.gz archive
- Automatic backup rotation - keeps only the N most recent backups
- Creates timestamped backup directories for easy identification
- Uses fast compression (gzip -1) to minimize backup time
- Requires sudo access for creating and managing backups in `/backups`

## Requirements

- zsh shell
- sudo access
- tar with gzip support

## Usage

Basic usage - backup directories with default settings (keeps last 2 backups):

```bash
sudo ./vps_backup.sh /home/user /etc /var/www
```

Specify how many backups to keep:

```bash
sudo ./vps_backup.sh --keep-n 5 /home/user /etc
```

Specify a custom output directory:

```bash
sudo ./vps_backup.sh --outdir /custom/backup/location /home/user /etc
```

Combine options:

```bash
sudo ./vps_backup.sh --keep-n 3 --outdir /mnt/external/backups /home/user /etc /var/www
```

## Default Behavior

- **Output directory**: `/backups/YYYY-MM-DD_HH-MM-SS` (timestamped)
- **Backup retention**: Keeps the last 2 backups, removes older ones
- **Compression**: Uses gzip with level 1 (fast compression, larger files)
- **Permissions**: Requires sudo to create `/backups` directory and write backups

## How It Works

1. Validates sudo access
2. Creates `/backups` directory if it doesn't exist
3. Creates a timestamped subdirectory (or uses custom `--outdir`)
4. Creates a single `backup.tar.gz` containing all specified directories
5. Cleans up old backups, keeping only the N most recent backup directories

## Warning

This is a quick and dirty script designed for simple VPS backups. For production environments or critical data, consider more robust backup solutions with features like incremental backups, encryption, remote storage, and monitoring.
