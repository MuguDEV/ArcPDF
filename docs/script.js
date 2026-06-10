document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    fetchLatestRelease();
});

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
        // Improved Markdown parsing
        let formattedBody = body
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
            // List items (* or -)
            .replace(/^[\*-]\s+(.*)$/gim, '<li>$1</li>');

        // Wrap consecutive <li> elements in <ul>
        formattedBody = formattedBody.replace(/(<li>[\s\S]*?<\/li>\n?)+/g, '<ul>$&</ul>');

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

        changelogContent.innerHTML = formattedBody;

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
                <span class="material-symbols-outlined">download</span>
                Download APK
            </button>
            <a href="https://github.com/MuguDEV/ArcPDF/releases/latest" class="btn btn-secondary" target="_blank" rel="noopener noreferrer">
                All Releases
            </a>
        `;

        const downloadBtn = document.getElementById('blob-download-btn');
        if (downloadBtn) {
            downloadBtn.addEventListener('click', () => {
                const originalContent = downloadBtn.innerHTML;
                downloadBtn.innerHTML = '<div class="loading-spinner" style="width: 20px; height: 20px; border-width: 2px;"></div> Starting Download...';

                // Create a hidden iframe to trigger the download without leaving the page
                // This bypasses CORS issues that fetch() would encounter with GitHub Releases.
                const iframe = document.createElement('iframe');
                iframe.style.display = 'none';
                iframe.src = downloadUrl;
                document.body.appendChild(iframe);

                // Fallback to a direct link click in case the iframe gets blocked by strict browser policies
                setTimeout(() => {
                    const a = document.createElement('a');
                    a.href = downloadUrl;
                    a.download = "ArcPDF.apk";
                    a.style.display = 'none';
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);

                    // Reset button state
                    setTimeout(() => {
                        downloadBtn.innerHTML = originalContent;
                    }, 2000);
                }, 500);
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