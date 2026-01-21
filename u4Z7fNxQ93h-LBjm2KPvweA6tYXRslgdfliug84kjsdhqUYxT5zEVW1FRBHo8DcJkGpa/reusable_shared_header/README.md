# Reusable Shared Header with Cloudflare Authentication

A complete, ready-to-use authentication and navigation component for web applications. Features Cloudflare Access integration, IP whitelist bypass, admin tools, and a consistent dark-themed UI.

## Quick Start

### 1. Copy Files to Your Project

Copy all files from this folder to your project root.

### 2. Initialize the Database

Run the initialization script to create required tables:

```bash
php init_database.php
```

Or visit in browser: `https://yoursite.com/init_database.php`

### 3. Configure Navigation

Edit `shared-header.js` and customize the configuration section at the top:

```javascript
// Navigation links - customize for your project
const NAV_LINKS = [
  { href: 'index.html', label: 'Home', id: 'index' },
  { href: 'dashboard.html', label: 'Dashboard', id: 'dashboard' },
  { href: 'reports.html', label: 'Reports', id: 'reports' },
  { href: 'admin_tools.html', label: 'Admin', id: 'admin', restricted: true }
];

// Users who can see restricted links (matched by name)
const ADMIN_USERS = ['Your Name Here'];

// Project name displayed in header
const PROJECT_NAME = 'My Project';
```

### 4. Add to Your Pages

Include the header on any HTML page:

```html
<!DOCTYPE html>
<html>
<head>
  <script src="shared-header.js"></script>
</head>
<body>
  <div id="shared-header"></div>
  <script>
    const user = initSharedHeader('mypage', 'My Page Title');
  </script>

  <!-- Your page content here -->
</body>
</html>
```

## Files Included

| File | Purpose |
|------|---------|
| `shared-header.js` | Navigation bar, user management, authentication UI |
| `get_user.php` | Cloudflare authentication endpoint |
| `auth_api.php` | IP whitelist and login logging API |
| `settings_api.php` | Application settings storage API |
| `admin_tools.html` | Example admin dashboard page |
| `admin_tools_api.php` | Admin tools preview/execute API |
| `init_database.php` | Database initialization script |
| `example.html` | Demo page showing implementation |
| `README.md` | This documentation |

## Features

### Authentication Flow

1. **Cloudflare Access** (Primary): When behind Cloudflare Access, user email is automatically extracted from headers
2. **IP Whitelist**: Specific IPs can bypass Cloudflare and use manual login
3. **Cookie Persistence**: User info stored in cookies for session continuity

### Navigation

- Fixed header with responsive navigation links
- Admin-only restricted links (based on username)
- Active page highlighting
- Dark theme styling

### Admin Tools Pattern

Safe preview-then-execute pattern for admin operations:
1. Click "Preview" to see what changes will be made
2. Review affected records
3. Click "Execute" to apply changes

### Available APIs

**get_user.php** - Returns current user info:
```javascript
fetch('get_user.php')
  .then(r => r.json())
  .then(data => console.log(data));
// { ok: true, email: "...", name: "...", auth_method: "...", ip_whitelisted: bool }
```

**auth_api.php** - Manage IP whitelist:
```javascript
// Check current IP
fetch('auth_api.php?action=check_ip')

// Get whitelist
fetch('auth_api.php?action=get_whitelist')

// Add IP
fetch('auth_api.php?action=add_ip', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ ip_address: '1.2.3.4', description: 'Office' })
})
```

**settings_api.php** - Store application settings:
```javascript
// Get settings
fetch('settings_api.php?action=get')

// Set settings
fetch('settings_api.php?action=set', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ theme: 'dark', language: 'en' })
})
```

## JavaScript Helpers

After initializing the header, these global functions are available:

```javascript
// Get current user
const user = window.getSharedUser();
// Returns: { name: "...", email: "..." }

// Get authentication state
const auth = window.getAuthState();
// Returns: { cfEmail, cfName, authMethod, ipWhitelisted, clientIP }

// Show login/auth required modal
window.showAuthRequired();

// Format dates
window.fmtDateShort('2026-01-21');  // "21 Jan"
window.fmtDateFull('2026-01-21 14:30:00');  // "21 Jan 2026, 2:30 PM"
```

## Events

Listen for user login events:

```javascript
window.addEventListener('userLogin', (e) => {
  console.log('User logged in:', e.detail.name, e.detail.email);
  // Update your page UI here
});
```

## Adding Admin Tools

To add a new admin tool, edit `admin_tools_api.php`:

1. Add preview function:
```php
function previewMyTool($db) {
    // Query data to preview
    echo json_encode([
        'tool' => 'my_tool',
        'description' => 'What this tool does',
        'totalAffected' => $count,
        'samples' => $samples
    ]);
}
```

2. Add execute function:
```php
function executeMyTool($db) {
    // Perform changes
    echo json_encode([
        'success' => true,
        'message' => 'Done!',
        'updated' => $count
    ]);
}
```

3. Register in switch statements and add UI card in `admin_tools.html`.

## Cloudflare Access Setup

For Cloudflare Access authentication:

1. Configure Cloudflare Access for your domain
2. Add an Access policy requiring authentication
3. The `CF-Access-Authenticated-User-Email` header will be set automatically
4. `get_user.php` reads this header to identify users

## Security Notes

- Cloudflare Access is the primary security layer
- IP whitelist is for development/testing convenience only
- Admin tools UI filtering is client-side only - add server-side checks for sensitive operations
- All login attempts are logged in the database

## Database

Uses SQLite for simplicity. Tables created by `init_database.php`:

- `ip_whitelist` - Whitelisted IP addresses
- `login_log` - Authentication log
- `app_settings` - Key-value settings storage
- `change_log` - Track data changes by user

Database file: `app.db` (created in same directory)

## Styling

The header uses a dark theme with these colors:
- Background: `#111823`
- Border: `#1d2a3a`
- Accent: `#4da3ff` (blue)
- Success: `#1dd1a1` (green)
- Error: `#ff5a5f` (red)
- Warning: `#f7b731` (yellow)
- Text: `#e7eef8`
- Muted: `#93a4b8`

## License

Free to use and modify for any project.
