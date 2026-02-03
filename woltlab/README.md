# WoltLab Sync Endpoint

PHP script that receives location updates from Discourse and writes them to WoltLab.

See the [main plugin README](../README.md#woltlab-integration) for full documentation.

## Quick Setup

1. **Deploy:**
   ```bash
   cp sync_location.php /var/www/forum/html/vzekc/
   ```

2. **Configure secret** in `sync_location.php`:
   ```php
   define('DISCOURSE_SYNC_SECRET', 'your-64-char-hex-secret');
   ```

   Generate with: `openssl rand -hex 32`

3. **Configure Discourse** (Admin > Settings > vzekc_map):
   - `vzekc_map_woltlab_sync_enabled`: true
   - `vzekc_map_woltlab_sync_url`: `https://forum.vzekc.de/vzekc/sync_location.php`
   - `vzekc_map_woltlab_sync_secret`: same as step 2

## Testing

```bash
http POST https://forum.vzekc.de/vzekc/sync_location.php \
  X-Sync-Secret:your-secret \
  username=hans \
  geoinformation='geo:52.52,13.40?z=15'
```

## Configuration

The script loads database credentials from WoltLab's `../config.inc.php`.

| Constant | Value | Description |
|----------|-------|-------------|
| `DB_PREFIX` | `wcf3_` | WoltLab table prefix |
| `GEO_COLUMN` | `userOption47` | Column storing Geoinformation |
