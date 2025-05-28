# Commands

`echo "action" | nc localhost 8020`

## Valid commands

All commands except `info_dump` return 200 as an output.

- `info_dump`: returns info about the app
- `alert_message <message>`: shows an alert on the screen