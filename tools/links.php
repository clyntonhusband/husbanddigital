<?php
// links.php - Secure link manager with built-in authentication
session_start();

// ===== CONFIGURATION =====
define('PASSWORD', 'ChangeThisPassword2024!'); // CHANGE THIS!
define('SESSION_TIMEOUT', 1800); // 30 minutes
define('DATA_FILE', __DIR__ . '/links_data.json'); // Store in same directory
define('MAX_LOGIN_ATTEMPTS', 5);
define('LOCKOUT_TIME', 900); // 15 minutes

// ===== SECURITY FUNCTIONS =====
function isAuthenticated() {
    if (!isset($_SESSION['authenticated']) || $_SESSION['authenticated'] !== true) {
        return false;
    }
    
    // Check session timeout
    if (isset($_SESSION['last_activity']) && (time() - $_SESSION['last_activity'] > SESSION_TIMEOUT)) {
        session_unset();
        session_destroy();
        return false;
    }
    
    $_SESSION['last_activity'] = time();
    return true;
}

function checkLoginAttempts() {
    $ip = $_SERVER['REMOTE_ADDR'];
    $attempts_file = __DIR__ . '/login_attempts.json';
    $attempts = [];
    
    if (file_exists($attempts_file)) {
        $attempts = json_decode(file_get_contents($attempts_file), true) ?: [];
    }
    
    // Clean old attempts
    foreach ($attempts as $key => $data) {
        if (time() - $data['time'] > LOCKOUT_TIME) {
            unset($attempts[$key]);
        }
    }
    
    if (isset($attempts[$ip]) && $attempts[$ip]['count'] >= MAX_LOGIN_ATTEMPTS) {
        return false;
    }
    
    return true;
}

function recordLoginAttempt($success = false) {
    $ip = $_SERVER['REMOTE_ADDR'];
    $attempts_file = __DIR__ . '/login_attempts.json';
    $attempts = [];
    
    if (file_exists($attempts_file)) {
        $attempts = json_decode(file_get_contents($attempts_file), true) ?: [];
    }
    
    if ($success) {
        unset($attempts[$ip]);
    } else {
        if (!isset($attempts[$ip])) {
            $attempts[$ip] = ['count' => 0, 'time' => time()];
        }
        $attempts[$ip]['count']++;
        $attempts[$ip]['time'] = time();
    }
    
    file_put_contents($attempts_file, json_encode($attempts));
}

