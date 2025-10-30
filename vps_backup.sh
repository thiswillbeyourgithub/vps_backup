#!/usr/bin/env zsh

# Backup script - creates compressed tar backups of specified directories
# Usage: vps_backup.sh [-v|--verbose] [--keep-n N] [--outdir DIR] dir1 [dir2 ...]

# Check for sudo access early - required for creating /backups and writing to it
if ! sudo -v; then
    echo "Error: This script requires sudo access" >&2
    exit 1
fi

# Default values
keep_n=2
outdir=""
verbose=false

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            verbose=true
            shift
            ;;
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
            echo "Usage: $0 [-v|--verbose] [--keep-n N] [--outdir DIR] dir1 [dir2 ...]" >&2
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
    echo "Usage: $0 [-v|--verbose] [--keep-n N] [--outdir DIR] dir1 [dir2 ...]" >&2
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

# Filter out non-existent directories
valid_dirs=()
for dir in "${directories[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "Warning: Directory '$dir' does not exist, skipping..." >&2
    else
        valid_dirs+=("$dir")
    fi
done

# Check if we have any valid directories to backup
if [[ ${#valid_dirs[@]} -eq 0 ]]; then
    echo "Error: No valid directories to backup" >&2
    exit 1
fi

# Create a single tar file containing all directories with timestamp
# Use _pending suffix during creation to indicate incomplete backup
timestamp=$(date +%Y-%m-%d_%H-%M-%S)
tarfile_pending="$outdir/backup_${timestamp}_pending.tar.gz"
tarfile="$outdir/backup_${timestamp}.tar.gz"
echo "Backing up ${#valid_dirs[@]} directories to $tarfile_pending..."
echo "Directories: ${valid_dirs[@]}"

# Quick compression with gzip -1 for speed
# Add verbose flag if requested to show progress
tar_opts="-czf"
if [[ "$verbose" == "true" ]]; then
    tar_opts="-cvzf"
fi
# tar exit codes: 0=success, 1=some files differed (e.g., changed during read), 2=fatal error
# We accept exit code 1 as it's common for active files to change during backup
GZIP=-1 sudo tar $tar_opts "$tarfile_pending" "${valid_dirs[@]}"
tar_exit=$?
if [[ $tar_exit -eq 2 ]]; then
    echo "Error: Fatal error during backup" >&2
    exit 1
elif [[ $tar_exit -eq 1 ]]; then
    echo "Warning: Some files changed during backup, but backup completed" >&2
fi

# Rename to remove _pending suffix on successful completion
echo "Finalizing backup..."
sudo mv "$tarfile_pending" "$tarfile" || {
    echo "Error: Failed to finalize backup (rename from pending)" >&2
    exit 1
}

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
