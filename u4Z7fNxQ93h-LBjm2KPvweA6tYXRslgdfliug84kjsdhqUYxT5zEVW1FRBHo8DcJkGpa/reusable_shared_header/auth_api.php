<?php
/**
 * Authentication API
 * Manages IP whitelist and login logging for Cloudflare authentication
 *
 * ENDPOINTS:
 *   ?action=check_ip      - Check if current IP is whitelisted
 *   ?action=get_whitelist - Get all whitelisted IPs (admin)
 *   ?action=add_ip        - Add IP to whitelist (admin)
 *   ?action=remove_ip     - Remove IP from whitelist (admin)
 *   ?action=log_auth      - Log an authentication attempt
 *   ?action=get_logs      - Get login logs with pagination
 *   ?action=clear_logs    - Clear old logs
 */

header('Content-Type: application/json');

// ==================== CONFIGURATION ====================
$dbFile = __DIR__ . '/app.db';
// ==================== END CONFIGURATION ====================

// Initialize auth tables if needed
function initAuthTables($db) {
    // IP whitelist table
    $db->exec("CREATE TABLE IF NOT EXISTS ip_whitelist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ip_address TEXT UNIQUE NOT NULL,
        description TEXT,
        added_by TEXT,
        added_at TEXT DEFAULT CURRENT_TIMESTAMP
    )");

    // Login log table
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

    // Create indexes for faster lookups
    $db->exec("CREATE INDEX IF NOT EXISTS idx_login_log_date ON login_log(logged_at DESC)");
    $db->exec("CREATE INDEX IF NOT EXISTS idx_login_log_email ON login_log(email)");
}

// Get client IP (handles proxies)
function getClientIP() {
    if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        return $_SERVER['HTTP_CF_CONNECTING_IP'];
    }
    if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
        return trim($ips[0]);
    }
    if (!empty($_SERVER['HTTP_X_REAL_IP'])) {
        return $_SERVER['HTTP_X_REAL_IP'];
    }
    return $_SERVER['REMOTE_ADDR'] ?? 'unknown';
}

// Check if IP is whitelisted
function isIPWhitelisted($db, $ip) {
    $stmt = $db->prepare("SELECT COUNT(*) FROM ip_whitelist WHERE ip_address = ?");
    $stmt->execute([$ip]);
    return $stmt->fetchColumn() > 0;
}

// Log an authentication event
function logAuth($db, $email, $name, $authMethod, $success = true, $failureReason = null) {
    $stmt = $db->prepare("INSERT INTO login_log (email, name, ip_address, user_agent, auth_method, success, failure_reason, logged_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))");
    return $stmt->execute([
        $email,
        $name,
        getClientIP(),
        $_SERVER['HTTP_USER_AGENT'] ?? 'unknown',
        $authMethod,
        $success ? 1 : 0,
        $failureReason
    ]);
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    $db = new PDO("sqlite:$dbFile");
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $db->exec("PRAGMA busy_timeout = 10000");
    $db->exec("PRAGMA journal_mode = WAL");
    initAuthTables($db);

    switch ($action) {
        case 'check_ip':
            // Check if current IP is whitelisted
            $ip = getClientIP();
            $whitelisted = isIPWhitelisted($db, $ip);
            echo json_encode([
                'ok' => true,
                'ip' => $ip,
                'whitelisted' => $whitelisted
            ]);
            break;

        case 'get_whitelist':
            // Get all whitelisted IPs
            $stmt = $db->query("SELECT id, ip_address, description, added_by, added_at FROM ip_whitelist ORDER BY added_at DESC");
            $ips = $stmt->fetchAll(PDO::FETCH_ASSOC);
            echo json_encode(['ok' => true, 'ips' => $ips]);
            break;

        case 'add_ip':
            // Add IP to whitelist
            $input = json_decode(file_get_contents('php://input'), true);
            $ip = trim($input['ip_address'] ?? '');
            $desc = trim($input['description'] ?? '');
            $addedBy = trim($input['added_by'] ?? 'admin');

            if (empty($ip)) {
                echo json_encode(['ok' => false, 'error' => 'IP address is required']);
                exit;
            }

            // Validate IP format (IPv4 or IPv6)
            if (!filter_var($ip, FILTER_VALIDATE_IP)) {
                echo json_encode(['ok' => false, 'error' => 'Invalid IP address format']);
                exit;
            }

            $stmt = $db->prepare("INSERT OR REPLACE INTO ip_whitelist (ip_address, description, added_by, added_at) VALUES (?, ?, ?, datetime('now'))");
            $stmt->execute([$ip, $desc, $addedBy]);

            echo json_encode(['ok' => true, 'message' => 'IP added to whitelist']);
            break;

        case 'remove_ip':
            // Remove IP from whitelist
            $input = json_decode(file_get_contents('php://input'), true);
            $id = intval($input['id'] ?? 0);

            if ($id <= 0) {
                echo json_encode(['ok' => false, 'error' => 'Invalid ID']);
                exit;
            }

            $stmt = $db->prepare("DELETE FROM ip_whitelist WHERE id = ?");
            $stmt->execute([$id]);

            echo json_encode(['ok' => true, 'message' => 'IP removed from whitelist']);
            break;

        case 'log_auth':
            // Log an authentication attempt
            $input = json_decode(file_get_contents('php://input'), true);
            $email = trim($input['email'] ?? '');
            $name = trim($input['name'] ?? '');
            $method = trim($input['method'] ?? 'unknown');
            $success = $input['success'] ?? true;
            $failureReason = $input['failure_reason'] ?? null;

            logAuth($db, $email, $name, $method, $success, $failureReason);
            echo json_encode(['ok' => true]);
            break;

        case 'get_logs':
            // Get login logs with pagination
            $limit = min(intval($_GET['limit'] ?? 100), 500);
            $offset = max(intval($_GET['offset'] ?? 0), 0);

            // Get total count
            $countStmt = $db->query("SELECT COUNT(*) FROM login_log");
            $total = $countStmt->fetchColumn();

            // Get logs
            $stmt = $db->prepare("SELECT id, email, name, ip_address, user_agent, auth_method, success, failure_reason, logged_at FROM login_log ORDER BY logged_at DESC LIMIT ? OFFSET ?");
            $stmt->execute([$limit, $offset]);
            $logs = $stmt->fetchAll(PDO::FETCH_ASSOC);

            echo json_encode([
                'ok' => true,
                'logs' => $logs,
                'total' => $total,
                'limit' => $limit,
                'offset' => $offset
            ]);
            break;

        case 'clear_logs':
            // Clear old logs (keep last N days)
            $days = intval($_GET['days'] ?? 30);
            $stmt = $db->prepare("DELETE FROM login_log WHERE logged_at < datetime('now', '-' || ? || ' days')");
            $stmt->execute([$days]);
            $deleted = $db->query("SELECT changes()")->fetchColumn();
            echo json_encode(['ok' => true, 'deleted' => $deleted]);
            break;

        default:
            echo json_encode(['ok' => false, 'error' => 'Unknown action']);
    }
} catch (Exception $e) {
    echo json_encode(['ok' => false, 'error' => $e->getMessage()]);
}
