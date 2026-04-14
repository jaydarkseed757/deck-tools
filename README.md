# deck-tools
my simple steam deck tools to do some task that annoy me

---

## shader_cache_report.sh

Shows shader cache and Proton compatdata usage on your Steam Deck — internal storage and SD card — with game name resolution from installed app manifests.

### Usage

```
./shader_cache_report.sh [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--clean` | Scan for orphaned cache entries (no matching installed game) and interactively offer to delete them |
| `--csv` | Export the full report as CSV (`type,location,appid,name,size_bytes`) — suitable for piping or saving to a file |
| `--game <name>` | Look up cache usage for a specific game by name (partial, case-insensitive match) |
| `--json` | Export the full report as JSON — suitable for piping or processing with other tools |
| `--nosd` | Skip SD card storage scan |
| `--top <N>` | Show top N entries per section (default: 10) |
| `--warn-at <size>` | Print a warning if total cache usage exceeds the given size (e.g. `20G`, `500M`, `1.5T`) |
| `--help` | Show usage information |

### Examples

```bash
# Full report
./shader_cache_report.sh

# Skip SD card
./shader_cache_report.sh --nosd

# Show top 5 entries per section
./shader_cache_report.sh --top 5

# Look up a specific game
./shader_cache_report.sh --game "Elden Ring"

# Find and clean up orphaned cache entries
./shader_cache_report.sh --clean

# Warn if total cache exceeds 20GB
./shader_cache_report.sh --warn-at 20G

# Export to CSV
./shader_cache_report.sh --csv > cache.csv

# Export to JSON
./shader_cache_report.sh --json > cache.json

# Combine flags
./shader_cache_report.sh --nosd --csv > internal_only.csv
```

### Source

https://github.com/jaydarkseed757/deck-tools
