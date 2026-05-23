(() => {
  const SERVER = "http://127.0.0.1:19876";
  let currentSelection = "";

  document.addEventListener("mouseup", () => {
    const sel = window.getSelection().toString().trim();
    if (sel.length > 0) currentSelection = sel;
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.action === "open-capture") openCaptureBar();
  });

  function getPageContext() {
    const url = window.location.href;
    const title = document.title;
    const metaDesc = document.querySelector('meta[name="description"]')?.content || "";
    const ogDesc = document.querySelector('meta[property="og:description"]')?.content || "";
    return { url, title, description: ogDesc || metaDesc };
  }

  function openCaptureBar() {
    if (document.getElementById("tc-bar")) return;

    const selectedText = currentSelection || window.getSelection().toString().trim();
    const context = getPageContext();

    const bar = document.createElement("div");
    bar.id = "tc-bar";

    const hint = selectedText
      ? `"${selectedText.slice(0, 40)}${selectedText.length > 40 ? "..." : ""}"`
      : "page";

    bar.innerHTML = `
      <span id="tc-selection-hint">${escapeHtml(hint)}</span>
      <input id="tc-input" type="text" placeholder="thought or command (/pp /plan /summary /expand)..." autofocus>
      <span id="tc-hint">↵ send · esc close</span>
    `;

    document.body.appendChild(bar);

    const input = document.getElementById("tc-input");
    setTimeout(() => input.focus(), 30);

    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        handleInput();
      }
      if (e.key === "Escape") close();
    });

    input.addEventListener("blur", () => {
      setTimeout(() => {
        if (document.getElementById("tc-bar")) close();
      }, 150);
    });

    document.addEventListener("mousedown", function handler(e) {
      if (!bar.contains(e.target)) {
        close();
        document.removeEventListener("mousedown", handler);
      }
    });

    function handleInput() {
      const raw = input.value.trim();
      if (!raw) { close(); return; }

      const payload = {
        input: raw,
        selectedText: selectedText || null,
        url: context.url,
        title: context.title,
        pageDescription: context.description,
        timestamp: new Date().toISOString(),
      };

      input.disabled = true;
      input.style.opacity = "0.5";

      fetch(`${SERVER}/handle`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      })
        .then((r) => r.json())
        .then((resp) => {
          close();
          addPanelItem({
            label: resp.message || raw,
            savedTo: resp.savedTo || "",
            status: resp.taskId ? "running" : "done",
            taskId: resp.taskId || null,
          });
          if (resp.taskId) startPolling();
        })
        .catch(() => {
          close();
          showToast("server offline", true);
        });
    }

    function close() {
      bar.remove();
    }
  }

  function showToast(text, isError) {
    const existing = document.getElementById("tc-toast");
    if (existing) existing.remove();

    const toast = document.createElement("div");
    toast.id = "tc-toast";
    if (isError) toast.style.color = "#f87171";
    toast.textContent = text;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 2500);
  }

  function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }

  // --- Persistent task panel ---

  let polling = false;
  const panelItems = [];  // {id, label, savedTo, status, taskId}
  let itemCounter = 0;

  function ensurePanel() {
    let el = document.getElementById("tc-panel");
    if (!el) {
      el = document.createElement("div");
      el.id = "tc-panel";
      el.innerHTML = `<div id="tc-panel-header">Thought Capture</div><div id="tc-panel-list"></div>`;
      document.body.appendChild(el);
    }
    return el;
  }

  function addPanelItem(item) {
    itemCounter++;
    item.id = `p${itemCounter}`;
    panelItems.push(item);
    renderPanel();
  }

  function renderPanel() {
    if (panelItems.length === 0) return;
    const panel = ensurePanel();
    const list = panel.querySelector("#tc-panel-list");

    list.innerHTML = panelItems.map((item) => {
      let statusHtml;
      if (item.status === "running") {
        statusHtml = `<div class="tc-spinner"></div>`;
      } else if (item.status === "done") {
        statusHtml = `<span class="tc-status-done">done</span>`;
      } else {
        statusHtml = `<span class="tc-status-error">error</span>`;
      }

      const savedTo = item.savedTo
        ? `<span class="tc-saved-to">→ ${escapeHtml(item.savedTo)}</span>`
        : "";

      return `<div class="tc-panel-item" data-id="${item.id}">
        <span class="tc-item-status">${statusHtml}</span>
        <span class="tc-item-content">
          <span class="tc-item-label">${escapeHtml(item.label)}</span>
          ${savedTo}
        </span>
      </div>`;
    }).join("");
  }

  function startPolling() {
    if (polling) return;
    polling = true;
    pollTasks();
  }

  function pollTasks() {
    fetch(`${SERVER}/tasks`)
      .then((r) => r.json())
      .then((data) => {
        const serverTasks = data.tasks || [];
        let changed = false;

        for (const st of serverTasks) {
          const item = panelItems.find((p) => p.taskId === st.id);
          if (item && item.status !== st.status) {
            item.status = st.status;
            if (st.savedTo) item.savedTo = st.savedTo;
            changed = true;
          }
        }

        if (changed) renderPanel();

        const hasRunning = panelItems.some((p) => p.status === "running");
        if (hasRunning) {
          setTimeout(pollTasks, 3000);
        } else {
          polling = false;
        }
      })
      .catch(() => { polling = false; });
  }
})();
