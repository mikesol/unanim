const unanimDB = (() => {
  const DB_NAME = "unanim_events";
  const DB_VERSION = 1;
  const STORE_NAME = "events";

  function openDatabase() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          const store = db.createObjectStore(STORE_NAME, { keyPath: "sequence" });
          store.createIndex("event_type", "event_type", { unique: false });
          store.createIndex("timestamp", "timestamp", { unique: false });
        }
      };
      request.onsuccess = (event) => {
        resolve(event.target.result);
      };
      request.onerror = (event) => {
        reject(event.target.error);
      };
    });
  }

  function appendEvents(events) {
    return openDatabase().then((db) => {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, "readwrite");
        const store = tx.objectStore(STORE_NAME);
        for (const event of events) {
          store.put(event);
        }
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

  function getEventsSince(sequence) {
    return openDatabase().then((db) => {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, "readonly");
        const store = tx.objectStore(STORE_NAME);
        const range = IDBKeyRange.lowerBound(sequence, true);
        const request = store.openCursor(range);
        const results = [];
        request.onsuccess = (event) => {
          const cursor = event.target.result;
          if (cursor) {
            results.push(cursor.value);
            cursor.continue();
          } else {
            db.close();
            resolve(results);
          }
        };
        request.onerror = (event) => {
          db.close();
          reject(event.target.error);
        };
      });
    });
  }

  function getLatestEvent() {
    return openDatabase().then((db) => {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, "readonly");
        const store = tx.objectStore(STORE_NAME);
        const request = store.openCursor(null, "prev");
        request.onsuccess = (event) => {
          const cursor = event.target.result;
          db.close();
          resolve(cursor ? cursor.value : null);
        };
        request.onerror = (event) => {
          db.close();
          reject(event.target.error);
        };
      });
    });
  }

  function getAllEvents() {
    return openDatabase().then((db) => {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, "readonly");
        const store = tx.objectStore(STORE_NAME);
        const request = store.getAll();
        request.onsuccess = (event) => {
          db.close();
          resolve(event.target.result);
        };
        request.onerror = (event) => {
          db.close();
          reject(event.target.error);
        };
      });
    });
  }

  return {
    openDatabase,
    appendEvents,
    getEventsSince,
    getLatestEvent,
    getAllEvents
  };
})();
