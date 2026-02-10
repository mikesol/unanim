## validation/todo_app.nim
## Todo reference app: exercises full sync protocol end-to-end.
## Generates Worker+DO deployment artifacts AND a browser Todo app page.
##
## Compile and run: nim c -r validation/todo_app.nim
## Outputs:
##   validation/todo_deploy/worker.js + wrangler.toml
##   validation/todo_app_test/index.html

import ../src/unanim/secret
import ../src/unanim/proxyfetch
import ../src/unanim/codegen
import ../src/unanim/clientgen

# --- Part 1: Artifact generation (compile-time) ---

# Stub proxyFetch so the analyze macro can walk it
proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""

# Register the API call pattern with the analyze macro
analyze:
  discard proxyFetch("https://httpbin.org/post",
    headers = {"Authorization": "Bearer " & secret("test-api-key")},
    body = "test")

# Generate Worker + DO artifacts at compile time
const deployDir = "validation/todo_deploy"
static:
  generateArtifacts("unanim-todo", deployDir)

# --- Part 2: Todo app page generation ---

const workerUrl = "https://unanim-todo.mike-solomon.workers.dev"

const todoAppJs = """
const WORKER_URL = """ & "\"" & workerUrl & "\"" & """;
const log = (msg) => {
  const el = document.getElementById("log");
  if (el) el.textContent += new Date().toLocaleTimeString() + " " + msg + "\n";
  console.log(msg);
};

let nextSequence = 1;

async function init() {
  await unanimDB.openDatabase();
  const events = await unanimDB.getAllEvents();
  if (events.length > 0) {
    nextSequence = events[events.length - 1].sequence + 1;
  }
  renderTodos(events);
  updateStatus();
  log("Todo app initialized. " + events.length + " events loaded from IndexedDB.");
}

function todosFromEvents(events) {
  const todos = {};
  for (const e of events) {
    try {
      const p = JSON.parse(e.payload);
      if (p.action === "add") {
        todos[p.id] = { id: p.id, text: p.text, done: false };
      } else if (p.action === "toggle" && todos[p.id]) {
        todos[p.id].done = !todos[p.id].done;
      } else if (p.action === "delete") {
        delete todos[p.id];
      }
    } catch (err) { /* skip non-todo events */ }
  }
  return Object.values(todos);
}

function renderTodos(events) {
  const todos = todosFromEvents(events);
  const list = document.getElementById("todo-list");
  list.innerHTML = "";
  for (const todo of todos) {
    const li = document.createElement("li");
    li.textContent = (todo.done ? "[x] " : "[ ] ") + todo.text;
    li.style.cursor = "pointer";
    li.style.textDecoration = todo.done ? "line-through" : "none";
    li.onclick = () => toggleTodo(todo.id);
    const delBtn = document.createElement("button");
    delBtn.textContent = "x";
    delBtn.style.marginLeft = "8px";
    delBtn.onclick = (e) => { e.stopPropagation(); deleteTodo(todo.id); };
    li.appendChild(delBtn);
    list.appendChild(li);
  }
  document.getElementById("todo-count").textContent = todos.length + " todos";
}

async function addTodo() {
  const input = document.getElementById("todo-input");
  const text = input.value.trim();
  if (!text) return;
  input.value = "";
  const id = "todo-" + Date.now();
  const event = {
    sequence: nextSequence++,
    timestamp: new Date().toISOString(),
    event_type: "user_action",
    schema_version: 1,
    payload: JSON.stringify({ action: "add", id: id, text: text })
  };
  await unanimDB.appendEvents([event]);
  const events = await unanimDB.getAllEvents();
  renderTodos(events);
  updateStatus();
  log("Added todo: " + text);
}

async function toggleTodo(id) {
  const event = {
    sequence: nextSequence++,
    timestamp: new Date().toISOString(),
    event_type: "user_action",
    schema_version: 1,
    payload: JSON.stringify({ action: "toggle", id: id })
  };
  await unanimDB.appendEvents([event]);
  const events = await unanimDB.getAllEvents();
  renderTodos(events);
  updateStatus();
  log("Toggled todo: " + id);
}

async function deleteTodo(id) {
  const event = {
    sequence: nextSequence++,
    timestamp: new Date().toISOString(),
    event_type: "user_action",
    schema_version: 1,
    payload: JSON.stringify({ action: "delete", id: id })
  };
  await unanimDB.appendEvents([event]);
  const events = await unanimDB.getAllEvents();
  renderTodos(events);
  updateStatus();
  log("Deleted todo: " + id);
}

async function doSync() {
  log("Syncing via proxyFetch...");
  const start = performance.now();
  try {
    const result = await unanimSync.proxyFetch(WORKER_URL,
      "https://httpbin.org/post", {
        method: "POST",
        headers: { "Content-Type": "application/json",
                   "Authorization": "Bearer <<SECRET:test-api-key>>" },
        body: JSON.stringify({ app: "unanim-todo", action: "sync" }),
        userId: "todo-user-1"
      });
    const elapsed = (performance.now() - start).toFixed(0);
    if (result && result.rejected) {
      log("Sync 409 — reconciled. Retried. " + elapsed + "ms");
    } else {
      log("Sync OK. " + elapsed + "ms");
    }
  } catch (err) {
    if (err.offline) {
      log("Offline — events queued locally.");
    } else {
      log("Sync error: " + (err.message || JSON.stringify(err)));
    }
  }
  updateStatus();
}

async function doSyncOnly() {
  log("Sync-only (no API call)...");
  const start = performance.now();
  try {
    const result = await unanimSync.sync(WORKER_URL, {
      userId: "todo-user-1"
    });
    const elapsed = (performance.now() - start).toFixed(0);
    if (result && result.rejected) {
      log("Sync-only 409 — reconciled. " + elapsed + "ms");
    } else {
      log("Sync-only OK. " + elapsed + "ms");
    }
  } catch (err) {
    if (err.offline) {
      log("Offline — events queued locally.");
    } else {
      log("Sync-only error: " + (err.message || JSON.stringify(err)));
    }
  }
  updateStatus();
}

async function updateStatus() {
  const events = await unanimDB.getAllEvents();
  const lastSynced = await unanimSync.getLastSyncedSequence();
  const latest = events.length > 0 ? events[events.length - 1].sequence : 0;
  const unsynced = latest - lastSynced;
  document.getElementById("status").textContent =
    "Local events: " + events.length +
    " | Last synced seq: " + lastSynced +
    " | Unsynced: " + unsynced;
}

// Handle Enter key in input
document.getElementById("todo-input").addEventListener("keydown", (e) => {
  if (e.key === "Enter") addTodo();
});

init();
"""

