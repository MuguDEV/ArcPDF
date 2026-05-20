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

const arrayBufferToBase64 = (buffer) => {
    let binary = '';
    const bytes = new Uint8Array(buffer);
    const len = bytes.byteLength;
    for (let i = 0; i < len; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return window.btoa(binary);
};

const base64ToArrayBuffer = (base64) => {
    const binary_string = window.atob(base64);
    const len = binary_string.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binary_string.charCodeAt(i);
    }
    return bytes.buffer;
};

// Deep serialization for complex IndexedDB types
const serializeValue = async (value) => {
    if (value === null || value === undefined) {
        return value;
    }

    if (typeof value === 'bigint') {
        return { __type: 'BigInt', value: value.toString() };
    }

    if (value instanceof Date) {
        return { __type: 'Date', value: value.toISOString() };
    }

    if (value instanceof RegExp) {
        return { __type: 'RegExp', source: value.source, flags: value.flags };
    }

    if (value instanceof Blob) {
        const base64 = await blobToBase64(value);
        if (value instanceof File) {
            return { __type: 'File', name: value.name, type: value.type, lastModified: value.lastModified, data: base64 };
        }
        return { __type: 'Blob', type: value.type, data: base64 };
    }

    if (value instanceof ArrayBuffer) {
        return { __type: 'ArrayBuffer', data: arrayBufferToBase64(value) };
    }

    if (ArrayBuffer.isView(value)) {
        const type = value.constructor.name;
        return { __type: 'TypedArray', type: type, data: arrayBufferToBase64(value.buffer) };
    }

    if (value instanceof Map) {
        const entries = [];
        for (const [k, v] of value.entries()) {
            entries.push([await serializeValue(k), await serializeValue(v)]);
        }
        return { __type: 'Map', entries: entries };
    }

    if (value instanceof Set) {
        const entries = [];
        for (const v of value.values()) {
            entries.push(await serializeValue(v));
        }
        return { __type: 'Set', entries: entries };
    }

    if (Array.isArray(value)) {
        const arr = [];
        for (const item of value) {
            arr.push(await serializeValue(item));
        }
        return arr;
    }

    if (typeof value === 'object') {
        const obj = {};
        for (const key in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) {
                obj[key] = await serializeValue(value[key]);
            }
        }
        return obj;
    }

    // primitives (string, number, boolean)
    return value;
};

// Deep deserialization for complex IndexedDB types
const deserializeValue = async (value) => {
    if (value === null || value === undefined) {
        return value;
    }

    if (typeof value === 'object' && value !== null) {
        if (value.__type === 'BigInt') {
            return BigInt(value.value);
        }
        if (value.__type === 'Date') {
            return new Date(value.value);
        }
        if (value.__type === 'RegExp') {
            return new RegExp(value.source, value.flags);
        }
        if (value.__type === 'Blob') {
            const blob = await base64ToBlob(value.data);
            return new Blob([blob], { type: value.type });
        }
        if (value.__type === 'File') {
            const blob = await base64ToBlob(value.data);
            return new File([blob], value.name, { type: value.type, lastModified: value.lastModified });
        }
        if (value.__type === 'ArrayBuffer') {
            return base64ToArrayBuffer(value.data);
        }
        if (value.__type === 'TypedArray') {
            const buffer = base64ToArrayBuffer(value.data);
            const Type = window[value.type];
            return new Type(buffer);
        }
        if (value.__type === 'Map') {
            const map = new Map();
            for (const [k, v] of value.entries) {
                map.set(await deserializeValue(k), await deserializeValue(v));
            }
            return map;
        }
        if (value.__type === 'Set') {
            const set = new Set();
            for (const v of value.entries) {
                set.add(await deserializeValue(v));
            }
            return set;
        }

        if (Array.isArray(value)) {
            const arr = [];
            for (const item of value) {
                arr.push(await deserializeValue(item));
            }
            return arr;
        }

        const obj = {};
        for (const key in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) {
                obj[key] = await deserializeValue(value[key]);
            }
        }
        return obj;
    }

    return value;
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
          // We need to fetch keys and values. To avoid race conditions, wait for both.
          const keysPromise = new Promise((res, rej) => {
              const req = store.getAllKeys();
              req.onsuccess = () => res(req.result);
              req.onerror = () => rej(req.error);
          });
          const valuesPromise = new Promise((res, rej) => {
              const req = store.getAll();
              req.onsuccess = () => res(req.result);
              req.onerror = () => rej(req.error);
          });

          Promise.all([keysPromise, valuesPromise]).then(async ([keys, values]) => {
              const records = [];
              // Serialize asynchronously outside of the active transaction
              for (let i = 0; i < values.length; i++) {
                  const serializedKey = await serializeValue(keys[i]);
                  const serializedValue = await serializeValue(values[i]);
                  records.push({ key: serializedKey, value: serializedValue });
              }
              resolve(records);
          }).catch(err => reject(err));
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
                    // Deserialize all records BEFORE starting the transaction
                    // to prevent the transaction from auto-closing while awaiting promises.
                    const processedRecords = [];
                    for (const record of records) {
                        const deserializedKey = await deserializeValue(record.key);
                        const deserializedValue = await deserializeValue(record.value);
                        processedRecords.push({ key: deserializedKey, value: deserializedValue });
                    }

                    await new Promise((resolve, reject) => {
                        const transaction = db.transaction(storeName, 'readwrite');
                        const store = transaction.objectStore(storeName);

                        // Clear existing data in the store
                        store.clear();

                        for (const record of processedRecords) {
                            // If the store has an in-line key (keyPath), supplying the key explicitly
                            // to put() throws a DataError. We must check for keyPath.
                            if (store.keyPath !== null) {
                                // The key is already inside the object, just put the value
                                store.put(record.value);
                            } else {
                                // Out-of-line keys
                                if (record.key !== undefined && record.key !== null) {
                                    store.put(record.value, record.key);
                                } else {
                                    store.put(record.value);
                                }
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
                let response;

                // Handle opaque responses which have status 0
                if (reqData.status === 0) {
                    // Opaque responses cannot be directly created via `new Response(..., { status: 0 })`.
                    // We mock them as 200 OK since the browser limits our ability to perfectly restore
                    // an opaque response programmatically to a cache.
                    response = new Response(blob, {
                        status: 200,
                        statusText: "OK",
                        headers: reqData.headers
                    });
                } else {
                    response = new Response(blob, {
                        status: reqData.status,
                        statusText: reqData.statusText,
                        headers: reqData.headers
                    });
                }

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
