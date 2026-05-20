// Content script to run in the context of the page

// Utility to convert Blob to Base64
const blobToBase64 = (blob) => {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
};

// Utility to convert Base64 to Blob
const base64ToBlob = async (base64) => {
  const response = await fetch(base64);
  return await response.blob();
};

const extractLocalStorage = () => {
  const data = {};
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    data[key] = localStorage.getItem(key);
  }
  return data;
};

const extractSessionStorage = () => {
  const data = {};
  for (let i = 0; i < sessionStorage.length; i++) {
    const key = sessionStorage.key(i);
    data[key] = sessionStorage.getItem(key);
  }
  return data;
};

const extractIndexedDB = async () => {
  const data = {};

  if (!window.indexedDB || !window.indexedDB.databases) {
      console.warn("IndexedDB.databases() not supported in this browser.");
      return data;
  }

  try {
    const dbs = await window.indexedDB.databases();
    for (const dbInfo of dbs) {
      data[dbInfo.name] = { version: dbInfo.version, stores: {} };

      const db = await new Promise((resolve, reject) => {
        const request = window.indexedDB.open(dbInfo.name, dbInfo.version);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });

      for (const storeName of db.objectStoreNames) {
        data[dbInfo.name].stores[storeName] = await new Promise((resolve, reject) => {
          const transaction = db.transaction(storeName, 'readonly');
          const store = transaction.objectStore(storeName);
          const request = store.getAll();
          const keyRequest = store.getAllKeys();

          let keys = [];
          keyRequest.onsuccess = () => { keys = keyRequest.result; };

          request.onsuccess = async () => {
            const records = [];
            for (let i = 0; i < request.result.length; i++) {
                let value = request.result[i];
                let isBinary = false;

                // Extremely basic binary check for Blob/File/ArrayBuffer
                if (value instanceof Blob) {
                    value = await blobToBase64(value);
                    isBinary = true;
                }
                // Handle ArrayBuffer etc if needed, but keeping it simpler for now to avoid crashes

                records.push({ key: keys[i], value: value, isBinary: isBinary });
            }
            resolve(records);
          };
          request.onerror = () => reject(request.error);
        });
      }
      db.close();
    }
  } catch (err) {
    console.error("Error extracting IndexedDB:", err);
  }
  return data;
};

const extractCacheStorage = async () => {
    const data = {};
    if (!window.caches) return data;

    try {
        const keys = await caches.keys();
        for (const key of keys) {
            data[key] = [];
            const cache = await caches.open(key);
            const requests = await cache.keys();

            for (const req of requests) {
                const response = await cache.match(req);
                if (response) {
                    const blob = await response.blob();
                    const base64 = await blobToBase64(blob);

                    const headers = {};
                    for (const [headerName, headerValue] of response.headers.entries()) {
                        headers[headerName] = headerValue;
                    }

                    data[key].push({
                        url: req.url,
                        method: req.method,
                        headers: headers,
                        status: response.status,
                        statusText: response.statusText,
                        bodyBase64: base64
                    });
                }
            }
        }
    } catch(err) {
        console.error("Error extracting Cache Storage:", err);
    }
    return data;
};


const restoreLocalStorage = (data) => {
  if (!data) return;
  localStorage.clear();
  for (const [key, value] of Object.entries(data)) {
    localStorage.setItem(key, value);
  }
};

const restoreSessionStorage = (data) => {
  if (!data) return;
  sessionStorage.clear();
  for (const [key, value] of Object.entries(data)) {
    sessionStorage.setItem(key, value);
  }
};

