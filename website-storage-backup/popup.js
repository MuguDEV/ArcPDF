document.addEventListener('DOMContentLoaded', async () => {
    const currentOriginEl = document.getElementById('current-origin');
    const detectBtn = document.getElementById('detect-btn');
    const exportBtn = document.getElementById('export-btn');
    const importBtn = document.getElementById('import-btn');
    const importFile = document.getElementById('import-file');
    const clearBtn = document.getElementById('clear-btn');
    const detectedStorageContainer = document.getElementById('detected-storage-container');
    const detectedList = document.getElementById('detected-list');
    const messageContainer = document.getElementById('message-container');

    let currentTab = null;
    let currentUrl = null;

    // Get current tab
    try {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (tab && tab.url && !tab.url.startsWith('chrome://') && !tab.url.startsWith('edge://') && !tab.url.startsWith('about:')) {
            currentTab = tab;
            currentUrl = new URL(tab.url);
            currentOriginEl.textContent = currentUrl.origin;
            exportBtn.disabled = false;
        } else {
            currentOriginEl.textContent = "Invalid/Restricted Tab";
            showMessage("Cannot operate on browser-protected or invalid tabs.", "error");
            disableButtons();
        }
    } catch (e) {
        currentOriginEl.textContent = "Error getting tab";
        showMessage("Error accessing current tab.", "error");
        disableButtons();
    }

    function disableButtons() {
        detectBtn.disabled = true;
        exportBtn.disabled = true;
        importBtn.disabled = true;
    }

    function showMessage(msg, type) {
        messageContainer.textContent = msg;
        messageContainer.className = `message ${type}`;
        messageContainer.style.display = 'block';
        setTimeout(() => {
            messageContainer.style.display = 'none';
        }, 5000);
    }

    // Ensure content script is injected
    async function ensureContentScriptInjected() {
        try {
            await chrome.tabs.sendMessage(currentTab.id, { action: "ping" });
        } catch (e) {
            // Script not injected, inject it now
            await chrome.scripting.executeScript({
                target: { tabId: currentTab.id },
                files: ['content.js']
            });
        }
    }

    // Detect Storage
    detectBtn.addEventListener('click', async () => {
        if (!currentTab) return;
        detectBtn.textContent = "Detecting...";
        detectBtn.disabled = true;

        try {
            await ensureContentScriptInjected();

            // Get Cookies
            const cookies = await chrome.cookies.getAll({ url: currentUrl.origin });
            const hasCookies = cookies.length > 0;

            // Get Page Storage via content script
            const response = await chrome.tabs.sendMessage(currentTab.id, { action: "detect" });

            detectedList.innerHTML = '';

            const addItem = (name, present) => {
                const li = document.createElement('li');
                li.textContent = `${name}: ${present ? 'Found' : 'Empty'}`;
                li.style.color = present ? 'var(--success-color)' : 'var(--disabled-text)';
                detectedList.appendChild(li);
            };

            addItem('Cookies (accessible)', hasCookies);

            if (response) {
                addItem('LocalStorage', response.localStorage);
                addItem('SessionStorage', response.sessionStorage);
                addItem('IndexedDB', response.indexedDB);
                addItem('Cache Storage', response.cacheStorage);
            } else {
                 addItem('Page Storage (Local/Session/IDB/Cache)', false);
                 showMessage("Could not reach content script. Try reloading the page.", "warning");
            }

            detectedStorageContainer.style.display = 'block';
            showMessage("Detection complete.", "success");

        } catch (e) {
            console.error(e);
            showMessage("Detection failed. Is the page fully loaded?", "error");
        } finally {
            detectBtn.textContent = "Detect Current Website";
            detectBtn.disabled = false;
        }
    });

    // Export Storage
    exportBtn.addEventListener('click', async () => {
        if (!currentTab) return;

        const confirmed = window.confirm("WARNING: The exported file may contain sensitive login/session data. Keep it safe. Proceed with export?");
        if (!confirmed) return;

        exportBtn.textContent = "Exporting...";
        exportBtn.disabled = true;

        try {
            await ensureContentScriptInjected();

            // 1. Get Cookies (Filter out HttpOnly cookies as per requirements)
            const allCookies = await chrome.cookies.getAll({ url: currentUrl.origin });
            const exportableCookies = allCookies.filter(cookie => !cookie.httpOnly);

            // 2. Get Page Storage
            const response = await chrome.tabs.sendMessage(currentTab.id, { action: "export" });

            if (!response || !response.success) {
                throw new Error(response ? response.error : "Failed to communicate with page.");
            }

            // Gather extra info (Service Worker and Manifest) via a quick injected script
            const extraInfoResult = await chrome.scripting.executeScript({
                target: { tabId: currentTab.id },
                func: async () => {
                    let swCount = 0;
                    if ('serviceWorker' in navigator) {
                        try {
                            const registrations = await navigator.serviceWorker.getRegistrations();
                            swCount = registrations.length;
                        } catch (e) {}
                    }

                    let manifestUrl = null;
                    const manifestLink = document.querySelector('link[rel="manifest"]');
                    if (manifestLink) {
                        manifestUrl = manifestLink.href;
                    }

                    return { serviceWorkers: swCount, manifestUrl: manifestUrl };
                }
            });
            const extraInfo = extraInfoResult[0]?.result || {};

            // 3. Compile Data
            const exportData = {
                origin: currentUrl.origin,
                exportedAt: new Date().toISOString(),
                localStorage: response.data.localStorage,
                sessionStorage: response.data.sessionStorage,
                indexedDB: response.data.indexedDB,
                cacheStorage: response.data.cacheStorage,
                cookies: exportableCookies,
                serviceWorkerRegistrations: extraInfo.serviceWorkers,
                manifestUrl: extraInfo.manifestUrl,
                notes: [
                    "Service worker and manifest info are tied to server hosting and not fully exportable here. HttpOnly cookies cannot be accessed."
                ]
            };

            // 4. Download JSON
            const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const filename = `storage_backup_${currentUrl.hostname}_${new Date().toISOString().replace(/[:.]/g, '-')}.json`;

            await chrome.downloads.download({
                url: url,
                filename: filename,
                saveAs: true
            });

            showMessage("Export successful!", "success");

        } catch (e) {
            console.error(e);
            showMessage(`Export failed: ${e.message}`, "error");
        } finally {
            exportBtn.textContent = "Export Storage";
            exportBtn.disabled = false;
        }
    });

    // Import Storage Button (triggers file input)
    importBtn.addEventListener('click', () => {
        if (!currentTab) return;
        importFile.click();
    });

    // Handle File Selection for Import
    importFile.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        try {
            const text = await file.text();
            const importData = JSON.parse(text);

            // Validation & Warnings
            if (!importData.origin) {
                throw new Error("Invalid backup file: Missing origin.");
            }

            if (importData.origin !== currentUrl.origin) {
                const proceed = window.confirm(`WARNING: Domain Mismatch!\n\nFile origin: ${importData.origin}\nCurrent origin: ${currentUrl.origin}\n\nAre you sure you want to import this data here?`);
                if (!proceed) {
                    importFile.value = ''; // reset input
                    return;
                }
            }

            const confirmOverwrite = window.confirm("WARNING: Importing will overwrite existing storage data for this website. Proceed?");
            if (!confirmOverwrite) {
                importFile.value = '';
                return;
            }

            importBtn.textContent = "Importing...";
            importBtn.disabled = true;

            await ensureContentScriptInjected();

            // 1. Restore Cookies
            if (importData.cookies && Array.isArray(importData.cookies)) {
                for (const cookie of importData.cookies) {
                    // Skip HttpOnly cookies if any somehow made it into the backup
                    if (cookie.httpOnly) continue;

                    // Remove unsupported properties for set()
                    const { hostOnly, session, ...cleanCookie } = cookie;

                    // The url must be specified to set a cookie
                    cleanCookie.url = currentUrl.origin;

                    // If it was a hostOnly cookie, we should not explicitly provide the domain
                    // to chrome.cookies.set() so it remains host-only.
                    if (hostOnly) {
                        delete cleanCookie.domain;
                    }

                    try {
                        await chrome.cookies.set(cleanCookie);
                    } catch (cookieErr) {
                         console.warn("Failed to set a cookie:", cleanCookie, cookieErr);
                    }
                }
            }

            // 2. Restore Page Storage
            const response = await chrome.tabs.sendMessage(currentTab.id, {
                action: "import",
                data: importData
            });

            if (!response || !response.success) {
                throw new Error(response ? response.error : "Failed to communicate with page during import.");
            }

            showMessage("Import successful! Reload the page to see changes.", "success");

        } catch (err) {
            console.error(err);
            showMessage(`Import failed: ${err.message}`, "error");
        } finally {
            importFile.value = ''; // reset input
            importBtn.textContent = "Import Storage";
            importBtn.disabled = false;
        }
    });

    // Clear Status
    clearBtn.addEventListener('click', () => {
        detectedStorageContainer.style.display = 'none';
        detectedList.innerHTML = '';
        messageContainer.style.display = 'none';
    });
});