// ===== HANDLE AJAX REQUESTS =====
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    header('Content-Type: application/json');
    
    switch ($_POST['action']) {
        case 'login':
            if (!checkLoginAttempts()) {
                http_response_code(429);
                echo json_encode(['success' => false, 'error' => 'Too many login attempts. Please try again later.']);
                exit;
            }
            
            $password = $_POST['password'] ?? '';
            if ($password === PASSWORD) {
                $_SESSION['authenticated'] = true;
                $_SESSION['last_activity'] = time();
                recordLoginAttempt(true);
                echo json_encode(['success' => true]);
            } else {
                recordLoginAttempt(false);
                echo json_encode(['success' => false, 'error' => 'Invalid password']);
            }
            exit;
            
        case 'logout':
            session_unset();
            session_destroy();
            echo json_encode(['success' => true]);
            exit;
            
        case 'check_auth':
            echo json_encode(['authenticated' => isAuthenticated()]);
            exit;
    }
    
    // All other actions require authentication
    if (!isAuthenticated()) {
        http_response_code(401);
        echo json_encode(['error' => 'Not authenticated']);
        exit;
    }
    
    switch ($_POST['action']) {
        case 'get_links':
            $links = [];
            if (file_exists(DATA_FILE)) {
                $links = json_decode(file_get_contents(DATA_FILE), true) ?: [];
            }
            echo json_encode(['success' => true, 'links' => $links]);
            exit;
            
        case 'save_link':
            $links = [];
            if (file_exists(DATA_FILE)) {
                $links = json_decode(file_get_contents(DATA_FILE), true) ?: [];
            }
            
            $link = [
                'id' => $_POST['id'] ?? uniqid(),
                'title' => strip_tags($_POST['title'] ?? ''),
                'url' => filter_var($_POST['url'] ?? '', FILTER_SANITIZE_URL),
                'category' => strip_tags($_POST['category'] ?? 'Uncategorized'),
                'description' => strip_tags($_POST['description'] ?? ''),
                'created' => $_POST['created'] ?? date('Y-m-d H:i:s'),
                'updated' => date('Y-m-d H:i:s')
            ];
            
            // Validate URL
            if (!filter_var($link['url'], FILTER_VALIDATE_URL)) {
                echo json_encode(['success' => false, 'error' => 'Invalid URL']);
                exit;
            }
            
            // Update existing or add new
            $found = false;
            foreach ($links as &$existingLink) {
                if ($existingLink['id'] === $link['id']) {
                    $existingLink = $link;
                    $found = true;
                    break;
                }
            }
            
            if (!$found) {
                $links[] = $link;
            }
            
            file_put_contents(DATA_FILE, json_encode($links, JSON_PRETTY_PRINT));
            echo json_encode(['success' => true]);
            exit;
            
        case 'delete_link':
            $links = [];
            if (file_exists(DATA_FILE)) {
                $links = json_decode(file_get_contents(DATA_FILE), true) ?: [];
            }
            
            $id = $_POST['id'] ?? '';
            $links = array_values(array_filter($links, function($link) use ($id) {
                return $link['id'] !== $id;
            }));
            
            file_put_contents(DATA_FILE, json_encode($links, JSON_PRETTY_PRINT));
            echo json_encode(['success' => true]);
            exit;
            
        case 'export_links':
            $links = [];
            if (file_exists(DATA_FILE)) {
                $links = json_decode(file_get_contents(DATA_FILE), true) ?: [];
            }
            echo json_encode(['success' => true, 'links' => $links]);
            exit;
            
        case 'import_links':
            $imported = json_decode($_POST['data'] ?? '[]', true);
            if (is_array($imported)) {
                file_put_contents(DATA_FILE, json_encode($imported, JSON_PRETTY_PRINT));
                echo json_encode(['success' => true]);
            } else {
                echo json_encode(['success' => false, 'error' => 'Invalid data format']);
            }
            exit;
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="robots" content="noindex, nofollow">
    <title>Link Manager - Secure</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        :root {
            --primary: #1a1a2e;
            --accent: #16213e;
            --highlight: #0f4c75;
            --bright: #3282b8;
            --light: #bbe1fa;
            --white: #ffffff;
            --gray: #f5f5f7;
            --text: #333333;
            --text-light: #666666;
            --success: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
        }
        
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background-color: var(--gray);
            color: var(--text);
            line-height: 1.6;
            min-height: 100vh;
        }
        
        /* Login Screen */
        .login-container {
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            padding: 20px;
        }
        
        .login-box {
            background: var(--white);
            padding: 40px;
            border-radius: 16px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            width: 100%;
            max-width: 400px;
            text-align: center;
        }
        
        .login-box h1 {
            font-size: 28px;
            margin-bottom: 10px;
            color: var(--primary);
        }
        
        .login-box p {
            color: var(--text-light);
            margin-bottom: 30px;
        }
        
        .password-group {
            position: relative;
            margin-bottom: 20px;
        }
        
        .password-input {
            width: 100%;
            padding: 12px 16px;
            padding-right: 45px;
            font-size: 16px;
            border: 2px solid #e5e5e5;
            border-radius: 8px;
            transition: border-color 0.3s ease;
        }
        
        .password-input:focus {
            outline: none;
            border-color: var(--bright);
        }
        
        .password-toggle {
            position: absolute;
            right: 12px;
            top: 50%;
            transform: translateY(-50%);
            background: none;
            border: none;
            cursor: pointer;
            font-size: 18px;
            color: var(--text-light);
            padding: 5px;
        }
        
        .password-toggle:hover {
            color: var(--text);
        }
        
        .login-btn {
            width: 100%;
            padding: 12px 24px;
            background: var(--bright);
            color: var(--white);
            border: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        
        .login-btn:hover:not(:disabled) {
            background: var(--highlight);
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(50, 130, 184, 0.4);
        }
        
        .login-btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .error-message {
            color: var(--danger);
            font-size: 14px;
            margin-top: 10px;
            display: none;
        }
        
        .success-message {
            color: var(--success);
            font-size: 14px;
            margin-top: 10px;
            display: none;
        }
        
        /* Loading spinner */
        .spinner {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 0.8s ease-in-out infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        /* Main App */
        .app-container {
            display: none;
            min-height: 100vh;
        }
        
        /* Header */
        .header {
            background: var(--white);
            box-shadow: 0 2px 10px rgba(0,0,0,0.08);
            position: sticky;
            top: 0;
            z-index: 100;
        }
        
        .header-content {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 20px;
        }
        
        .header h1 {
            font-size: 24px;
            color: var(--primary);
        }
        
        .header-actions {
            display: flex;
            gap: 15px;
            align-items: center;
            flex-wrap: wrap;
        }
        
        .search-box {
            padding: 10px 16px;
            border: 1px solid #e5e5e5;
            border-radius: 8px;
            font-size: 14px;
            width: 250px;
            transition: all 0.3s ease;
        }
        
        .search-box:focus {
            outline: none;
            border-color: var(--bright);
            box-shadow: 0 0 0 3px rgba(50, 130, 184, 0.1);
        }
        
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            white-space: nowrap;
        }
        
        .btn-primary {
            background: var(--bright);
            color: var(--white);
        }
        
        .btn-primary:hover {
            background: var(--highlight);
            transform: translateY(-1px);
        }
        
        .btn-secondary {
            background: var(--gray);
            color: var(--text);
        }
        
        .btn-secondary:hover {
            background: #e5e5e5;
        }
        
        .btn-danger {
            background: var(--danger);
            color: var(--white);
        }
        
        .btn-danger:hover {
            background: #dc2626;
        }
        
        /* Main Content */
        .main-content {
            max-width: 1400px;
            margin: 0 auto;
            padding: 40px 20px;
        }
        
        /* Stats */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .stat-card {
            background: var(--white);
            padding: 20px;
            border-radius: 12px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        }
        
        .stat-card h3 {
            font-size: 14px;
            color: var(--text-light);
            margin-bottom: 5px;
        }
        
        .stat-card .stat-value {
            font-size: 28px;
            font-weight: 700;
            color: var(--primary);
        }
        
        /* Categories */
        .categories {
            display: flex;
            gap: 10px;
            margin-bottom: 30px;
            flex-wrap: wrap;
        }
        
        .category-tag {
            padding: 6px 16px;
            background: var(--white);
            border: 2px solid transparent;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        
        .category-tag:hover {
            border-color: var(--bright);
        }
        
        .category-tag.active {
            background: var(--bright);
            color: var(--white);
            border-color: var(--bright);
        }
        
        /* Links Grid */
        .links-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 20px;
        }
        
        .link-card {
            background: var(--white);
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }
        
        .link-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
        }
        
        .link-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            width: 4px;
            height: 100%;
            background: var(--bright);
            transform: scaleY(0);
            transition: transform 0.3s ease;
        }
        
        .link-card:hover::before {
            transform: scaleY(1);
        }
        
        .link-title {
            font-size: 18px;
            font-weight: 600;
            color: var(--primary);
            margin-bottom: 5px;
            word-break: break-word;
        }
        
        .link-url {
            color: var(--bright);
            text-decoration: none;
            font-size: 14px;
            word-break: break-all;
            display: block;
            margin-bottom: 10px;
        }
        
        .link-url:hover {
            text-decoration: underline;
        }
        
        .link-description {
            color: var(--text-light);
            font-size: 14px;
            line-height: 1.5;
            margin-bottom: 15px;
        }
        
        .link-footer {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 10px;
        }
        
        .link-category {
            display: inline-block;
            padding: 4px 12px;
            background: var(--gray);
            border-radius: 15px;
            font-size: 12px;
            font-weight: 500;
            color: var(--text);
        }
        
        .link-actions {
            display: flex;
            gap: 10px;
        }
        
        .link-actions button {
            padding: 6px 12px;
            border: none;
            background: none;
            color: var(--text-light);
            cursor: pointer;
            font-size: 14px;
            transition: color 0.3s ease;
        }
        
        .link-actions button:hover {
            color: var(--bright);
        }
        
        .link-actions button.delete:hover {
            color: var(--danger);
        }
        
        /* Modal */
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.5);
            z-index: 1000;
            padding: 20px;
            overflow-y: auto;
        }
        
        .modal-content {
            background: var(--white);
            max-width: 600px;
            margin: 50px auto;
            border-radius: 16px;
            padding: 30px;
            position: relative;
        }
        
        .modal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 25px;
        }
        
        .modal-header h2 {
            font-size: 24px;
            color: var(--primary);
        }
        
        .close-modal {
            background: none;
            border: none;
            font-size: 24px;
            color: var(--text-light);
            cursor: pointer;
            width: 32px;
            height: 32px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 8px;
            transition: all 0.3s ease;
        }
        
        .close-modal:hover {
            background: var(--gray);
            color: var(--text);
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            font-weight: 600;
            margin-bottom: 8px;
            color: var(--text);
        }
        
        .form-group input,
        .form-group textarea,
        .form-group select {
            width: 100%;
            padding: 10px 14px;
            border: 2px solid #e5e5e5;
            border-radius: 8px;
            font-size: 14px;
            font-family: inherit;
            transition: border-color 0.3s ease;
        }
        
        .form-group input:focus,
        .form-group textarea:focus,
        .form-group select:focus {
            outline: none;
            border-color: var(--bright);
        }
        
        .form-group textarea {
            resize: vertical;
            min-height: 80px;
        }
        
        .form-actions {
            display: flex;
            gap: 15px;
            justify-content: flex-end;
            margin-top: 30px;
        }
        
        /* Empty State */
        .empty-state {
            text-align: center;
            padding: 60px 20px;
        }
        
        .empty-state-icon {
            font-size: 48px;
            margin-bottom: 20px;
            opacity: 0.3;
        }
        
        .empty-state h3 {
            font-size: 20px;
            color: var(--text);
            margin-bottom: 10px;
        }
        
        .empty-state p {
            color: var(--text-light);
            margin-bottom: 20px;
        }
        
        /* Responsive */
        @media (max-width: 768px) {
            .header-content {
                flex-direction: column;
                align-items: stretch;
            }
            
            .header-actions {
                flex-direction: column;
                width: 100%;
            }
            
            .search-box {
                width: 100%;
            }
            
            .links-grid {
                grid-template-columns: 1fr;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
            
            .categories {
                overflow-x: auto;
                -webkit-overflow-scrolling: touch;
                padding-bottom: 10px;
            }
        }
        
        /* File input styling */
        .file-input-wrapper {
            position: relative;
            overflow: hidden;
            display: inline-block;
        }
        
        .file-input-wrapper input[type=file] {
            position: absolute;
            left: -9999px;
        }
        
        /* Toast notifications */
        .toast {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: var(--primary);
            color: var(--white);
            padding: 16px 24px;
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.2);
            display: none;
            animation: slideIn 0.3s ease;
        }
        
        .toast.success {
            background: var(--success);
        }
        
        .toast.error {
            background: var(--danger);
        }
        
        @keyframes slideIn {
            from {
                transform: translateX(100%);
                opacity: 0;
            }
            to {
                transform: translateX(0);
                opacity: 1;
            }
        }
    </style>