const restoreIndexedDB = async (data) => {
    if (!data || !window.indexedDB) return;

    // Warning: Full structural restore of IndexedDB from scratch is complex due to keys, indexes, and schemas.
    // This makes a best-effort attempt assuming the schema is already created by the web app,
    // or tries to create a simple schema if missing. It will overwrite data in existing stores.
    for (const [dbName, dbData] of Object.entries(data)) {
        try {
            // Get existing databases
            let existingVersion = dbData.version;

            const db = await new Promise((resolve, reject) => {
                // To create stores if they don't exist, we might need a version bump, but we'll stick to
                // the exported version and rely on onupgradeneeded.
                const request = window.indexedDB.open(dbName, dbData.version);

                request.onupgradeneeded = (event) => {
                    const upgradableDb = event.target.result;
                    for (const storeName of Object.keys(dbData.stores)) {
                        if (!upgradableDb.objectStoreNames.contains(storeName)) {
                            // Note: We don't know the exact keyPath or autoIncrement from the simple export.
                            // Assuming no keyPath for a generic restore if missing.
                            upgradableDb.createObjectStore(storeName);
                        }
                    }
                };

                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error);
            });

            for (const [storeName, records] of Object.entries(dbData.stores)) {
                if (db.objectStoreNames.contains(storeName)) {
                    // Pre-process all binary conversions BEFORE starting the transaction
                    // because awaiting async operations (like fetch in base64ToBlob)
                    // causes the IndexedDB transaction to auto-close.
                    const processedRecords = [];
                    for (const record of records) {
                        let value = record.value;
                        if (record.isBinary) {
                            value = await base64ToBlob(record.value);
                        }
                        processedRecords.push({ ...record, value });
                    }

                    await new Promise((resolve, reject) => {
                        const transaction = db.transaction(storeName, 'readwrite');
                        const store = transaction.objectStore(storeName);

                        // Clear existing data in the store
                        store.clear();

                        for (const record of processedRecords) {
                            // If key is undefined, it might be auto-increment or have a keyPath.
                            if (record.key !== undefined && record.key !== null) {
                                store.put(record.value, record.key);
                            } else {
                                store.put(record.value);
                            }
                        }

                        transaction.oncomplete = () => resolve();
                        transaction.onerror = () => reject(transaction.error);
                    });
                } else {
                     console.warn(`Object store ${storeName} does not exist in DB ${dbName}.`);
                }
            }
            db.close();

        } catch (err) {
            console.error(`Error restoring IndexedDB ${dbName}:`, err);
        }
    }
};

const restoreCacheStorage = async (data) => {
    if (!data || !window.caches) return;

    for (const [cacheName, requests] of Object.entries(data)) {
        try {
            // Delete existing cache first to overwrite
            await caches.delete(cacheName);
            const cache = await caches.open(cacheName);

            for (const reqData of requests) {
                const blob = await base64ToBlob(reqData.bodyBase64);
                const response = new Response(blob, {
                    status: reqData.status,
                    statusText: reqData.statusText,
                    headers: reqData.headers
                });

                await cache.put(reqData.url, response);
            }
        } catch(err) {
            console.error(`Error restoring Cache Storage ${cacheName}:`, err);
        }
    }
};

// Listen for messages from the popup
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "ping") {
    sendResponse({ success: true });
    return;
  }

  if (request.action === "detect") {
      (async () => {
          let hasIndexedDB = false;
          if (window.indexedDB && window.indexedDB.databases) {
              try {
                  const dbs = await window.indexedDB.databases();
                  hasIndexedDB = dbs.length > 0;
              } catch(e) {}
          }

          let hasCache = false;
          if (window.caches) {
              try {
                  const keys = await caches.keys();
                  hasCache = keys.length > 0;
              } catch(e) {}
          }

          sendResponse({
            localStorage: localStorage.length > 0,
            sessionStorage: sessionStorage.length > 0,
            indexedDB: hasIndexedDB,
            cacheStorage: hasCache
          });
      })();
      return true; // async response
  }

  if (request.action === "export") {
    (async () => {
        try {
            const data = {
                localStorage: extractLocalStorage(),
                sessionStorage: extractSessionStorage(),
                indexedDB: await extractIndexedDB(),
                cacheStorage: await extractCacheStorage()
            };
            sendResponse({ success: true, data: data });
        } catch(err) {
            sendResponse({ success: false, error: err.message });
        }
    })();
    return true; // Keep message channel open for async response
  }

  if (request.action === "import") {
      (async () => {
          try {
              const data = request.data;
              restoreLocalStorage(data.localStorage);
              restoreSessionStorage(data.sessionStorage);
              await restoreIndexedDB(data.indexedDB);
              await restoreCacheStorage(data.cacheStorage);

              sendResponse({ success: true });
          } catch(err) {
               sendResponse({ success: false, error: err.message });
          }
      })();
      return true; // Keep message channel open
  }
});
