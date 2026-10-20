(() => {
    'use strict';

    const API_URL = 'https://api.github.com/repos/MuguDEV/ArcPDF/releases?per_page=20';
    const REPO_URL = 'https://github.com/MuguDEV/ArcPDF';
    const RELEASES_URL = `${REPO_URL}/releases`;
    const LATEST_RELEASE_URL = `${RELEASES_URL}/latest`;
    const CACHE_KEY = 'arcpdf:releases:v2';
    const CACHE_TTL = 10 * 60 * 1000;
    const OLDER_BATCH = 4;

    const state = {
        releases: [],
        older: [],
        olderShown: 0
    };

    let clearActiveNav = () => {};

    const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
    const dateFormatter = new Intl.DateTimeFormat('en', { year: 'numeric', month: 'short', day: 'numeric' });

    const $ = (selector, context = document) => context.querySelector(selector);
    const $$ = (selector, context = document) => Array.from(context.querySelectorAll(selector));

    const SKELETON_MARKUP = `
        <div class="release-skeleton" aria-hidden="true">
            <div class="skeleton-line skeleton-line--sm"></div>
            <div class="skeleton-line skeleton-line--lg"></div>
            <div class="skeleton-line"></div>
            <div class="skeleton-line skeleton-line--md"></div>
        </div>
        <div class="release-skeleton release-skeleton--row" aria-hidden="true"></div>
        <div class="release-skeleton release-skeleton--row" aria-hidden="true"></div>`;

    /* ---------- Boot ---------- */
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    function init() {
        initTheme();
        initMenu();
        initHeader();
        initScrollSpy();
        initReveal();
        initYear();
        initReleases();
    }

    /* ---------- Theme ---------- */
    function initTheme() {
        const toggle = $('#theme-toggle');
        if (!toggle) return;

        const root = document.documentElement;
        const meta = $('meta[name="theme-color"]');
        const systemQuery = window.matchMedia('(prefers-color-scheme: dark)');

        const storedTheme = () => {
            try {
                const value = localStorage.getItem('arcpdf-theme');
                return value === 'light' || value === 'dark' ? value : null;
            } catch (error) {
                return null;
            }
        };

        const apply = (theme, persist) => {
            root.setAttribute('data-theme', theme);
            toggle.setAttribute('aria-pressed', theme === 'dark' ? 'true' : 'false');
            toggle.setAttribute('aria-label', theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
            if (meta) meta.setAttribute('content', theme === 'dark' ? '#0A0A0B' : '#F4F3EF');

            if (persist) {
                try {
                    localStorage.setItem('arcpdf-theme', theme);
                } catch (error) { /* storage can be unavailable */ }
            }
        };

        apply(root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light', false);

        toggle.addEventListener('click', () => {
            apply(root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark', true);
        });

        const onSystemChange = (event) => {
            if (!storedTheme()) apply(event.matches ? 'dark' : 'light', false);
        };

        if (typeof systemQuery.addEventListener === 'function') {
            systemQuery.addEventListener('change', onSystemChange);
        } else if (typeof systemQuery.addListener === 'function') {
            systemQuery.addListener(onSystemChange);
        }
    }

    /* ---------- Mobile menu ---------- */
    function initMenu() {
        const header = $('#site-header');
        const toggle = $('#menu-toggle');
        const nav = $('#mobile-nav');
        if (!header || !toggle || !nav) return;

        const setOpen = (open) => {
            header.classList.toggle('menu-open', open);
            toggle.setAttribute('aria-expanded', String(open));
            toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
        };

        toggle.addEventListener('click', () => {
            setOpen(!header.classList.contains('menu-open'));
        });

        nav.addEventListener('click', (event) => {
            if (event.target.closest('a')) setOpen(false);
        });

        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape' && header.classList.contains('menu-open')) {
                setOpen(false);
                toggle.focus();
            }
        });

        document.addEventListener('pointerdown', (event) => {
            if (header.classList.contains('menu-open') && !header.contains(event.target)) {
                setOpen(false);
            }
        });

        const desktopQuery = window.matchMedia('(min-width: 861px)');
        const closeOnDesktop = (event) => {
            if (event.matches) setOpen(false);
        };

        if (typeof desktopQuery.addEventListener === 'function') {
            desktopQuery.addEventListener('change', closeOnDesktop);
        } else if (typeof desktopQuery.addListener === 'function') {
            desktopQuery.addListener(closeOnDesktop);
        }
    }

    /* ---------- Sticky header ---------- */
    function initHeader() {
        const header = $('#site-header');
        if (!header) return;

        let ticking = false;
        const update = () => {
            header.classList.toggle('is-scrolled', window.scrollY > 14);
            if (window.scrollY < 240) clearActiveNav();
            ticking = false;
        };

        window.addEventListener('scroll', () => {
            if (ticking) return;
            ticking = true;
            window.requestAnimationFrame(update);
        }, { passive: true });

        update();
    }

    /* ---------- Scroll spy ---------- */
    function initScrollSpy() {
        const links = $$('.primary-nav a[href^="#"], .mobile-nav a[href^="#"]');
        if (!links.length || !('IntersectionObserver' in window)) return;

        const sections = [];
        const seen = new Set();

        links.forEach((link) => {
            const id = link.getAttribute('href').slice(1);
            if (!id || seen.has(id)) return;
            const section = document.getElementById(id);
            if (section) {
                seen.add(id);
                sections.push(section);
            }
        });

        if (!sections.length) return;

        clearActiveNav = () => {
            links.forEach((link) => link.removeAttribute('aria-current'));
        };

        const setActive = (id) => {
            links.forEach((link) => {
                if (link.getAttribute('href') === `#${id}`) {
                    link.setAttribute('aria-current', 'location');
                } else {
                    link.removeAttribute('aria-current');
                }
            });
        };

        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) setActive(entry.target.id);
            });
        }, { rootMargin: '-42% 0px -52% 0px', threshold: 0 });

        sections.forEach((section) => observer.observe(section));
    }

    /* ---------- Reveal on scroll ---------- */
    function initReveal() {
        const items = $$('.reveal');
        if (!items.length) return;

        const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (reducedMotion || !('IntersectionObserver' in window)) {
            items.forEach((item) => item.classList.add('is-in'));
            return;
        }

        document.documentElement.classList.add('js');

        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (!entry.isIntersecting) return;
                entry.target.classList.add('is-in');
                observer.unobserve(entry.target);
            });
        }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

        items.forEach((item) => observer.observe(item));
    }

    function initYear() {
        const year = $('#year');
        if (year) year.textContent = String(new Date().getFullYear());
    }

    /* ---------- Releases ---------- */
    function initReleases() {
        if (!$('#release-list')) return;

        const cached = readCache();
        if (cached && cached.fresh) {
            state.releases = cached.data;
            renderAll();
            return;
        }

        loadReleases();
    }

    async function loadReleases() {
        const list = $('#release-list');
        if (!list) return;

        const footer = $('#release-footer');
        if (footer) footer.hidden = true;
        list.setAttribute('aria-busy', 'true');
        list.innerHTML = SKELETON_MARKUP;
        setReleaseStatus('Loading release history from GitHub.');

        const controller = new AbortController();
        const timeout = window.setTimeout(() => controller.abort(), 12000);

        try {
            const response = await fetch(API_URL, {
                headers: { Accept: 'application/vnd.github+json' },
                cache: 'no-store',
                signal: controller.signal
            });

            if (!response.ok) throw new Error(`GitHub returned HTTP ${response.status}`);

            const payload = await response.json();
            if (!Array.isArray(payload)) throw new Error('Unexpected release payload');

            const releases = payload
                .filter((release) => release && !release.draft)
                .map(normalizeRelease)
                .filter(Boolean);

            if (!releases.length) throw new Error('No published releases');

            state.releases = releases;
            writeCache(releases);
            renderAll();
        } catch (error) {
            const cached = readCache();
            if (cached && cached.data.length) {
                state.releases = cached.data;
                renderAll({ stale: true });
            } else {
                renderError(error);
            }
        } finally {
            window.clearTimeout(timeout);
            list.setAttribute('aria-busy', 'false');
        }
    }

    function renderAll(options = {}) {
        const list = $('#release-list');
        const latest = state.releases[0];
        if (!list || !latest) return;

        state.older = state.releases.slice(1);
        state.olderShown = 0;

        updateVersion(latest);
        updateDownloads(latest);

        list.replaceChildren();

        if (options.stale) {
            const note = document.createElement('p');
            note.className = 'release-note';
            note.textContent = 'Showing saved release data — GitHub could not be reached.';
            list.append(note);
        }

        list.append(renderLatestRelease(latest));

        const rows = document.createElement('div');
        rows.className = 'release-rows';
        rows.id = 'older-releases';
        list.append(rows);

        appendOlderReleases();

        const footer = $('#release-footer');
        if (footer) footer.hidden = false;

        list.setAttribute('aria-busy', 'false');

        setReleaseStatus(
            `Latest release ${latest.tag}. ${state.older.length} older release${state.older.length === 1 ? '' : 's'} available.`
        );
    }

    function renderLatestRelease(release) {
        const article = document.createElement('article');
        article.className = 'release release--latest';

        const date = release.date
            ? `<time datetime="${release.date.toISOString()}">${escapeHtml(formatDate(release.date))}</time>`
            : 'Date unavailable';
        const size = release.apk && release.apk.size ? ` · ${escapeHtml(formatBytes(release.apk.size))} APK` : '';
        const prerelease = release.prerelease
            ? '<span class="release-badge release-badge--ghost">Pre-release</span>'
            : '';
        const apkButton = release.apk
            ? `<a class="btn btn-primary btn--sm" href="${escapeHtml(release.apk.url)}">
                   ${icon('download')} Download APK
               </a>`
            : '';

        article.innerHTML = `
            <header class="release-head">
                <div class="release-meta">
                    <div class="release-badges">
                        <span class="release-badge">Latest</span>
                        ${prerelease}
                    </div>
                    <h3 class="release-version">${escapeHtml(release.tag)}</h3>
                    <p class="release-date">${date}${size}</p>
                </div>
                <div class="release-actions">
                    ${apkButton}
                    <a class="btn btn-secondary btn--sm" href="${escapeHtml(release.url)}" target="_blank" rel="noopener noreferrer">
                        View on GitHub ${icon('arrow-up-right')}
                    </a>
                </div>
            </header>
            <div class="release-body">${renderChangelog(release.body)}</div>`;

        return article;
    }

    function renderOlderRelease(release) {
        const details = document.createElement('details');
        details.className = 'release-row';

        const date = release.date
            ? `<time datetime="${release.date.toISOString()}">${escapeHtml(formatDate(release.date))}</time>`
            : 'Date unavailable';
        const apkButton = release.apk
            ? `<a class="btn btn-primary btn--sm" href="${escapeHtml(release.apk.url)}">
                   ${icon('download')} Download APK
               </a>`
            : '';

        details.innerHTML = `
            <summary>
                <span class="release-row-main">
                    <span class="release-version">${escapeHtml(release.tag)}</span>
                    <span class="release-date">${date}</span>
                </span>
                <span class="release-row-action">
                    <span class="release-row-hint">Notes</span>
                    ${icon('chevron-down')}
                </span>
            </summary>
            <div class="release-row-body">
                <div class="release-actions">
                    ${apkButton}
                    <a class="btn btn-secondary btn--sm" href="${escapeHtml(release.url)}" target="_blank" rel="noopener noreferrer">
                        View on GitHub ${icon('arrow-up-right')}
                    </a>
                </div>
                <div class="release-body">${renderChangelog(release.body)}</div>
            </div>`;

        return details;
    }

    function appendOlderReleases() {
        const rows = $('#older-releases');
        if (!rows) return;

        const next = state.older.slice(state.olderShown, state.olderShown + OLDER_BATCH);
        next.forEach((release) => rows.append(renderOlderRelease(release)));
        state.olderShown += next.length;
        updateLoadMore();
    }

    function updateLoadMore() {
        const button = $('#load-more');
        if (!button) return;

        const remaining = state.older.length - state.olderShown;
        button.hidden = remaining <= 0;

        if (remaining > 0) {
            const count = Math.min(OLDER_BATCH, remaining);
            button.textContent = `Show ${count} older release${count === 1 ? '' : 's'}`;
        }
    }

    function updateVersion(release) {
        const text = $('#version-text');
        const line = $('.hero-version');
        if (!text) return;

        if (release) {
            const date = release.date ? ` · ${formatDate(release.date)}` : '';
            text.textContent = `Latest ${release.tag}${date}`;
            if (line) {
                line.classList.add('is-live');
                line.classList.remove('is-error');
            }
        } else {
            text.textContent = 'Latest release on GitHub';
            if (line) {
                line.classList.remove('is-live');
                line.classList.add('is-error');
            }
        }
    }

    function updateDownloads(release) {
        const targets = ['#hero-download', '#header-download', '#mobile-download', '#cta-download'];

        targets.forEach((selector) => {
            const link = $(selector);
            if (!link) return;

            const label = $('[data-download-label]', link);
            const size = $('[data-download-size]', link);

            if (release && release.apk) {
                link.href = release.apk.url;
                link.removeAttribute('target');
                link.setAttribute('rel', 'noopener');
                if (label) label.textContent = 'Download APK';
                if (size) size.textContent = formatBytes(release.apk.size) || 'APK';
            } else {
                link.href = release ? release.url : LATEST_RELEASE_URL;
                link.setAttribute('target', '_blank');
                link.setAttribute('rel', 'noopener noreferrer');
                if (label) label.textContent = 'Get latest release';
                if (size) size.textContent = 'GitHub';
            }
        });
    }

    function useFallbackDownloads() {
        updateDownloads(null);
    }

    function renderError(error) {
        if (window.console && typeof window.console.warn === 'function') {
            window.console.warn('[ArcPDF] Release history could not be loaded:', error);
        }

        const list = $('#release-list');
        if (!list) return;

        list.innerHTML = `
            <div class="callout" role="alert">
                <p><strong>Release history didn’t load.</strong> GitHub may be rate-limiting this page, or the connection is offline.</p>
                <button class="btn btn-secondary btn--sm" type="button" id="retry-releases">Try again</button>
                <a class="btn btn-secondary btn--sm" href="${RELEASES_URL}" target="_blank" rel="noopener noreferrer">Open releases</a>
            </div>`;

        const retry = $('#retry-releases');
        if (retry) retry.addEventListener('click', () => loadReleases());

        updateVersion(null);
        useFallbackDownloads();
        setReleaseStatus('Release history could not be loaded. You can open GitHub releases instead.');
    }

    /* ---------- Release data ---------- */
    function normalizeRelease(release) {
        const tag = typeof release.tag_name === 'string' && release.tag_name.trim()
            ? release.tag_name.trim()
            : (typeof release.name === 'string' ? release.name.trim() : '');

        if (!tag) return null;

        const assets = Array.isArray(release.assets) ? release.assets : [];
        const apks = assets.filter((asset) => (
            asset &&
            typeof asset.name === 'string' &&
            /\.apk$/i.test(asset.name) &&
            isHttps(asset.browser_download_url)
        ));

        const apk = apks.find((asset) => /universal/i.test(asset.name))
            || apks.find((asset) => !/(arm64|armeabi|x86|abi)/i.test(asset.name))
            || apks[0]
            || null;

        const published = release.published_at ? new Date(release.published_at) : null;
        const date = published && !Number.isNaN(published.getTime()) ? published : null;

        return {
            tag,
            name: typeof release.name === 'string' ? release.name : tag,
            prerelease: Boolean(release.prerelease),
            date,
            body: typeof release.body === 'string' ? release.body : '',
            url: isHttps(release.html_url) ? release.html_url : RELEASES_URL,
            apk: apk
                ? {
                    url: apk.browser_download_url,
                    name: apk.name,
                    size: Number(apk.size) || 0
                }
                : null
        };
    }

    function hydrateCachedRelease(release) {
        if (!release || typeof release.tag !== 'string' || !release.tag) return null;

        const date = release.date ? new Date(release.date) : null;
        const apk = release.apk && isHttps(release.apk.url)
            ? {
                url: release.apk.url,
                name: typeof release.apk.name === 'string' ? release.apk.name : '',
                size: Number(release.apk.size) || 0
            }
            : null;

        return {
            tag: release.tag,
            name: typeof release.name === 'string' ? release.name : release.tag,
            prerelease: Boolean(release.prerelease),
            date: date && !Number.isNaN(date.getTime()) ? date : null,
            body: typeof release.body === 'string' ? release.body : '',
            url: isHttps(release.url) ? release.url : RELEASES_URL,
            apk
        };
    }

    function readCache() {
        try {
            const raw = localStorage.getItem(CACHE_KEY);
            if (!raw) return null;

            const parsed = JSON.parse(raw);
            if (!parsed || !Array.isArray(parsed.releases) || typeof parsed.savedAt !== 'number') return null;

            const data = parsed.releases.map(hydrateCachedRelease).filter(Boolean);
            if (!data.length) return null;

            return {
                data,
                fresh: Date.now() - parsed.savedAt < CACHE_TTL
            };
        } catch (error) {
            return null;
        }
    }

    function writeCache(releases) {
        try {
            localStorage.setItem(CACHE_KEY, JSON.stringify({ savedAt: Date.now(), releases }));
        } catch (error) { /* storage can be unavailable */ }
    }

    /* ---------- Changelog rendering ---------- */
    function renderChangelog(rawBody) {
        let text = String(rawBody || '')
            .replace(/\r\n?/g, '\n')
            .replace(/^\s*##\s*What'?s Changed\s*$/gim, '')
            .replace(/^\s*##\s*What'?s New\s*$/gim, '')
            .replace(/^\s*\*\*Full Changelog\*\*:.*$/gim, '')
            .replace(/\s+by\s+@[\w-]+\s+in\s+https?:\/\/\S+/gi, '')
            .replace(/\s*\(#\d+\)/g, '');

        if (text.length > 8000) text = `${text.slice(0, 8000)}…`;

        const lines = escapeHtml(text).split('\n');
        const output = [];
        let list = [];
        let paragraph = [];

        const flushList = () => {
            if (!list.length) return;
            output.push(`<ul>${list.map((item) => `<li>${renderInline(item)}</li>`).join('')}</ul>`);
            list = [];
        };

        const flushParagraph = () => {
            if (!paragraph.length) return;
            output.push(`<p>${renderInline(paragraph.join(' '))}</p>`);
            paragraph = [];
        };

        lines.forEach((line) => {
            const trimmed = line.trim();

            if (!trimmed) {
                flushList();
                flushParagraph();
                return;
            }

            if (/^#{1,6}\s+/.test(trimmed)) {
                flushList();
                flushParagraph();
                output.push(`<h4>${renderInline(trimmed.replace(/^#{1,6}\s+/, ''))}</h4>`);
                return;
            }

            if (/^[-*+]\s+/.test(trimmed)) {
                flushParagraph();
                list.push(trimmed.replace(/^[-*+]\s+/, ''));
                return;
            }

            if (/^\d+\.\s+/.test(trimmed)) {
                flushParagraph();
                list.push(trimmed.replace(/^\d+\.\s+/, ''));
                return;
            }

            if (/^([-*_])\1{2,}$/.test(trimmed)) {
                flushList();
                flushParagraph();
                return;
            }

            flushList();
            paragraph.push(trimmed.replace(/^>\s?/, ''));
        });

        flushList();
        flushParagraph();

        return output.join('') || '<p>No release notes were provided for this build.</p>';
    }

    function renderInline(value) {
        return value
            .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
            .replace(/__([^_]+)__/g, '<strong>$1</strong>')
            .replace(/`([^`]+)`/g, '<code>$1</code>')
            .replace(
                /\[([^\]]+)\]\((https:\/\/[^\s)]+)\)/g,
                '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>'
            );
    }

    /* ---------- Small helpers ---------- */
    function icon(name) {
        return `<svg class="icon" aria-hidden="true"><use href="#i-${name}"></use></svg>`;
    }

    function escapeHtml(value) {
        return String(value).replace(/[&<>"']/g, (character) => ESCAPES[character]);
    }

    function isHttps(value) {
        if (typeof value !== 'string') return false;
        try {
            return new URL(value).protocol === 'https:';
        } catch (error) {
            return false;
        }
    }

    function formatDate(date) {
        if (!(date instanceof Date) || Number.isNaN(date.getTime())) return '';
        try {
            return dateFormatter.format(date);
        } catch (error) {
            return date.toISOString().slice(0, 10);
        }
    }

    function formatBytes(bytes) {
        if (!Number.isFinite(bytes) || bytes <= 0) return '';
        const megabytes = bytes / (1024 * 1024);
        if (megabytes >= 1) return `${megabytes.toFixed(megabytes >= 10 ? 0 : 1)} MB`;
        return `${Math.max(1, Math.round(bytes / 1024))} KB`;
    }

    function setReleaseStatus(message) {
        const status = $('#release-status');
        if (status) status.textContent = message;
    }
})();
