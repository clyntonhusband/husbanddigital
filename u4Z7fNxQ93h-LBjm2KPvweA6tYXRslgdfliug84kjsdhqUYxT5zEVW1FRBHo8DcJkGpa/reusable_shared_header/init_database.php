<?php
/**
 * Database Initialization Script
 * Run this once to create all required tables
 *
 * USAGE:
 *   php init_database.php
 *   OR visit in browser: https://yoursite.com/init_database.php
 */

header('Content-Type: text/plain');

// ==================== CONFIGURATION ====================
$dbFile = __DIR__ . '/app.db';
// ==================== END CONFIGURATION ====================

echo "=== Database Initialization ===\n\n";

try {
    $db = new PDO("sqlite:$dbFile");
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $db->exec("PRAGMA busy_timeout = 10000");
    $db->exec("PRAGMA journal_mode = WAL");

    echo "Connected to database: $dbFile\n\n";

    // Create ip_whitelist table
    echo "Creating ip_whitelist table... ";
    $db->exec("CREATE TABLE IF NOT EXISTS ip_whitelist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ip_address TEXT UNIQUE NOT NULL,
        description TEXT,
        added_by TEXT,
        added_at TEXT DEFAULT CURRENT_TIMESTAMP
    )");
    echo "OK\n";

    // Create login_log table
    echo "Creating login_log table... ";
    $db->exec("CREATE TABLE IF NOT EXISTS login_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT,
        name TEXT,
        ip_address TEXT,
        user_agent TEXT,
        auth_method TEXT,
        success INTEGER DEFAULT 1,
        failure_reason TEXT,
        logged_at TEXT DEFAULT CURRENT_TIMESTAMP
    )");
    echo "OK\n";

    // Create indexes for login_log
    echo "Creating login_log indexes... ";
    $db->exec("CREATE INDEX IF NOT EXISTS idx_login_log_date ON login_log(logged_at DESC)");
    $db->exec("CREATE INDEX IF NOT EXISTS idx_login_log_email ON login_log(email)");
    echo "OK\n";

    // Create app_settings table
    echo "Creating app_settings table... ";
    $db->exec("CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    )");
    echo "OK\n";

    // Create change_log table (for tracking user actions)
    echo "Creating change_log table... ";
    $db->exec("CREATE TABLE IF NOT EXISTS change_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        jobid TEXT,
        field TEXT,
        old_value TEXT,
        new_value TEXT,
        name TEXT,
        email TEXT,
        timestamp TEXT DEFAULT CURRENT_TIMESTAMP
    )");
    echo "OK\n";

    // Create change_log indexes
    echo "Creating change_log indexes... ";
    $db->exec("CREATE INDEX IF NOT EXISTS idx_change_log_timestamp ON change_log(timestamp DESC)");
    $db->exec("CREATE INDEX IF NOT EXISTS idx_change_log_name ON change_log(name)");
    echo "OK\n";

    echo "\n=== Database initialized successfully! ===\n";

    // List all tables
    echo "\nTables in database:\n";
    $stmt = $db->query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
    $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
    foreach ($tables as $table) {
        echo "  - $table\n";
    }

    echo "\n";
    echo "Database size: " . formatBytes(filesize($dbFile)) . "\n";

} catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
    exit(1);
}

function formatBytes($bytes) {
    if ($bytes >= 1073741824) {
        return round($bytes / 1073741824, 2) . ' GB';
    } elseif ($bytes >= 1048576) {
        return round($bytes / 1048576, 2) . ' MB';
    } elseif ($bytes >= 1024) {
        return round($bytes / 1024, 2) . ' KB';
    } else {
        return $bytes . ' bytes';
    }
}
