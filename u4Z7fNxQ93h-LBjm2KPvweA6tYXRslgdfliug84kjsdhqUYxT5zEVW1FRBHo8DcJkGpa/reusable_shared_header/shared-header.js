// Shared Header Component - Reusable Authentication & Navigation
// Include with: <script src="shared-header.js"></script>
// Then call: initSharedHeader('pageName', 'Page Title') where pageName matches the nav link id

(function() {
  // ==================== CONFIGURATION - CUSTOMIZE FOR YOUR PROJECT ====================

  // Navigation links - customize this array for your project
  // Set restricted: true for admin-only links
  const NAV_LINKS = [
    { href: 'index.html', label: 'Home', id: 'index' },
    { href: 'dashboard.html', label: 'Dashboard', id: 'dashboard' },
    { href: 'admin_tools.html', label: 'Admin Tools', id: 'admin', restricted: true }
  ];

  // Users who can see restricted links (matched by name)
  const ADMIN_USERS = ['Admin User'];

  // Project name displayed in header
  const PROJECT_NAME = 'My Project';

  // API endpoints - update paths if your file structure is different
  const API_ENDPOINTS = {
    getUser: 'get_user.php',
    authApi: 'auth_api.php',
    settingsApi: 'settings_api.php'
  };

  // ==================== END CONFIGURATION ====================

  // CSS styles for header
  const HEADER_STYLES = `
    .sh-nav { display: flex; gap: 4px; padding: 8px 10px; background: #111823; border-bottom: 1px solid #1d2a3a; flex-wrap: wrap; align-items: center; position: fixed; top: 0; left: 0; right: 0; z-index: 1000; }
    body { padding-top: 45px; }
    .sh-nav a { padding: 5px 10px; border-radius: 5px; font-size: 10px; text-decoration: none; color: #93a4b8; background: #182337; border: 1px solid #1d2a3a; transition: all 0.15s; }
    .sh-nav a:hover { border-color: #4da3ff; color: #e7eef8; }
    .sh-nav a.active { background: #0f2440; border-color: #1b3c66; color: #4da3ff; }
    .sh-nav-spacer { flex: 1; }
    .sh-nav-title { font-size: 13px; font-weight: 600; color: #e7eef8; padding: 0 20px; }
    .sh-nav-right { display: flex; align-items: center; gap: 8px; font-size: 10px; color: #93a4b8; margin-left: auto; }
    .sh-user-name { color: #1dd1a1; font-weight: 500; }
    .sh-nav button { padding: 3px 8px; font-size: 10px; cursor: pointer; background: #182337; color: #e7eef8; border: 1px solid #1d2a3a; border-radius: 4px; }
    .sh-nav button:hover { border-color: #4da3ff; }
  `;

  // Cookie helpers
  function getCookie(n) {
    const m = document.cookie.match(new RegExp('(^| )' + n + '=([^;]+)'));
    return m ? decodeURIComponent(m[2]) : '';
  }

  function setCookie(n, v, d = 365) {
    document.cookie = `${n}=${encodeURIComponent(v)};path=/;max-age=${d * 86400}`;
  }

  // Clear all auth cookies (including Cloudflare)
  function clearAllAuthCookies() {
    setCookie('reviewerName', '', 0);
    setCookie('reviewerEmail', '', 0);
    document.cookie = 'CF_Authorization=;path=/;max-age=0';
    document.cookie = 'CF_Authorization=;path=/;max-age=0;domain=' + window.location.hostname;
  }

  // Get current user from cookies
  function getCurrentUser() {
    return {
      name: getCookie('reviewerName') || '',
      email: getCookie('reviewerEmail') || ''
    };
  }

  // Auth state - will be populated by get_user.php
  let authState = {
    cfEmail: '',
    cfName: '',
    authMethod: 'none',
    ipWhitelisted: false,
    clientIP: ''
  };

  // Log authentication to server
  async function logAuthToServer(email, name, method, success = true, failureReason = null) {
    try {
      await fetch(API_ENDPOINTS.authApi + '?action=log_auth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, name, method, success, failure_reason: failureReason })
      });
    } catch (e) {
      console.error('Failed to log auth:', e);
    }
  }

  // Fetch authentication state from server
  async function fetchAuthState() {
    try {
      const res = await fetch(API_ENDPOINTS.getUser);
      const data = await res.json();
      if (data.ok) {
        authState.cfEmail = data.email || '';
        authState.cfName = data.name || '';
        authState.authMethod = data.auth_method || 'none';
        authState.ipWhitelisted = data.ip_whitelisted || false;
        authState.clientIP = data.client_ip || '';
      }
    } catch (e) {
      console.error('Failed to fetch auth state:', e);
    }
    return authState;
  }

  // Login modal HTML - only shown for IP whitelisted users
  function getLoginModalHTML() {
    return `
      <div class="sh-modal-bg hidden" id="shLoginModal">
        <div class="sh-modal">
          <h2>Login</h2>
          <p style="font-size: 11px; color: #93a4b8; margin: 0 0 12px 0;">IP Whitelisted - Manual login allowed</p>
          <input type="text" id="shLoginName" placeholder="Name">
          <input type="email" id="shLoginEmail" placeholder="Email">
          <button class="sh-btn" id="shLoginSubmit">Login</button>
        </div>
      </div>
      <div class="sh-modal-bg hidden" id="shAuthErrorModal">
        <div class="sh-modal" style="max-width: 350px;">
          <h2 style="color: #ff5a5f;">Authentication Required</h2>
          <p style="font-size: 12px; color: #93a4b8; margin: 0 0 16px 0; line-height: 1.5;">
            Please close this browser tab and access the site again to authenticate through the secure login system.
          </p>
          <button class="sh-btn" id="shAuthErrorClose" style="background: #2e0a0a; border-color: #661b1b; color: #ff5a5f;">Clear Session & Reload</button>
        </div>
      </div>
      <style>
        .sh-modal-bg { position: fixed; inset: 0; background: rgba(0,0,0,0.7); display: flex; align-items: center; justify-content: center; z-index: 9999; }
        .sh-modal-bg.hidden { display: none; }
        .sh-modal { background: #111823; border: 1px solid #1d2a3a; border-radius: 8px; padding: 16px; width: 90%; max-width: 300px; }
        .sh-modal h2 { font-size: 14px; margin: 0 0 12px 0; color: #e7eef8; }
        .sh-modal input { width: 100%; padding: 8px; margin-bottom: 8px; background: #0c121b; color: #e7eef8; border: 1px solid #1d2a3a; border-radius: 4px; box-sizing: border-box; }
        .sh-modal .sh-btn { width: 100%; padding: 8px; background: #0f2440; color: #e7eef8; border: 1px solid #1b3c66; border-radius: 4px; cursor: pointer; }
      </style>
    `;
  }

  // Main init function - returns user synchronously, updates async
  window.initSharedHeader = function(activePageId, pageTitle) {
    // Inject styles
    const styleEl = document.createElement('style');
    styleEl.textContent = HEADER_STYLES;
    document.head.appendChild(styleEl);

    // Get user from cookies immediately (synchronous)
    let user = getCurrentUser();
    let showLoginBtn = !user.name;

    const isAdmin = ADMIN_USERS.includes(user.name);

    // Async: Fetch auth state and update if needed
    fetchAuthState().then(() => {
      let needsUpdate = false;

      if (authState.cfEmail) {
        // Cloudflare authenticated - use Cloudflare identity
        if (user.email !== authState.cfEmail || user.name !== authState.cfName) {
          user.email = authState.cfEmail;
          user.name = authState.cfName;
          // Store in cookies for convenience
          setCookie('reviewerName', user.name);
          setCookie('reviewerEmail', user.email);
          needsUpdate = true;
        }
        // Log the authentication (only once per session)
        const loggedKey = 'auth_logged_' + authState.cfEmail;
        if (!sessionStorage.getItem(loggedKey)) {
          logAuthToServer(authState.cfEmail, authState.cfName, authState.authMethod);
          sessionStorage.setItem(loggedKey, '1');
        }
        // Hide login button since we have Cloudflare auth
        const loginBtn = document.getElementById('shLoginBtn');
        if (loginBtn) loginBtn.style.display = 'none';
      } else if (authState.ipWhitelisted) {
        // IP whitelisted - show login button if not logged in
        const loginBtn = document.getElementById('shLoginBtn');
        if (loginBtn && !user.name) loginBtn.style.display = '';
      } else if (!authState.cfEmail && !authState.ipWhitelisted) {
        // Not authenticated and not IP whitelisted
        const cookieUser = getCurrentUser();
        if (cookieUser.name) {
          // Has cookies but no Cloudflare auth - might be stale
          const loginBtn = document.getElementById('shLoginBtn');
          if (loginBtn) loginBtn.style.display = 'none';
        }
      }

      // Update UI if user changed
      if (needsUpdate) {
        const userNameEl = document.getElementById('shUserName');
        if (userNameEl) userNameEl.textContent = user.name || '-';
        // Dispatch event so pages can update
        window.dispatchEvent(new CustomEvent('userLogin', { detail: { name: user.name, email: user.email } }));
      }
    }).catch(err => {
      console.error('Auth state fetch failed:', err);
    });

    // Build nav HTML (filter restricted links for non-admin users)
    const navHTML = NAV_LINKS
      .filter(link => !link.restricted || isAdmin)
      .map(link =>
        `<a href="${link.href}"${link.id === activePageId ? ' class="active"' : ''}>${link.label}</a>`
      ).join('');

    // Build single-line header
    const headerHTML = `
      <nav class="sh-nav">
        ${navHTML}
        <span class="sh-nav-spacer"></span>
        <span class="sh-nav-title">${pageTitle || PROJECT_NAME}</span>
        <span class="sh-nav-spacer"></span>
        <div class="sh-nav-right">
          <span>User: <span class="sh-user-name" id="shUserName">${user.name || '-'}</span></span>
          <button id="shLoginBtn" style="${showLoginBtn ? '' : 'display:none'}">Login</button>
        </div>
      </nav>
    `;

    // Find or create header container
    let container = document.getElementById('shared-header');
    if (!container) {
      container = document.createElement('div');
      container.id = 'shared-header';
      document.body.insertBefore(container, document.body.firstChild);
    }
    container.innerHTML = headerHTML + getLoginModalHTML();

    // Attach event listeners - Login only for IP whitelisted users
    document.getElementById('shLoginBtn').onclick = () => {
      if (!authState.ipWhitelisted) {
        document.getElementById('shAuthErrorModal').classList.remove('hidden');
        return;
      }
      document.getElementById('shLoginModal').classList.remove('hidden');
    };

    document.getElementById('shLoginModal').onclick = (e) => {
      if (e.target.id === 'shLoginModal') {
        e.target.classList.add('hidden');
      }
    };

    document.getElementById('shLoginSubmit').onclick = () => {
      const name = document.getElementById('shLoginName').value.trim();
      const email = document.getElementById('shLoginEmail').value.trim();
      if (!name || !email) return alert('Enter name and email');

      // Validate email format
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return alert('Please enter a valid email address');
      }

      setCookie('reviewerName', name);
      setCookie('reviewerEmail', email);
      document.getElementById('shUserName').textContent = name;
      document.getElementById('shLoginBtn').style.display = 'none';
      document.getElementById('shLoginModal').classList.add('hidden');

      // Log manual login
      logAuthToServer(email, name, 'manual_ip_whitelist');

      // Dispatch event for page-specific handling
      window.dispatchEvent(new CustomEvent('userLogin', { detail: { name, email } }));
    };

    // Auth error modal - clear session and reload
    document.getElementById('shAuthErrorClose').onclick = () => {
      clearAllAuthCookies();
      sessionStorage.clear();
      window.location.reload();
    };

    document.getElementById('shAuthErrorModal').onclick = (e) => {
      if (e.target.id === 'shAuthErrorModal') {
        e.target.classList.add('hidden');
      }
    };

    // Return user for convenience
    return user;
  };

  // Helper to get current user (can be called anytime)
  window.getSharedUser = function() {
    return getCurrentUser();
  };

  // Helper to get auth state (can be called anytime)
  window.getAuthState = function() {
    return authState;
  };

  // Helper to show auth required modal
  window.showAuthRequired = function() {
    if (authState.ipWhitelisted) {
      document.getElementById('shLoginModal').classList.remove('hidden');
    } else {
      document.getElementById('shAuthErrorModal').classList.remove('hidden');
    }
  };

  // Date formatting utilities
  window.fmtDateShort = function(dateStr) {
    if (!dateStr || dateStr === '-') return '-';
    try {
      const d = new Date(dateStr.replace(' ', 'T'));
      if (isNaN(d.getTime())) return dateStr.substring(0, 10);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return `${d.getDate()} ${months[d.getMonth()]}`;
    } catch(e) {
      return dateStr.substring(0, 10);
    }
  };

  window.fmtDateFull = function(dateStr) {
    if (!dateStr || dateStr === '-') return '-';
    try {
      const d = new Date(dateStr.replace(' ', 'T'));
      if (isNaN(d.getTime())) return dateStr;
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const day = d.getDate();
      const month = months[d.getMonth()];
      const year = d.getFullYear();
      let hours = d.getHours();
      const mins = String(d.getMinutes()).padStart(2, '0');
      const ampm = hours >= 12 ? 'PM' : 'AM';
      hours = hours % 12 || 12;
      return `${day} ${month} ${year}, ${hours}:${mins} ${ampm}`;
    } catch(e) {
      return dateStr;
    }
  };
})();
