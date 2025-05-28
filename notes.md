# What to change for version updates

- server/localpkg.cjs > version (for backend updates)
- app/lib/main.dart > version (for frontent updates) (make sure to rebuild the app using `homebuildall` after this change)
- config.json > version (for configuration updates)

# spotifyd

Statuses:

- 0: No players found
- 1: Playing
- 2: Paused

# Server Arguments

- `--override-verify`

# App Commands

- Run an app command: `echo "action" | nc localhost 8020 || echo '{"error": "unavailable"}'`