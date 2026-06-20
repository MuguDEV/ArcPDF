document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    fetchLatestRelease();
    initScrollAnimations();
    initMagneticButtons();
    initParallaxMockups();
});

// Magnetic Buttons
function initMagneticButtons() {
    const buttons = document.querySelectorAll('.btn');
    buttons.forEach(btn => {
        btn.addEventListener('mousemove', (e) => {
            const rect = btn.getBoundingClientRect();
            const x = e.clientX - rect.left - rect.width / 2;
            const y = e.clientY - rect.top - rect.height / 2;

            // Subtle magnetic pull
            btn.style.transform = `translate(${x * 0.15}px, ${y * 0.15}px)`;

            // Adjust the sheen gradient position
            const after = btn.style;
            // We use css variables to pass mouse position to the pseudo element
            btn.style.setProperty('--mouse-x', `${e.clientX - rect.left}px`);
            btn.style.setProperty('--mouse-y', `${e.clientY - rect.top}px`);
        });

        btn.addEventListener('mouseleave', () => {
            btn.style.transform = 'translate(0px, 0px)';
        });
    });
}

// Parallax and 3D Mockups
function initParallaxMockups() {
    const mockups = document.querySelectorAll('.smartphone-mockup');

    // Mouse hover 3D tilt
    mockups.forEach(mockup => {
        mockup.addEventListener('mousemove', (e) => {
            const rect = mockup.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;

            const centerX = rect.width / 2;
            const centerY = rect.height / 2;

            const rotateX = ((y - centerY) / centerY) * -10; // Max 10 deg
            const rotateY = ((x - centerX) / centerX) * 10;

            mockup.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale(1.02)`;
        });

        mockup.addEventListener('mouseleave', () => {
            mockup.style.transform = 'perspective(1000px) rotateX(0deg) rotateY(0deg) rotateZ(2deg)';
        });
    });

    // Scroll parallax
    window.addEventListener('scroll', () => {
        const scrolled = window.scrollY;
        mockups.forEach((mockup, index) => {
            // Only apply scroll parallax if not currently being hovered (checking transform string)
            if (!mockup.style.transform.includes('rotateX')) {
                 const speed = (index + 1) * 0.05;
                 const yOffset = scrolled * speed;
                 // Keep the base Z rotation
                 mockup.style.transform = `translateY(${yOffset}px) rotateZ(2deg)`;
            }
        });
    });
}

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
    const timelineContainer = document.getElementById('timeline-container');

    try {
        const response = await fetch('https://api.github.com/repos/MuguDEV/ArcPDF/releases');

        if (!response.ok) {
            throw new Error('Failed to fetch release data');
        }

        const releases = await response.json();

        if (!releases || releases.length === 0) {
            throw new Error('No releases found');
        }

        const latestRelease = releases[0];
        const latestVersion = latestRelease.tag_name || latestRelease.name;

        // Update Version Badge
        versionBadge.textContent = `Latest Version: ${latestVersion}`;

        // Find APKs for the hero download button
        const latestAssets = latestRelease.assets || [];
        const latestUniversalApk = latestAssets.find(a => a.name.includes('universal.apk') || a.name.endsWith('.apk') && !a.name.includes('arm') && !a.name.includes('x86'));
        const latestAnyApk = latestAssets.find(a => a.name.endsWith('.apk'));
        const latestDownloadUrl = latestUniversalApk ? latestUniversalApk.browser_download_url : (latestAnyApk ? latestAnyApk.browser_download_url : latestRelease.html_url);

        renderDownloadSection(downloadSection, latestDownloadUrl);

        // Build Timeline
        timelineContainer.innerHTML = ''; // Clear loading spinner

        releases.forEach((release, index) => {
            const version = release.tag_name || release.name;
            const date = new Date(release.published_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
            const body = release.body || 'No changelog provided.';
            const assets = release.assets || [];

            // Clean up auto-generated GitHub release boilerplate
            let cleanBody = body
                .replace(/## What's Changed/gi, '')
                .replace(/## What's New/gi, '')
                .replace(/\*\*Full Changelog\*\*: https:\/\/github.com\/[^\s]+/gi, '')
                .replace(/ by @[^\s]+ in https:\/\/github.com\/[^\s]+/gi, '');

            // Improved Markdown parsing
            let formattedBody = cleanBody
                .replace(/^### (.*$)/gim, '<h3>$1</h3>')
                .replace(/^## (.*$)/gim, '<h2>$1</h2>')
                .replace(/^# (.*$)/gim, '<h1>$1</h1>')
                .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>')
                .replace(/(^|[^"'])(https?:\/\/[^\s]+)/g, '$1<a href="$2" target="_blank" rel="noopener noreferrer">$2</a>')
                .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                .replace(/\s*\(\#[0-9]+\)/g, '')
                .replace(/^[\*-]\s+(.*)$/gim, '<li>$1</li>');

            formattedBody = formattedBody.replace(/(<li>[\s\S]*?<\/li>\n?)+/g, '<ul class="clean-list">$&</ul>');

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

            if (!formattedBody.trim()) {
                formattedBody = '<p>Minor updates and improvements.</p>';
            }

            // Find APKs for this release
            const universalApk = assets.find(a => a.name.includes('universal.apk') || a.name.endsWith('.apk') && !a.name.includes('arm') && !a.name.includes('x86'));
            const anyApk = assets.find(a => a.name.endsWith('.apk'));
            const downloadUrl = universalApk ? universalApk.browser_download_url : (anyApk ? anyApk.browser_download_url : release.html_url);

            const isAndroid = /Android/i.test(navigator.userAgent);
            const downloadLink = isAndroid
                ? `<a href="${downloadUrl}" class="timeline-download-btn"><span class="material-symbols-outlined">download</span> Download APK</a>`
                : `<a href="${release.html_url}" target="_blank" class="timeline-download-btn"><span class="material-symbols-outlined">open_in_new</span> View on GitHub</a>`;

            const cardHtml = `
                <div class="timeline-card liquid-glass pill-container">
                    <div class="timeline-header">
                        <div>
                            <h3 class="timeline-version">${version}</h3>
                            <div class="timeline-date">${date}</div>
                        </div>
                        <div>
                            ${downloadLink}
                        </div>
                    </div>
                    <div class="changelog-content">
                        ${formattedBody}
                    </div>
                </div>
            `;
            timelineContainer.innerHTML += cardHtml;
        });

    } catch (error) {
        console.error('Error fetching release:', error);
        versionBadge.textContent = 'Latest Version: Unknown';

        if (timelineContainer) {
            timelineContainer.innerHTML = `
                <div class="timeline-card liquid-glass pill-container">
                    <div class="changelog-content">
                        <p>Unable to load release history at this time. Please visit GitHub directly.</p>
                        <a href="https://github.com/MuguDEV/ArcPDF/releases" class="btn btn-secondary" target="_blank" rel="noopener noreferrer">View All Releases</a>
                    </div>
                </div>
            `;
        }

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