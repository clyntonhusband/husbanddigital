// Mobile menu toggle
function toggleMobileMenu() {
    const navLinks = document.getElementById('navLinks');
    const menuBtn = document.querySelector('.mobile-menu-btn');
    navLinks.classList.toggle('active');
    menuBtn.classList.toggle('active');
}// Mobile menu toggle
function toggleMobileMenu() {
    const navLinks = document.getElementById('navLinks');
    const menuBtn = document.querySelector('.mobile-menu-btn');
    navLinks.classList.toggle('active');
    menuBtn.classList.toggle('active');
}

function closeMobileMenu() {
    const navLinks = document.getElementById('navLinks');
    const menuBtn = document.querySelector('.mobile-menu-btn');
    navLinks.classList.remove('active');
    menuBtn.classList.remove('active');
}

// Smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

// Basic protection against right-click
document.addEventListener('contextmenu', function(e) {
    e.preventDefault();
    return false;
});

// Basic protection against keyboard shortcuts
document.addEventListener('keydown', function(e) {
    // Disable F12
    if(e.keyCode === 123) {
        e.preventDefault();
        return false;
    }
    // Disable Ctrl+Shift+I
    if(e.ctrlKey && e.shiftKey && e.keyCode === 73) {
        e.preventDefault();
        return false;
    }
    // Disable Ctrl+Shift+C
    if(e.ctrlKey && e.shiftKey && e.keyCode === 67) {
        e.preventDefault();
        return false;
    }
    // Disable Ctrl+Shift+J
    if(e.ctrlKey && e.shiftKey && e.keyCode === 74) {
        e.preventDefault();
        return false;
    }
    // Disable Ctrl+U
    if(e.ctrlKey && e.keyCode === 85) {
        e.preventDefault();
        return false;
    }
});

// Console warning message
console.log('%cSTOP!', 'color: red; font-size: 50px; font-weight: bold;');
console.log('%cThis is a browser feature intended for developers. Content here is protected by copyright.', 'color: red; font-size: 16px;');

// Navbar scroll effect
let lastScroll = 0;
const navbar = document.querySelector('.navbar');

window.addEventListener('scroll', () => {
    const currentScroll = window.pageYOffset;
    
    if (currentScroll <= 0) {
        navbar.classList.remove('scroll-up');
        return;
    }
    
    if (currentScroll > lastScroll && !navbar.classList.contains('scroll-down')) {
        // Scroll down
        navbar.classList.remove('scroll-up');
        navbar.classList.add('scroll-down');
    } else if (currentScroll < lastScroll && navbar.classList.contains('scroll-down')) {
        // Scroll up
        navbar.classList.remove('scroll-down');
        navbar.classList.add('scroll-up');
    }
    
    lastScroll = currentScroll;
});

// Add animation on scroll
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver(function(entries) {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add('animate-in');
        }
    });
}, observerOptions);

// Observe all sections
document.querySelectorAll('section').forEach(section => {
    observer.observe(section);
});

// Form validation (if you add a contact form later)
function validateEmail(email) {
    const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return re.test(email);
}

// Analytics placeholder (replace with your actual analytics)
window.addEventListener('load', function() {
    // Google Analytics or other tracking code would go here
    console.log('Page loaded successfully');
});

function closeMobileMenu() {
    const navLinks = document.getElementById('navLinks');
    const menuBtn = document.querySelector('.mobile-menu-btn');
    navLinks.classList.remove('active');
    menuBtn.classList.remove('active');
}

// Smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

// Basic protection against right-click
document.addEventListener('contextmenu', function(e) {
    e.preventDefault();
    return false;
});

// Basic protection against keyboard shortcuts
document.addEventListener('keydown', function(e) {
    // Disable F12
    if(e.keyCode === 123) {
        e.preventDefault();
        return false;
    }
    // Disable Ctrl+Shift+I
    if(e.ctrlKey && e.shiftKey && e.keyCode === 73) {
        e.preventDefault();
        return false;
    }
    // Disable Ctrl+Shift+C
    if(e.ctrlKey && e.shiftKey && e.keyCode === 67) {
        e.preventDefault();
        return false;
    }
    // Disable Ctrl+Shift+J
    if(e.ctrlKey && e.shiftKey && e.keyCode === 74) {
        e.preventDefault();
        return false;
    }
    // Disable Ctrl+U
    if(e.ctrlKey && e.keyCode === 85) {
        e.preventDefault();
        return false;
    }
});

// Console warning message
console.log('%cSTOP!', 'color: red; font-size: 50px; font-weight: bold;');
console.log('%cThis is a browser feature intended for developers. Content here is protected by copyright.', 'color: red; font-size: 16px;');

// Navbar scroll effect
let lastScroll = 0;
const navbar = document.querySelector('.navbar');

window.addEventListener('scroll', () => {
    const currentScroll = window.pageYOffset;
    
    if (currentScroll <= 0) {
        navbar.classList.remove('scroll-up');
        return;
    }
    
    if (currentScroll > lastScroll && !navbar.classList.contains('scroll-down')) {
        // Scroll down
        navbar.classList.remove('scroll-up');
        navbar.classList.add('scroll-down');
    } else if (currentScroll < lastScroll && navbar.classList.contains('scroll-down')) {
        // Scroll up
        navbar.classList.remove('scroll-down');
        navbar.classList.add('scroll-up');
    }
    
    lastScroll = currentScroll;
});

// Add animation on scroll
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver(function(entries) {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add('animate-in');
        }
    });
}, observerOptions);

// Observe all sections
document.querySelectorAll('section').forEach(section => {
    observer.observe(section);
});

// Form validation (if you add a contact form later)
function validateEmail(email) {
    const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return re.test(email);
}

// Analytics placeholder (replace with your actual analytics)
window.addEventListener('load', function() {
    // Google Analytics or other tracking code would go here
    console.log('Page loaded successfully');
});