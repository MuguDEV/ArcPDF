document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    fetchLatestRelease();
    initScrollAnimations();
});

// Scroll Reveal Animations
function initScrollAnimations() {
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                // Add the 'visible' class to trigger animation
                entry.target.classList.add('visible');
                // Stop observing once animated
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    // Observe all elements with animation classes
    document.querySelectorAll('.slide-up, .fade-in').forEach(el => {
        observer.observe(el);
    });
}

// Theme Management
function initTheme() {
    const themeToggle = document.getElementById('theme-toggle');
    const themeIcon = themeToggle.querySelector('.material-symbols-outlined');

    // Check local storage or system preference
    const savedTheme = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

    if (savedTheme === 'dark' || (!savedTheme && prefersDark)) {
        document.body.setAttribute('data-theme', 'dark');
        themeIcon.textContent = 'dark_mode';
    }

    themeToggle.addEventListener('click', () => {
        const isDark = document.body.getAttribute('data-theme') === 'dark';

        if (isDark) {
            document.body.removeAttribute('data-theme');
            themeIcon.textContent = 'light_mode';
            localStorage.setItem('theme', 'light');
        } else {
            document.body.setAttribute('data-theme', 'dark');
            themeIcon.textContent = 'dark_mode';
            localStorage.setItem('theme', 'dark');
        }
    });
}

