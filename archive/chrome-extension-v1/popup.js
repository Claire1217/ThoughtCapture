const SERVER = "http://127.0.0.1:19876";

document.addEventListener("DOMContentLoaded", async () => {
  const statusEl = document.getElementById("status");
  const contentEl = document.getElementById("content");
  const filePathEl = document.getElementById("file-path");

  try {
    const healthResp = await fetch(`${SERVER}/health`);
    if (!healthResp.ok) throw new Error();
    statusEl.classList.add("online");
  } catch {
    statusEl.classList.add("offline");
    contentEl.innerHTML = `
      <div class="error-msg">
        Server is offline
        <code>cd thought-capture-extension && python3 server.py</code>
      </div>
    `;
    return;
  }

  try {
    const resp = await fetch(`${SERVER}/thoughts`);
    const data = await resp.json();

    if (data.file) {
      filePathEl.textContent = data.file;
    }

    if (!data.content) {
      contentEl.innerHTML = `
        <div class="empty">
          No thoughts captured today yet.<br>
          Select text on any page, press <b>Alt+T</b>
        </div>
      `;
      return;
    }

    contentEl.innerHTML = `<div class="content">${renderMarkdown(data.content)}</div>`;
  } catch {
    contentEl.innerHTML = `<div class="error-msg">Failed to load thoughts</div>`;
  }
});

function renderMarkdown(md) {
  return md
    .replace(/^### (.+)$/gm, "<h3>$1</h3>")
    .replace(/^## (.+)$/gm, "<h2>$1</h2>")
    .replace(/^# (.+)$/gm, "<h1>$1</h1>")
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/^> (.+)$/gm, "<blockquote>$1</blockquote>")
    .replace(/^---$/gm, "<hr>")
    .replace(/\[\[(.+?)\]\]/g, '<a href="#" title="$1">📄 $1</a>')
    .replace(/\n{2,}/g, "<br><br>")
    .replace(/\n/g, "<br>");
}
