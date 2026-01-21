<?php
/**
 * Get User API
 * Returns authenticated user info from Cloudflare Access
 * Also checks IP whitelist for manual login bypass
 *
 * USAGE: Fetch this endpoint from JavaScript to get the current user
 * Response: { ok: true, email: "...", name: "...", auth_method: "...", ip_whitelisted: bool, client_ip: "..." }
 */

header('Content-Type: application/json');

// ==================== CONFIGURATION ====================
// Path to SQLite database (will be created if doesn't exist)
$dbFile = __DIR__ . '/app.db';
// ==================== END CONFIGURATION ====================

// Initialize auth tables if needed
function initAuthTables($db) {
    $db->exec("CREATE TABLE IF NOT EXISTS ip_whitelist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ip_address TEXT UNIQUE NOT NULL,
        description TEXT,
        added_by TEXT,
        added_at TEXT DEFAULT CURRENT_TIMESTAMP
    )");

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
}

// Get client IP (handles proxies)
function getClientIP() {
    // Cloudflare provides the real IP in this header
    if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        return $_SERVER['HTTP_CF_CONNECTING_IP'];
    }
    // Fallback to X-Forwarded-For
    if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
        return trim($ips[0]);
    }
    // Fallback to X-Real-IP
    if (!empty($_SERVER['HTTP_X_REAL_IP'])) {
        return $_SERVER['HTTP_X_REAL_IP'];
    }
    // Default
    return $_SERVER['REMOTE_ADDR'] ?? 'unknown';
}

// Check if IP is whitelisted
function isIPWhitelisted($db, $ip) {
    try {
        $stmt = $db->prepare("SELECT COUNT(*) FROM ip_whitelist WHERE ip_address = ?");
        $stmt->execute([$ip]);
        return $stmt->fetchColumn() > 0;
    } catch (Exception $e) {
        return false;
    }
}

// Get email from Cloudflare
$email = '';
$authMethod = 'none';

// Method 1: Cloudflare Access HTTP Header (preferred)
if (!empty($_SERVER['HTTP_CF_ACCESS_AUTHENTICATED_USER_EMAIL'])) {
    $email = $_SERVER['HTTP_CF_ACCESS_AUTHENTICATED_USER_EMAIL'];
    $authMethod = 'cloudflare_header';
}

// Method 2: CF_Authorization Cookie (JWT fallback)
if (empty($email) && !empty($_COOKIE['CF_Authorization'])) {
    $parts = explode('.', $_COOKIE['CF_Authorization']);
    if (count($parts) === 3) {
        $payload = json_decode(base64_decode(strtr($parts[1], '-_', '+/')), true);
        $email = $payload['email'] ?? '';
        if ($email) {
            $authMethod = 'cloudflare_jwt';
        }
    }
}

// Derive name from email (john.smith@company.com -> John Smith)
$name = '';
if ($email) {
    $local = explode('@', $email)[0];
    $parts = explode('.', str_replace('_', '.', $local));
    $name = implode(' ', array_map('ucfirst', $parts));
}

// Connect to database and check IP whitelist
$ipWhitelisted = false;
$clientIP = getClientIP();

try {
    $db = new PDO("sqlite:$dbFile");
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $db->exec("PRAGMA busy_timeout = 10000");
    $db->exec("PRAGMA journal_mode = WAL");
    initAuthTables($db);

    $ipWhitelisted = isIPWhitelisted($db, $clientIP);
} catch (Exception $e) {
    // Continue without database - fail open for IP whitelist
}

echo json_encode([
    'ok' => true,
    'email' => $email,
    'name' => $name,
    'auth_method' => $authMethod,
    'ip_whitelisted' => $ipWhitelisted,
    'client_ip' => $clientIP
]);
