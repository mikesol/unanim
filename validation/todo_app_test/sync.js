const unanimSync = (() => {
  const SYNC_DB_NAME = "unanim_sync_meta";
  const SYNC_DB_VERSION = 1;
  const SYNC_STORE = "meta";

  function openSyncMeta() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(SYNC_DB_NAME, SYNC_DB_VERSION);
      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains(SYNC_STORE)) {
          db.createObjectStore(SYNC_STORE, { keyPath: "key" });
        }
      };
      request.onsuccess = (event) => resolve(event.target.result);
      request.onerror = (event) => reject(event.target.error);
    });
  }

  function getLastSyncedSequence() {
    return openSyncMeta().then((db) => {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(SYNC_STORE, "readonly");
        const store = tx.objectStore(SYNC_STORE);
        const request = store.get("last_synced_sequence");
        request.onsuccess = (event) => {
          db.close();
          const record = event.target.result;
          resolve(record ? record.value : 0);
        };
        request.onerror = (event) => {
          db.close();
          reject(event.target.error);
        };
      });
    });
  }

  function setLastSyncedSequence(seq) {
    return openSyncMeta().then((db) => {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(SYNC_STORE, "readwrite");
        const store = tx.objectStore(SYNC_STORE);
        store.put({ key: "last_synced_sequence", value: seq });
        tx.oncomplete = () => {
          db.close();
          resolve();
        };
        tx.onerror = (event) => {
          db.close();
          reject(event.target.error);
        };
      });
    });
  }

  async function reconcile409(data) {
    // Server rejected our events — accept server state as authoritative
    if (data.server_events && data.server_events.length > 0) {
      await unanimDB.appendEvents(data.server_events);
    }
    const latest = await unanimDB.getLatestEvent();
    if (latest) {
      await setLastSyncedSequence(latest.sequence);
    }
  }

  async function processResponse(response, isProxy) {
    if (!response.ok && response.status !== 409) {
      throw new Error("Sync request failed: " + response.status);
    }
    const data = await response.json();

    if (data.events_accepted) {
      // Store any server events the client hasn't seen
      if (data.server_events && data.server_events.length > 0) {
        await unanimDB.appendEvents(data.server_events);
      }
      // Update last synced sequence to highest known
      const latest = await unanimDB.getLatestEvent();
      if (latest) {
        await setLastSyncedSequence(latest.sequence);
      }
      return isProxy ? data.response : data;
    }

    // 409: server rejected — reconcile and signal retry needed
    if (response.status === 409) {
      await reconcile409(data);
      return { _retry: true, error: data.error };
    }

    return isProxy ? data.response : data;
  }

  async function doFetch(endpoint, body, userId) {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-User-Id": userId
      },
      body: JSON.stringify(body)
    });
    return response;
  }

  async function proxyFetch(workerUrl, url, options) {
    options = options || {};
    const userId = options.userId || "default-user";
    const maxRetries = 1;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      const lastSeq = await getLastSyncedSequence();
      const events = await unanimDB.getEventsSince(lastSeq);

      const body = {
        events_since: lastSeq,
        events: events,
        request: {
          url: url,
          headers: options.headers || {},
          method: options.method || "POST",
          body: options.body || ""
        }
      };

      try {
        const response = await doFetch(workerUrl + "/do/proxy", body, userId);
        const result = await processResponse(response, true);
        if (result && result._retry && attempt < maxRetries) {
          continue;
        }
        if (result && result._retry) {
          return { rejected: true, error: result.error };
        }
        return result;
      } catch (err) {
        // Network error — events are already in IndexedDB (queued)
        throw { offline: true, queued: true, error: err.message };
      }
    }
  }

  async function sync(workerUrl, options) {
    options = options || {};
    const userId = options.userId || "default-user";
    const maxRetries = 1;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      const lastSeq = await getLastSyncedSequence();
      const events = await unanimDB.getEventsSince(lastSeq);

      const body = {
        events_since: lastSeq,
        events: events
      };

      try {
        const response = await doFetch(workerUrl + "/do/sync", body, userId);
        const result = await processResponse(response, false);
        if (result && result._retry && attempt < maxRetries) {
          continue;
        }
        if (result && result._retry) {
          return { rejected: true, error: result.error };
        }
        return result;
      } catch (err) {
        throw { offline: true, queued: true, error: err.message };
      }
    }
  }

  return {
    proxyFetch,
    sync,
    getLastSyncedSequence,
    setLastSyncedSequence
  };
})();