// Fetch GitHub Release Data
async function fetchLatestRelease() {
    const downloadSection = document.getElementById('download-section');
    const versionBadge = document.getElementById('version-badge');
    const changelogContent = document.getElementById('changelog-content');

    try {
        const response = await fetch('https://api.github.com/repos/MuguDEV/ArcPDF/releases/latest');

        if (!response.ok) {
            throw new Error('Failed to fetch release data');
        }

        const data = await response.json();
        const version = data.tag_name || data.name;
        const body = data.body || 'No changelog provided.';
        const assets = data.assets || [];

        // Update Version Badge
        versionBadge.textContent = `Latest Version: ${version}`;

        // Update Changelog

        // Clean up auto-generated GitHub release boilerplate
        let cleanBody = body
            // Remove "What's Changed" headers
            .replace(/## What's Changed/gi, '')
            .replace(/## What's New/gi, '')
            // Remove full changelog links at the bottom
            .replace(/\*\*Full Changelog\*\*: https:\/\/github.com\/[^\s]+/gi, '')
            // Clean up "by @User in https://..." from PR merges to just keep the message
            .replace(/ by @[^\s]+ in https:\/\/github.com\/[^\s]+/gi, '');

        // Improved Markdown parsing
        let formattedBody = cleanBody
            // Headers
            .replace(/^### (.*$)/gim, '<h3>$1</h3>')
            .replace(/^## (.*$)/gim, '<h2>$1</h2>')
            .replace(/^# (.*$)/gim, '<h1>$1</h1>')
            // Links
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>')
            // URLs that aren't markdown links
            .replace(/(^|[^"'])(https?:\/\/[^\s]+)/g, '$1<a href="$2" target="_blank" rel="noopener noreferrer">$2</a>')
            // Bold
            .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
            // Clean PR numbers like (#79) at the end of lists
            .replace(/\s*\(\#[0-9]+\)/g, '')
            // List items (* or -)
            .replace(/^[\*-]\s+(.*)$/gim, '<li>$1</li>');

        // Wrap consecutive <li> elements in <ul class="clean-list">
        formattedBody = formattedBody.replace(/(<li>[\s\S]*?<\/li>\n?)+/g, '<ul class="clean-list">$&</ul>');

        // Clean up empty lines and wrap paragraphs
        formattedBody = formattedBody
            .split('\n')
            .filter(line => line.trim() !== '')
            .map(line => {
                if (line.startsWith('<h') || line.startsWith('<ul') || line.startsWith('<li') || line.startsWith('</ul')) {
                    return line;
                }
                return `<p>${line}</p>`;
            })
            .join('\n');

        changelogContent.innerHTML = formattedBody || '<p>A brand new update with exciting features and improvements!</p>';

        // Find APKs
        const universalApk = assets.find(a => a.name.includes('universal.apk') || a.name.endsWith('.apk') && !a.name.includes('arm') && !a.name.includes('x86'));
        // Fallback if universal is not found
        const anyApk = assets.find(a => a.name.endsWith('.apk'));
        const downloadUrl = universalApk ? universalApk.browser_download_url : (anyApk ? anyApk.browser_download_url : data.html_url);

        renderDownloadSection(downloadSection, downloadUrl);

    } catch (error) {
        console.error('Error fetching release:', error);
        versionBadge.textContent = 'Latest Version: Unknown';
        changelogContent.innerHTML = '<p>Unable to load changelog at this time. Please visit GitHub directly.</p>';

        // Fallback to repo releases page
        renderDownloadSection(downloadSection, 'https://github.com/MuguDEV/ArcPDF/releases/latest');
    }
}

function renderDownloadSection(container, downloadUrl) {
    const isAndroid = /Android/i.test(navigator.userAgent);

    if (isAndroid) {
        container.innerHTML = `
            <button id="blob-download-btn" class="btn btn-primary">
                <div class="btn-progress-overlay" id="download-progress"></div>
                <div class="btn-content-flex" id="download-content">
                    <span class="material-symbols-outlined">download</span>
                    <span>Download APK</span>
                </div>
            </button>
            <a href="https://github.com/MuguDEV/ArcPDF/releases/latest" class="btn btn-secondary" target="_blank" rel="noopener noreferrer">
                All Releases
            </a>
        `;

        const downloadBtn = document.getElementById('blob-download-btn');
        const downloadProgress = document.getElementById('download-progress');
        const downloadContent = document.getElementById('download-content');

        if (downloadBtn) {
            downloadBtn.addEventListener('click', () => {
                // Prevent multiple clicks
                if (downloadBtn.classList.contains('downloading')) return;
                downloadBtn.classList.add('downloading');

                // Start animation
                downloadContent.innerHTML = '<div class="loading-spinner" style="width: 20px; height: 20px; border-width: 2px; margin:0;"></div> <span>Starting Download...</span>';

                // Simulate liquid progress
                requestAnimationFrame(() => {
                    downloadProgress.style.width = '80%';
                });

                // Create a hidden iframe to trigger the download without leaving the page
                const iframe = document.createElement('iframe');
                iframe.style.display = 'none';
                iframe.src = downloadUrl;
                document.body.appendChild(iframe);

                // Fallback and completion animation
                setTimeout(() => {
                    const a = document.createElement('a');
                    a.href = downloadUrl;
                    a.download = "ArcPDF.apk";
                    a.style.display = 'none';
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);

                    // Complete progress bar and show checkmark
                    downloadProgress.style.width = '100%';
                    downloadContent.innerHTML = '<span class="material-symbols-outlined">check_circle</span> <span>Downloaded!</span>';

                    // Reset button state after a few seconds
                    setTimeout(() => {
                        downloadProgress.style.transition = 'none';
                        downloadProgress.style.width = '0%';
                        // Restore transition
                        setTimeout(() => {
                            downloadProgress.style.transition = 'width 2s cubic-bezier(0.1, 0.7, 0.1, 1)';
                        }, 50);

                        downloadContent.innerHTML = '<span class="material-symbols-outlined">download</span> <span>Download APK</span>';
                        downloadBtn.classList.remove('downloading');
                    }, 3000);
                }, 1500); // Give it a moment to show the progress
            });
        }

    } else {
        container.innerHTML = `
            <div class="non-android-msg">
                <span class="material-symbols-outlined sad-icon">sentiment_dissatisfied</span>
                <h3>Oops! ArcPDF is only for Android.</h3>
                <p>Visit this page on your Android device to download.</p>
                <a href="https://github.com/MuguDEV/ArcPDF/releases/latest" class="btn btn-secondary" target="_blank" rel="noopener noreferrer">
                    View GitHub Releases
                </a>
            </div>
        `;
    }
}