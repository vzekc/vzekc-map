<?php
/**
 * WoltLab Location Sync Endpoint
 *
 * Receives location updates from Discourse and writes them directly to WoltLab.
 *
 * Deploy to: /var/www/forum/html/vzekc/sync_location.php
 *
 * Configure Discourse with:
 *   - vzekc_map_woltlab_sync_url: https://forum.example.com/vzekc/sync_location.php
 *   - vzekc_map_woltlab_sync_secret: (same secret as DISCOURSE_SYNC_SECRET below)
 */

// Shared secret for API authentication
define('DISCOURSE_SYNC_SECRET', '1f26f80a359ed4e6d81a03b13098b5a573e977897b78ab99de23198566e5dd08');

// Load WoltLab database configuration
require_once __DIR__ . '/../config.inc.php';

// WoltLab uses wcf3_ prefix for this installation
define('DB_PREFIX', 'wcf3_');

// The Geoinformation field is stored in userOption47
// (determined from wcf3_user_option WHERE optionName = 'Geoinformation')
define('GEO_COLUMN', 'userOption47');

// ============================================================================
// MAIN SCRIPT
// ============================================================================

header('Content-Type: application/json; charset=utf-8');

// Only accept POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['error' => 'Method not allowed']));
}

// Validate the secret key
$headers = [];
foreach (getallheaders() as $key => $value) {
    $headers[strtolower($key)] = $value;
}

$providedSecret = $headers['x-sync-secret'] ?? '';

// Also check JSON body for secret (fallback)
$input = json_decode(file_get_contents('php://input'), true);
if (empty($providedSecret) && is_array($input)) {
    $providedSecret = $input['secret'] ?? '';
}

if (!hash_equals(DISCOURSE_SYNC_SECRET, $providedSecret)) {
    http_response_code(403);
    error_log("WoltLab sync: Invalid secret from " . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
    exit(json_encode(['error' => 'Unauthorized']));
}

// Validate input
if (!is_array($input)) {
    http_response_code(400);
    exit(json_encode(['error' => 'Invalid JSON body']));
}

$username = trim($input['username'] ?? '');
$geoinformation = $input['geoinformation'] ?? '';

if (empty($username)) {
    http_response_code(400);
    exit(json_encode(['error' => 'Missing username']));
}

// Database operations using WoltLab's config variables
try {
    $dsn = sprintf(
        "mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4",
        $dbHost,
        $dbPort ?: 3306,
        $dbName
    );

    $pdo = new PDO($dsn, $dbUser, $dbPassword, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);

    // Find user by username
    $stmt = $pdo->prepare(
        "SELECT userID FROM " . DB_PREFIX . "user WHERE username = ?"
    );
    $stmt->execute([$username]);
    $user = $stmt->fetch();

    if (!$user) {
        http_response_code(404);
        exit(json_encode([
            'error' => 'User not found',
            'username' => $username
        ]));
    }

    $userId = (int)$user['userID'];

    // Update the user's Geoinformation using INSERT ... ON DUPLICATE KEY UPDATE
    $sql = "INSERT INTO " . DB_PREFIX . "user_option_value (userID, " . GEO_COLUMN . ")
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE " . GEO_COLUMN . " = VALUES(" . GEO_COLUMN . ")";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([$userId, $geoinformation]);

    // Log success
    error_log(sprintf(
        "WoltLab sync: Updated Geoinformation for user %s (ID: %d)",
        $username,
        $userId
    ));

    echo json_encode([
        'success' => true,
        'user_id' => $userId,
        'username' => $username,
    ]);

} catch (PDOException $e) {
    error_log("WoltLab sync database error: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode(['error' => 'Database error']));
}
