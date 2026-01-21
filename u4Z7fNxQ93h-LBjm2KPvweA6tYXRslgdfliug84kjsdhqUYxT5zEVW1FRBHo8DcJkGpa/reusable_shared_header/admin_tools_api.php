<?php
/**
 * Admin Tools API
 * Provides preview and execute functionality for admin scripts
 * Follows the preview-then-execute pattern for safety
 *
 * ENDPOINTS:
 *   ?action=preview&tool=TOOL_ID - Preview what changes will be made
 *   ?action=execute&tool=TOOL_ID - Execute the changes
 *   ?action=list                  - List available tools
 *   ?action=system_status         - Get system status dashboard data
 *
 * HOW TO ADD A NEW TOOL:
 *   1. Add preview function: previewMyTool($db)
 *   2. Add execute function: executeMyTool($db)
 *   3. Register in handlePreview() and handleExecute() switch statements
 *   4. Add to listAvailableTools() if it should appear in admin UI
 */

header('Content-Type: application/json; charset=utf-8');

// ==================== CONFIGURATION ====================
$dbFile = __DIR__ . '/app.db';
// ==================== END CONFIGURATION ====================

if (!file_exists($dbFile)) {
    echo json_encode(['error' => 'Database not found. Run init_database.php first.']);
    exit;
}

try {
    $db = new PDO("sqlite:$dbFile");
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $db->exec("PRAGMA busy_timeout = 10000");
    $db->exec("PRAGMA journal_mode = WAL");
} catch (Exception $e) {
    echo json_encode(['error' => 'Database connection failed: ' . $e->getMessage()]);
    exit;
}

$action = $_GET['action'] ?? '';
$tool = $_GET['tool'] ?? '';

switch ($action) {
    case 'preview':
        handlePreview($db, $tool);
        break;
    case 'execute':
        handleExecute($db, $tool);
        break;
    case 'list':
        listAvailableTools();
        break;
    case 'system_status':
        getSystemStatus($db);
        break;
    default:
        echo json_encode(['error' => 'Invalid action. Use: preview, execute, list, or system_status']);
}

function handlePreview($db, $tool) {
    switch ($tool) {
        case 'clear_old_logs':
            previewClearOldLogs($db);
            break;
        case 'example_tool':
            previewExampleTool($db);
            break;
        default:
            echo json_encode(['error' => 'Unknown tool: ' . $tool]);
    }
}

function handleExecute($db, $tool) {
    switch ($tool) {
        case 'clear_old_logs':
            executeClearOldLogs($db);
            break;
        case 'example_tool':
            executeExampleTool($db);
            break;
        default:
            echo json_encode(['error' => 'Unknown tool: ' . $tool]);
    }
}

// ==================== EXAMPLE TOOL ====================
// This is a template - copy and modify for your own tools

function previewExampleTool($db) {
    // Query data to see what would be affected
    // In a real tool, this would query actual data

    $samples = [
        ['id' => 1, 'name' => 'Sample Item 1', 'status' => 'pending'],
        ['id' => 2, 'name' => 'Sample Item 2', 'status' => 'pending'],
    ];

    echo json_encode([
        'tool' => 'example_tool',
        'description' => 'This is an example tool template',
        'totalAffected' => count($samples),
        'samples' => $samples,
        'note' => 'This tool does not actually modify any data'
    ]);
}

function executeExampleTool($db) {
    // In a real tool, this would perform the actual changes
    // For this example, we just return a success message

    echo json_encode([
        'success' => true,
        'message' => 'Example tool executed successfully',
        'updated' => 0,
        'errors' => 0
    ]);
}

// ==================== CLEAR OLD LOGS TOOL ====================

function previewClearOldLogs($db) {
    $days = 30;

    // Count logs older than threshold
    $stmt = $db->prepare("SELECT COUNT(*) FROM login_log WHERE logged_at < datetime('now', '-' || ? || ' days')");
    $stmt->execute([$days]);
    $count = $stmt->fetchColumn();

    // Get sample of old logs
    $stmt = $db->prepare("SELECT id, email, ip_address, auth_method, logged_at FROM login_log WHERE logged_at < datetime('now', '-' || ? || ' days') ORDER BY logged_at DESC LIMIT 10");
    $stmt->execute([$days]);
    $samples = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'tool' => 'clear_old_logs',
        'description' => "Delete login logs older than $days days",
        'totalAffected' => (int)$count,
        'samples' => $samples,
        'note' => "Keeping the most recent $days days of login history"
    ]);
}

function executeClearOldLogs($db) {
    $days = 30;

    $stmt = $db->prepare("DELETE FROM login_log WHERE logged_at < datetime('now', '-' || ? || ' days')");
    $stmt->execute([$days]);
    $deleted = $db->query("SELECT changes()")->fetchColumn();

    echo json_encode([
        'success' => true,
        'message' => "Deleted $deleted old log entries",
        'updated' => (int)$deleted,
        'errors' => 0
    ]);
}

// ==================== TOOL LIST ====================

function listAvailableTools() {
    $tools = [
        [
            'id' => 'clear_old_logs',
            'name' => 'Clear Old Login Logs',
            'description' => 'Delete login logs older than 30 days',
            'type' => 'action',
            'hasPreview' => true
        ],
        [
            'id' => 'example_tool',
            'name' => 'Example Tool',
            'description' => 'Template tool for demonstration',
            'type' => 'action',
            'hasPreview' => true
        ]
    ];

    echo json_encode(['tools' => $tools]);
}

// ==================== SYSTEM STATUS ====================

function getSystemStatus($db) {
    $status = [
        'database' => [],
        'auth' => []
    ];

    try {
        // Database file size
        $dbFile = __DIR__ . '/app.db';
        if (file_exists($dbFile)) {
            $size = filesize($dbFile);
            if ($size >= 1073741824) {
                $status['database']['size'] = round($size / 1073741824, 2) . ' GB';
            } elseif ($size >= 1048576) {
                $status['database']['size'] = round($size / 1048576, 1) . ' MB';
            } else {
                $status['database']['size'] = round($size / 1024, 1) . ' KB';
            }
        }

        // Table counts
        $tables = ['ip_whitelist', 'login_log', 'app_settings', 'change_log'];
        foreach ($tables as $table) {
            try {
                $stmt = $db->query("SELECT COUNT(*) FROM $table");
                $status['database'][$table . '_count'] = (int)$stmt->fetchColumn();
            } catch (Exception $e) {
                $status['database'][$table . '_count'] = 'N/A';
            }
        }

        // Auth stats
        $stmt = $db->query("SELECT COUNT(DISTINCT email) FROM login_log WHERE success = 1");
        $status['auth']['unique_users'] = (int)$stmt->fetchColumn();

        $stmt = $db->query("SELECT COUNT(*) FROM login_log WHERE logged_at > datetime('now', '-24 hours')");
        $status['auth']['logins_24h'] = (int)$stmt->fetchColumn();

        $stmt = $db->query("SELECT COUNT(*) FROM ip_whitelist");
        $status['auth']['whitelisted_ips'] = (int)$stmt->fetchColumn();

    } catch (Exception $e) {
        $status['error'] = $e->getMessage();
    }

    echo json_encode($status);
}