</head>
<body>
    <!-- Login Screen -->
    <div class="login-container" id="loginScreen">
        <div class="login-box">
            <h1>🔒 Link Manager</h1>
            <p>Secure access to your links</p>
            <form id="loginForm" onsubmit="handleLogin(event)">
                <div class="password-group">
                    <input type="password" class="password-input" id="passwordInput" 
                           placeholder="Enter password" autocomplete="off" required>
                    <button type="button" class="password-toggle" onclick="togglePassword()">👁️</button>
                </div>
                <button type="submit" class="login-btn" id="loginBtn">
                    <span id="loginBtnText">Access Links</span>
                </button>
                <div class="error-message" id="errorMessage"></div>
                <div class="success-message" id="successMessage"></div>
            </form>
        </div>
    </div>
    
    <!-- Main App -->
    <div class="app-container" id="appContainer">
        <!-- Header -->
        <header class="header">
            <div class="header-content">
                <h1>🔗 Link Manager</h1>
                <div class="header-actions">
                    <input type="text" class="search-box" id="searchBox" 
                           placeholder="Search links..." oninput="renderLinks()">
                    <button class="btn btn-primary" onclick="openAddModal()">
                        <span>+</span> Add Link
                    </button>
                    <button class="btn btn-secondary" onclick="exportLinks()">📥 Export</button>
                    <div class="file-input-wrapper">
                        <button class="btn btn-secondary">📤 Import</button>
                        <input type="file" accept=".json" onchange="importLinks(event)">
                    </div>
                    <button class="btn btn-secondary" onclick="logout()">Logout</button>
                </div>
            </div>
        </header>
        
        <!-- Main Content -->
        <main class="main-content">
            <!-- Stats -->
            <div class="stats-grid">
                <div class="stat-card">
                    <h3>Total Links</h3>
                    <div class="stat-value" id="totalLinks">0</div>
                </div>
                <div class="stat-card">
                    <h3>Categories</h3>
                    <div class="stat-value" id="totalCategories">0</div>
                </div>
                <div class="stat-card">
                    <h3>Last Updated</h3>
                    <div class="stat-value" id="lastUpdated">Never</div>
                </div>
            </div>
            
            <!-- Categories -->
            <div class="categories" id="categoriesContainer">
                <div class="category-tag active" onclick="filterByCategory('all')">All</div>
            </div>
            
            <!-- Links Grid -->
            <div class="links-grid" id="linksGrid">
                <!-- Links will be inserted here -->
            </div>
            
            <!-- Empty State -->
            <div class="empty-state" id="emptyState" style="display: none;">
                <div class="empty-state-icon">🔗</div>
                <h3>No links yet</h3>
                <p>Start building your link collection</p>
                <button class="btn btn-primary" onclick="openAddModal()">Add Your First Link</button>
            </div>
        </main>
    </div>
    
    <!-- Add/Edit Modal -->
    <div class="modal" id="linkModal">
        <div class="modal-content">
            <div class="modal-header">
                <h2 id="modalTitle">Add Link</h2>
                <button class="close-modal" onclick="closeModal()">✕</button>
            </div>
            <form id="linkForm" onsubmit="handleSubmit(event)">
                <div class="form-group">
                    <label for="linkTitle">Title *</label>
                    <input type="text" id="linkTitle" required>
                </div>
                <div class="form-group">
                    <label for="linkUrl">URL *</label>
                    <input type="url" id="linkUrl" required placeholder="https://example.com">
                </div>
                <div class="form-group">
                    <label for="linkCategory">Category</label>
                    <input type="text" id="linkCategory" 
                           placeholder="e.g., Resources, Tools, Documentation"
                           list="categoryList">
                    <datalist id="categoryList"></datalist>
                </div>
                <div class="form-group">
                    <label for="linkDescription">Description</label>
                    <textarea id="linkDescription" 
                              placeholder="Brief description of the link..."></textarea>
                </div>
                <div class="form-actions">
                    <button type="button" class="btn btn-secondary" onclick="closeModal()">Cancel</button>
                    <button type="submit" class="btn btn-primary">Save Link</button>
                </div>
            </form>
        </div>
    </div>
    
    <!-- Toast notification -->
    <div class="toast" id="toast"></div>
    
    <script>
        // State
        let links = [];
        let editingId = null;
        let currentCategory = 'all';
        
        // API Functions
        async function api(action, data = {}) {
            const formData = new FormData();
            formData.append('action', action);
            for (const key in data) {
                formData.append(key, data[key]);
            }
            
            try {
                const response = await fetch(window.location.href, {
                    method: 'POST',
                    body: formData
                });
                
                const result = await response.json();
                if (!response.ok || !result.success) {
                    throw new Error(result.error || 'Request failed');
                }
                return result;
            } catch (error) {
                showToast(error.message || 'An error occurred', 'error');
                throw error;
            }
        }
        
        // Authentication
        async function checkAuth() {
            try {
                const result = await api('check_auth');
                if (result.authenticated) {
                    showApp();
                }
            } catch (error) {
                console.error('Auth check failed');
            }
        }
        
        async function handleLogin(event) {
            event.preventDefault();
            
            const password = document.getElementById('passwordInput').value;
            const loginBtn = document.getElementById('loginBtn');
            const loginBtnText = document.getElementById('loginBtnText');
            
            loginBtn.disabled = true;
            loginBtnText.innerHTML = '<span class="spinner"></span> Logging in...';
            
            try {
                await api('login', { password });
                showToast('Login successful!', 'success');
                setTimeout(() => {
                    showApp();
                }, 500);
            } catch (error) {
                document.getElementById('errorMessage').textContent = error.message;
                document.getElementById('errorMessage').style.display = 'block';
                document.getElementById('passwordInput').value = '';
                document.getElementById('passwordInput').focus();
            } finally {
                loginBtn.disabled = false;
                loginBtnText.textContent = 'Access Links';
            }
        }
        
        function showApp() {
            document.getElementById('loginScreen').style.display = 'none';
            document.getElementById('appContainer').style.display = 'block';
            loadLinks();
        }
        
        async function logout() {
            try {
                await api('logout');
                location.reload();
            } catch (error) {
                console.error('Logout failed');
                location.reload();
            }
        }
        
        // Link Management
        async function loadLinks() {
            try {
                const result = await api('get_links');
                links = result.links || [];
                renderLinks();
                updateCategoryList();
            } catch (error) {
                console.error('Failed to load links');
            }
        }
        
        async function saveLink(linkData) {
            try {
                await api('save_link', linkData);
                await loadLinks();
                showToast('Link saved successfully!', 'success');
            } catch (error) {
                console.error('Failed to save link');
            }
        }
        
        async function deleteLink(id) {
            if (!confirm('Are you sure you want to delete this link?')) return;
            
            try {
                await api('delete_link', { id });
                await loadLinks();
                showToast('Link deleted', 'success');
            } catch (error) {
                console.error('Failed to delete link');
            }
        }
        
        // UI Functions
        function togglePassword() {
            const input = document.getElementById('passwordInput');
            const toggle = document.querySelector('.password-toggle');
            
            if (input.type === 'password') {
                input.type = 'text';
                toggle.textContent = '👁️‍🗨️';
            } else {
                input.type = 'password';
                toggle.textContent = '👁️';
            }
        }
        
        function openAddModal() {
            editingId = null;
            document.getElementById('modalTitle').textContent = 'Add Link';
            document.getElementById('linkForm').reset();
            document.getElementById('linkModal').style.display = 'block';
        }
        
        function openEditModal(id) {
            editingId = id;
            const link = links.find(l => l.id === id);
            if (link) {
                document.getElementById('modalTitle').textContent = 'Edit Link';
                document.getElementById('linkTitle').value = link.title;
                document.getElementById('linkUrl').value = link.url;
                document.getElementById('linkCategory').value = link.category || '';
                document.getElementById('linkDescription').value = link.description || '';
                document.getElementById('linkModal').style.display = 'block';
            }
        }
        
        function closeModal() {
            document.getElementById('linkModal').style.display = 'none';
            document.getElementById('linkForm').reset();
            editingId = null;
        }
        
        async function handleSubmit(event) {
            event.preventDefault();
            
            const linkData = {
                title: document.getElementById('linkTitle').value,
                url: document.getElementById('linkUrl').value,
                category: document.getElementById('linkCategory').value || 'Uncategorized',
                description: document.getElementById('linkDescription').value
            };
            
            if (editingId) {
                linkData.id = editingId;
                const existingLink = links.find(l => l.id === editingId);
                if (existingLink) {
                    linkData.created = existingLink.created;
                }
            }
            
            await saveLink(linkData);
            closeModal();
        }
        
        function filterByCategory(category) {
            currentCategory = category;
            
            document.querySelectorAll('.category-tag').forEach(tag => {
                tag.classList.remove('active');
            });
            event.target.classList.add('active');
            
            renderLinks();
        }
        
        function renderLinks() {
            const searchTerm = document.getElementById('searchBox').value.toLowerCase();
            
            // Filter links
            let filteredLinks = links;
            
            if (currentCategory !== 'all') {
                filteredLinks = filteredLinks.filter(link => link.category === currentCategory);
            }
            
            if (searchTerm) {
                filteredLinks = filteredLinks.filter(link => 
                    link.title.toLowerCase().includes(searchTerm) ||
                    link.url.toLowerCase().includes(searchTerm) ||
                    (link.description && link.description.toLowerCase().includes(searchTerm))
                );
            }
            
            // Update categories
            const categories = ['all', ...new Set(links.map(l => l.category))];
            const categoriesHtml = categories.map(cat => 
                `<div class="category-tag ${cat === currentCategory ? 'active' : ''}" 
                     onclick="filterByCategory('${cat}')">${cat === 'all' ? 'All' : cat}</div>`
            ).join('');
            document.getElementById('categoriesContainer').innerHTML = categoriesHtml;
            
            // Render links
            const linksGrid = document.getElementById('linksGrid');
            const emptyState = document.getElementById('emptyState');
            
            if (filteredLinks.length === 0) {
                linksGrid.style.display = 'none';
                emptyState.style.display = 'block';
            } else {
                linksGrid.style.display = 'grid';
                emptyState.style.display = 'none';
                
                linksGrid.innerHTML = filteredLinks.map(link => `
                    <div class="link-card">
                        <div class="link-title">${link.title}</div>
                        <a href="${link.url}" target="_blank" class="link-url">${link.url}</a>
                        ${link.description ? `<div class="link-description">${link.description}</div>` : ''}
                        <div class="link-footer">
                            <span class="link-category">${link.category}</span>
                            <div class="link-actions">
                                <button onclick="openEditModal('${link.id}')">Edit</button>
                                <button class="delete" onclick="deleteLink('${link.id}')">Delete</button>
                            </div>
                        </div>
                    </div>
                `).join('');
            }
            
            updateStats();
        }
        
        function updateStats() {
            document.getElementById('totalLinks').textContent = links.length;
            document.getElementById('totalCategories').textContent = 
                new Set(links.map(l => l.category)).size;
            
            // Get last updated date
            if (links.length > 0) {
                const dates = links.map(l => new Date(l.updated || l.created));
                const lastDate = new Date(Math.max(...dates));
                document.getElementById('lastUpdated').textContent = 
                    lastDate.toLocaleDateString();
            } else {
                document.getElementById('lastUpdated').textContent = 'Never';
            }
        }
        
        function updateCategoryList() {
            const categories = [...new Set(links.map(l => l.category))];
            const datalist = document.getElementById('categoryList');
            datalist.innerHTML = categories.map(cat => 
                `<option value="${cat}">`
            ).join('');
        }
        
        // Import/Export
        async function exportLinks() {
            try {
                const result = await api('export_links');
                const dataStr = JSON.stringify(result.links, null, 2);
                const dataUri = 'data:application/json;charset=utf-8,'+ 
                    encodeURIComponent(dataStr);
                
                const filename = `links-backup-${new Date().toISOString().split('T')[0]}.json`;
                
                const link = document.createElement('a');
                link.setAttribute('href', dataUri);
                link.setAttribute('download', filename);
                link.click();
                
                showToast('Links exported successfully!', 'success');
            } catch (error) {
                console.error('Export failed');
            }
        }
        
        async function importLinks(event) {
            const file = event.target.files[0];
            if (!file) return;
            
            const reader = new FileReader();
            reader.onload = async function(e) {
                try {
                    const imported = JSON.parse(e.target.result);
                    if (!Array.isArray(imported)) {
                        throw new Error('Invalid file format');
                    }
                    
                    await api('import_links', { data: JSON.stringify(imported) });
                    await loadLinks();
                    showToast('Links imported successfully!', 'success');
                } catch (error) {
                    showToast('Failed to import links. Check file format.', 'error');
                }
            };
            reader.readAsText(file);
            
            // Reset file input
            event.target.value = '';
        }
        
        // Utilities
        function showToast(message, type = 'success') {
            const toast = document.getElementById('toast');
            toast.textContent = message;
            toast.className = `toast ${type}`;
            toast.style.display = 'block';
            
            setTimeout(() => {
                toast.style.display = 'none';
            }, 3000);
        }
        
        // Modal close on outside click
        window.onclick = function(event) {
            const modal = document.getElementById('linkModal');
            if (event.target === modal) {
                closeModal();
            }
        }
        
        // Keyboard shortcuts
        document.addEventListener('keydown', function(e) {
            if (!document.getElementById('appContainer').style.display || 
                document.getElementById('appContainer').style.display === 'none') return;
            
            if (e.ctrlKey || e.metaKey) {
                switch(e.key) {
                    case 'n':
                        e.preventDefault();
                        openAddModal();
                        break;
                    case 's':
                        e.preventDefault();
                        exportLinks();
                        break;
                    case 'f':
                        e.preventDefault();
                        document.getElementById('searchBox').focus();
                        break;
                }
            }
            
            if (e.key === 'Escape') {
                closeModal();
            }
        });
        
        // Initialize
        document.addEventListener('DOMContentLoaded', function() {
            checkAuth();
            
            // Focus password input
            document.getElementById('passwordInput').focus();
        });
    </script>
</body>
</html>