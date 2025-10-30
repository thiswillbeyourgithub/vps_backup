#!/usr/bin/env zsh

# Backup script - creates compressed tar backups of specified directories
# Usage: backup.sh [--keep-n N] [--outdir DIR] dir1 [dir2 ...]

# Check for sudo access early - required for creating /backups and writing to it
if ! sudo -v; then
    echo "Error: This script requires sudo access" >&2
    exit 1
fi

# Default values
keep_n=2
outdir=""

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-n)
            if [[ -z "$2" ]] || [[ "$2" =~ ^- ]]; then
                echo "Error: --keep-n requires a numeric argument" >&2
                exit 1
            fi
            keep_n="$2"
            shift 2
            ;;
        --outdir)
            if [[ -z "$2" ]] || [[ "$2" =~ ^- ]]; then
                echo "Error: --outdir requires a directory argument" >&2
                exit 1
            fi
            outdir="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--keep-n N] [--outdir DIR] dir1 [dir2 ...]" >&2
            exit 1
            ;;
        *)
            # No more flags, remaining are positional arguments
            break
            ;;
    esac
done

# Set default outdir if not specified - human readable date format
if [[ -z "$outdir" ]]; then
    outdir="/backups/$(date +%Y-%m-%d_%H-%M-%S)"
fi

# Remaining arguments are directories to backup
declare -a directories=("$@")

# Validate that we have directories to backup
if [[ ${#directories[@]} -eq 0 ]]; then
    echo "Error: No directories specified for backup" >&2
    echo "Usage: $0 [--keep-n N] [--outdir DIR] dir1 [dir2 ...]" >&2
    exit 1
fi

# Create /backups directory if it doesn't exist
if [[ ! -d "/backups" ]]; then
    echo "Creating /backups directory..."
    sudo mkdir -p /backups || {
        echo "Error: Failed to create /backups directory" >&2
        exit 1
    }
fi

# Create output directory
echo "Creating backup directory: $outdir"
sudo mkdir -p "$outdir" || {
    echo "Error: Failed to create output directory $outdir" >&2
    exit 1
}

# Backup each directory with quick compression (gzip level 1)
for dir in "${directories[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "Warning: Directory '$dir' does not exist, skipping..." >&2
        continue
    fi
    
    # Get basename for the tar file
    dir_basename=$(basename "$dir")
    tarfile="$outdir/${dir_basename}.tar.gz"
    
    echo "Backing up $dir to $tarfile..."
    # Quick compression with gzip -1 for speed
    GZIP=-1 sudo tar -czf "$tarfile" -C "$(dirname "$dir")" "$(basename "$dir")" || {
        echo "Warning: Failed to backup $dir" >&2
    }
done

# Clean up old backups - keep only the last n backups in /backups
# List all directories in /backups (excluding /backups itself), sorted by modification time
echo "Checking for old backups to clean up..."
backup_dirs=($(sudo find /backups -maxdepth 1 -type d ! -path /backups -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-))

if [[ ${#backup_dirs[@]} -gt $keep_n ]]; then
    echo "Found ${#backup_dirs[@]} backups, keeping last $keep_n..."
    # Remove backups beyond keep_n (arrays in zsh are 1-indexed by default)
    for ((i=$((keep_n+1)); i<=${#backup_dirs[@]}; i++)); do
        old_backup="${backup_dirs[$i]}"
        echo "Removing old backup: $old_backup"
        sudo rm -rf "$old_backup" || {
            echo "Warning: Failed to remove $old_backup" >&2
        }
    done
else
    echo "Found ${#backup_dirs[@]} backups, no cleanup needed (keeping last $keep_n)"
fi

echo "Backup complete: $outdir"
