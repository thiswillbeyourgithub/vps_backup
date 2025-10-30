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

# Validate that all directories exist - crash if any directory is missing
for dir in "${directories[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "Error: Directory '$dir' does not exist" >&2
        exit 1
    fi
done

# Create a single tar file containing all directories with timestamp
# Use _pending suffix during creation to indicate incomplete backup
timestamp=$(date +%Y-%m-%d_%H-%M-%S)
tarfile_pending="$outdir/backup_${timestamp}_pending.tar.gz"
tarfile="$outdir/backup_${timestamp}.tar.gz"
echo "Backing up ${#directories[@]} directories to $tarfile_pending..."
echo "Directories: ${directories[@]}"

# Create compressed tar backup
# Add verbose flag if requested to show progress
tar_opts="-czf"
if [[ "$verbose" == "true" ]]; then
    tar_opts="-cvzf"
fi
# tar exit codes: 0=success, 1=some files differed (e.g., changed during read), 2=fatal error
# We accept exit code 1 as it's common for active files to change during backup
sudo tar $tar_opts "$tarfile_pending" "${directories[@]}"
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

# Clean up any pending (incomplete) backups first
echo "Cleaning up any incomplete backups..."
pending_files=($(sudo find /backups -name '*_pending.tar.gz' 2>/dev/null))
if [[ ${#pending_files[@]} -gt 0 ]]; then
    for pending in "${pending_files[@]}"; do
        echo "Removing incomplete backup: $pending"
        sudo rm -f "$pending" || {
            echo "Warning: Failed to remove $pending" >&2
        }
    done
else
    echo "No incomplete backups found"
fi

# Clean up old backups - keep only the last n backups in /backups
# List all items (directories and .tar.gz files) in /backups, sorted by modification time
# This handles both subdirectory-based backups (default) and direct .tar.gz backups (--outdir /backups)
echo "Checking for old backups to clean up..."
backup_items=($(sudo find /backups -mindepth 1 -maxdepth 1 \( -type d -o -name '*.tar.gz' \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-))

if [[ ${#backup_items[@]} -gt $keep_n ]]; then
    echo "Found ${#backup_items[@]} backups, keeping last $keep_n..."
    # Remove backups beyond keep_n (arrays in zsh are 1-indexed by default)
    for ((i=$((keep_n+1)); i<=${#backup_items[@]}; i++)); do
        old_backup="${backup_items[$i]}"
        echo "Removing old backup: $old_backup"
        sudo rm -rf "$old_backup" || {
            echo "Warning: Failed to remove $old_backup" >&2
        }
    done
else
    echo "Found ${#backup_items[@]} backups, no cleanup needed (keeping last $keep_n)"
fi

echo "Backup complete: $outdir"