const todoHtml = "<!DOCTYPE html>\n<html>\n<head><meta charset=\"utf-8\"><title>Unanim Todo</title>\n" &
  "<style>body{font-family:monospace;max-width:600px;margin:20px auto}" &
  "button{margin:2px}li{padding:4px 0}#log{background:#f0f0f0;padding:8px;" &
  "font-size:12px;max-height:200px;overflow-y:auto}</style>\n</head>\n<body>\n" &
  "<h2>Unanim Todo</h2>\n" &
  "<div id=\"status\">Loading...</div>\n" &
  "<div><input id=\"todo-input\" placeholder=\"Add todo...\" />" &
  "<button onclick=\"addTodo()\">Add</button></div>\n" &
  "<ul id=\"todo-list\"></ul>\n" &
  "<div><button onclick=\"doSync()\">Sync (proxyFetch)</button>" &
  "<button onclick=\"doSyncOnly()\">Sync Only</button></div>\n" &
  "<div id=\"todo-count\"></div>\n" &
  "<h3>Log</h3>\n<pre id=\"log\"></pre>\n" &
  "<script>\n" & generateIndexedDBJs() & "\n</script>\n" &
  "<script>\n" & generateSyncJs() & "\n</script>\n" &
  "<script>\n" & todoAppJs & "\n</script>\n" &
  "</body>\n</html>\n"

# --- Part 3: Runtime file output ---

import std/os

let testOutputDir = getCurrentDir() / "validation" / "todo_app_test"
createDir(testOutputDir)
writeFile(testOutputDir / "index.html", todoHtml)

echo "Deployment artifacts generated in: " & deployDir
echo "  - " & deployDir & "/worker.js"
echo "  - " & deployDir & "/wrangler.toml"
echo ""
echo "Todo app page generated at: " & testOutputDir & "/index.html"
echo "Open in browser to exercise the full sync protocol."

