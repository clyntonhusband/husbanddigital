<?php
/**
 * Settings API
 * Manages application settings in SQLite database
 *
 * ENDPOINTS:
 *   ?action=get - Get all settings
 *   ?action=set - Set one or more settings (POST JSON)
 *
 * USAGE:
 *   // Get settings
 *   fetch('settings_api.php?action=get').then(r => r.json())
 *
 *   // Set settings
 *   fetch('settings_api.php?action=set', {
 *     method: 'POST',
 *     headers: { 'Content-Type': 'application/json' },
 *     body: JSON.stringify({ my_setting: 'value' })
 *   })
 */

header('Content-Type: application/json');

// ==================== CONFIGURATION ====================
$dbFile = __DIR__ . '/app.db';

// Define allowed settings with validation rules
// Add your own settings here
$ALLOWED_SETTINGS = [
    'theme' => ['type' => 'enum', 'values' => ['light', 'dark', 'auto'], 'default' => 'dark'],
    'language' => ['type' => 'string', 'default' => 'en'],
    'notifications_enabled' => ['type' => 'boolean', 'default' => true],
    // Add more settings as needed
];
// ==================== END CONFIGURATION ====================

// Initialize settings table if needed
function initSettingsTable($db) {
    $db->exec("CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    )");
}

// Get a setting
function getSetting($db, $key, $default = null) {
    $stmt = $db->prepare("SELECT value FROM app_settings WHERE key = ?");
    $stmt->execute([$key]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ? $row['value'] : $default;
}

// Set a setting
function setSetting($db, $key, $value) {
    $stmt = $db->prepare("INSERT OR REPLACE INTO app_settings (key, value, updated_at) VALUES (?, ?, datetime('now'))");
    return $stmt->execute([$key, $value]);
}

// Validate a setting value
function validateSetting($key, $value, $rules) {
    global $ALLOWED_SETTINGS;

    if (!isset($ALLOWED_SETTINGS[$key])) {
        return ['valid' => false, 'error' => "Unknown setting: $key"];
    }

    $rule = $ALLOWED_SETTINGS[$key];

    switch ($rule['type']) {
        case 'enum':
            if (!in_array($value, $rule['values'])) {
                return ['valid' => false, 'error' => "$key must be one of: " . implode(', ', $rule['values'])];
            }
            break;
        case 'boolean':
            if (!is_bool($value) && $value !== 'true' && $value !== 'false' && $value !== '1' && $value !== '0') {
                return ['valid' => false, 'error' => "$key must be a boolean"];
            }
            break;
        case 'string':
            if (!is_string($value)) {
                return ['valid' => false, 'error' => "$key must be a string"];
            }
            break;
        case 'integer':
            if (!is_numeric($value)) {
                return ['valid' => false, 'error' => "$key must be an integer"];
            }
            break;
    }

    return ['valid' => true];
}

$action = $_GET['action'] ?? $_POST['action'] ?? 'get';

try {
    $db = new PDO("sqlite:$dbFile");
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $db->exec("PRAGMA busy_timeout = 10000");
    $db->exec("PRAGMA journal_mode = WAL");
    initSettingsTable($db);

    switch ($action) {
        case 'get':
            // Get all configured settings with their values or defaults
            $settings = [];
            foreach ($ALLOWED_SETTINGS as $key => $rule) {
                $settings[$key] = getSetting($db, $key, $rule['default']);
            }
            echo json_encode(['ok' => true, 'settings' => $settings]);
            break;

        case 'set':
            // Get JSON input
            $input = json_decode(file_get_contents('php://input'), true);
            if (!$input) {
                $input = $_POST;
            }

            $updated = false;
            $settings = [];
            $errors = [];

            foreach ($input as $key => $value) {
                // Skip non-setting fields
                if ($key === 'action') continue;

                // Validate the setting
                $validation = validateSetting($key, $value, $ALLOWED_SETTINGS);
                if (!$validation['valid']) {
                    $errors[] = $validation['error'];
                    continue;
                }

                // Save the setting
                setSetting($db, $key, $value);
                $settings[$key] = $value;
                $updated = true;
            }

            if (count($errors) > 0) {
                echo json_encode(['ok' => false, 'errors' => $errors, 'settings' => $settings]);
            } elseif ($updated) {
                echo json_encode(['ok' => true, 'settings' => $settings]);
            } else {
                echo json_encode(['ok' => false, 'error' => 'No valid settings provided']);
            }
            break;

        default:
            echo json_encode(['ok' => false, 'error' => 'Unknown action. Use get or set']);
    }
} catch (Exception $e) {
    echo json_encode(['ok' => false, 'error' => $e->getMessage()]);
}
