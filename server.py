#!/usr/bin/env python3
"""
Thought Capture Server
Routes captured thoughts to an Obsidian vault. Optionally uses any
OpenAI-compatible LLM API for paper reading, summarization, and idea expansion.
"""

import base64
import json
import os
import re
import threading
import time
import unicodedata
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

# --- Config from .env ---

ENV_FILE = Path(__file__).parent / ".env"
_env = {}
if ENV_FILE.exists():
    for line in ENV_FILE.read_text().strip().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            _env[k.strip()] = v.strip()

LLM_API_KEY = os.environ.get("LLM_API_KEY", _env.get("LLM_API_KEY", ""))
LLM_API_BASE = os.environ.get("LLM_API_BASE", _env.get("LLM_API_BASE", "https://api.deepseek.com/chat/completions"))
LLM_MODEL = os.environ.get("LLM_MODEL", _env.get("LLM_MODEL", "deepseek-chat"))
LLM_MODEL_FAST = os.environ.get("LLM_MODEL_FAST", _env.get("LLM_MODEL_FAST", "deepseek-chat"))
LLM_MODEL_DEEP = os.environ.get("LLM_MODEL_DEEP", _env.get("LLM_MODEL_DEEP", "deepseek-reasoner"))

STORAGE_BACKEND = os.environ.get("STORAGE_BACKEND", _env.get("STORAGE_BACKEND", "obsidian"))  # "obsidian" or "notes"
vault_raw = os.environ.get("VAULT_PATH", _env.get("VAULT_PATH", "~/obsidian"))
VAULT = Path(vault_raw).expanduser()
VAULT_NAME = os.environ.get("VAULT_NAME", _env.get("VAULT_NAME", VAULT.name))
DAILY_DIR = VAULT / "01_daily"
PAPERS_DIR = VAULT / "30_papers"
ATTACHMENTS_DIR = VAULT / "attachments"
if STORAGE_BACKEND == "obsidian":
    ATTACHMENTS_DIR.mkdir(parents=True, exist_ok=True)
PORT = int(os.environ.get("PORT", _env.get("PORT", "19876")))

# Color palette — matches Swift ThoughtBubbleView palette order exactly
THOUGHT_COLORS = ["coral", "blue", "purple", "green", "amber", "olive", "pink", "steel"]
_color_index = 0


# --- LLM API (OpenAI-compatible) ---

def call_llm(system_prompt, user_prompt, max_tokens=1500, model=None, temperature=0.7):
    """Call any OpenAI-compatible API and return the response text."""
    use_model = model or LLM_MODEL
    payload = json.dumps({
        "model": use_model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }).encode()

    req = Request(LLM_API_BASE, data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Bearer {LLM_API_KEY}")

    with urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
        return data["choices"][0]["message"]["content"].strip()


# --- Task tracking ---

tasks = {}
task_counter = 0
tasks_lock = threading.Lock()


def create_task(label, saved_to=""):
    global task_counter
    with tasks_lock:
        task_counter += 1
        tid = f"t{task_counter}"
        tasks[tid] = {
            "id": tid,
            "label": label,
            "status": "running",
            "savedTo": saved_to,
            "started": time.time(),
            "finished": None,
        }
        return tid


def finish_task(tid, success=True, saved_to=None):
    with tasks_lock:
        if tid in tasks:
            tasks[tid]["status"] = "done" if success else "error"
            tasks[tid]["finished"] = time.time()
            if saved_to:
                tasks[tid]["savedTo"] = saved_to


def get_tasks():
    with tasks_lock:
        return list(tasks.values())


def run_async(fn, *args):
    thread = threading.Thread(target=fn, args=args, daemon=True)
    thread.start()


# --- Intent detection ---

COMMANDS = {
    "pr": {
        "patterns": [r"^/pr\b", r"^/pp\b", r"精读", r"读.*这篇", r"读.*paper",
                     r"读.*论文", r"看.*这篇", r"paper\s*reading", r"deep\s*read",
                     r"细读", r"过一遍.*paper", r"过一遍.*论文"],
    },
    "plan": {
        "patterns": [r"^/plan\b", r"今日计划", r"今天.*计划", r"今天.*打算",
                     r"计划一下", r"daily\s*plan", r"today.*plan"],
    },
    "experiment": {
        "patterns": [r"^/exp\b", r"总结.*实验", r"记录.*实验", r"实验.*总结", r"实验.*结果",
                     r"实验.*记录", r"log.*experiment", r"experiment.*summary"],
    },
    "summary": {
        "patterns": [r"^/summary\b", r"总结", r"summarize", r"summarise", r"写.*summary"],
    },
    "expand": {
        "patterns": [r"^/expand\b", r"展开", r"expand", r"发散", r"elaborate"],
    },
}


def detect_intent(text):
    text_lower = text.lower().strip()
    for cmd, info in COMMANDS.items():
        for pattern in info["patterns"]:
            if re.search(pattern, text_lower):
                cleaned = re.sub(pattern, "", text_lower, count=1).strip()
                return cmd, cleaned or text
    return None, text


# --- Obsidian helpers ---

def slugify(text, max_len=80):
    text = unicodedata.normalize("NFKD", text)
    text = re.sub(r"[^\w\s\-]", "", text)
    text = re.sub(r"[\s]+", " ", text).strip()
    return text[:max_len]


def extract_arxiv_id(url):
    m = re.search(r"arxiv\.org/(?:abs|pdf)/(\d{4}\.\d{4,5})", url)
    return m.group(1) if m else None


def extract_paper_id(url):
    if "arxiv.org" in url:
        return extract_arxiv_id(url)
    if "openreview.net" in url:
        m = re.search(r"id=([A-Za-z0-9_-]+)", url)
        return m.group(1) if m else None
    if "pubmed" in url:
        m = re.search(r"/(\d{7,9})", url)
        return m.group(1) if m else None
    return None


def find_existing_paper(url, title):
    paper_id = extract_paper_id(url)
    for f in PAPERS_DIR.glob("*.md"):
        fname = f.stem.lower()
        if paper_id and paper_id.lower() in fname:
            return f.stem
        try:
            content = f.read_text(encoding="utf-8")[:1000]
        except Exception:
            continue
        if paper_id and paper_id in content:
            return f.stem
        if title:
            title_words = [w for w in re.findall(r"\w+", title.lower()) if len(w) > 3]
            if len(title_words) >= 3:
                matches = sum(1 for w in title_words if w in fname)
                if matches >= len(title_words) * 0.6:
                    return f.stem
    return None


def detect_page_type(url):
    if url.startswith("app://"):
        app_name = url.replace("app://", "").lower()
        if app_name in ("preview", "skim", "pdf expert"):
            return "pdf"
        if app_name in ("zotero", "mendeley", "papers"):
            return "reference-manager"
        if app_name in ("visual studio code", "cursor"):
            return "code"
        return "app"

    domain = urlparse(url).netloc.lower()
    mapping = {
        "arxiv.org": "paper", "openreview.net": "paper",
        "pubmed.ncbi.nlm.nih.gov": "paper", "semanticscholar.org": "paper",
        "github.com": "github", "twitter.com": "twitter", "x.com": "twitter",
        "youtube.com": "youtube", "news.ycombinator.com": "hackernews",
        "reddit.com": "reddit", "medium.com": "article", "wikipedia.org": "wikipedia",
    }
    for key, val in mapping.items():
        if key in domain:
            return val
    return "webpage"


def create_paper_stub(title, url, description, thought, selected_text):
    arxiv_id = extract_arxiv_id(url)
    date_str = datetime.now().strftime("%Y-%m-%d")
    safe_title = slugify(title) if title else "Untitled Paper"
    filename = f"{date_str}_{safe_title}.md"
    filepath = PAPERS_DIR / filename
    if filepath.exists():
        return filepath.stem

    lines = ["---", f'title: "{title}"']
    if arxiv_id:
        lines.append(f'arxiv_id: "{arxiv_id}"')
    lines.extend([
        f"url: {url}", f"date_added: {date_str}",
        "status: stub", "tags: [needs-pp]",
        "---", "", f"# {title}", "", f"**Source:** {url}", "",
    ])
    if description:
        lines.extend(["## Abstract / Description", "", description, ""])
    if selected_text:
        lines.extend([f"> {selected_text}", ""])
    if thought:
        lines.extend([f"- {thought}", ""])
    lines.extend(["---", "*Stub note — run `pp` for full paper reading.*"])
    filepath.write_text("\n".join(lines), encoding="utf-8")
    return filepath.stem


def append_to_daily(date_str, content):
    """Append content to daily random thoughts file (Obsidian or Apple Notes)."""
    if STORAGE_BACKEND == "notes":
        append_to_apple_notes(date_str, content)
    else:
        day_dir = DAILY_DIR / date_str
        day_dir.mkdir(parents=True, exist_ok=True)
        daily_file = day_dir / "Daily random thoughts.md"
        if daily_file.exists():
            with open(daily_file, "a", encoding="utf-8") as f:
                f.write(content)
        else:
            with open(daily_file, "w", encoding="utf-8") as f:
                f.write(f"# Random Thoughts — {date_str}\n{content}")


def append_to_apple_notes(date_str, content):
    """Append a thought to Apple Notes. Creates a daily note if needed."""
    import subprocess
    note_title = f"Thoughts — {date_str}"
    # Strip markdown callout syntax for plain text Notes
    plain = re.sub(r'^> \[!thought-\w+\]\s*', '🔵 ', content, flags=re.MULTILINE)
    def quote_to_html(m):
        text = m.group(1)
        return f'<span style="font-style:italic;color:#8e8e93">{text}</span>'
    plain = re.sub(r'^> > (.*)', quote_to_html, plain, flags=re.MULTILINE)
    plain = re.sub(r'^> ', '', plain, flags=re.MULTILINE)
    plain = plain.strip()

    escaped = plain.replace('"', '\\"').replace("\n", "<br>")
    script = f'''
    tell application "Notes"
        set noteFound to false
        repeat with n in notes of default account
            if name of n is "{note_title}" then
                set body of n to (body of n) & "<br><br>" & "{escaped}"
                set noteFound to true
                exit repeat
            end if
        end repeat
        if not noteFound then
            make new note at default account with properties {{name:"{note_title}", body:"{escaped}"}}
        end if
    end tell
    '''
    subprocess.run(["osascript", "-e", script], capture_output=True, timeout=5)


# --- Actions ---

def action_thought(data):
    """Save as thought to daily random thoughts."""
    now = datetime.now()
    date_str = now.strftime("%Y-%m-%d")
    time_str = now.strftime("%H:%M")

    url = data.get("url", "")
    title = data.get("title", "")
    thought = data.get("input", "")
    selected_text = data.get("selectedText")
    page_type = detect_page_type(url)
    description = data.get("pageDescription", "")

    paper_link = None
    paper_created = False

    if page_type == "paper":
        existing = find_existing_paper(url, title)
        if existing:
            paper_link = existing
        else:
            paper_link = create_paper_stub(title, url, description, thought, selected_text)
            paper_created = True

    app_name = data.get("app", "")
    # Source context — always keep a clickable URL when available
    if url and not url.startswith("app://"):
        parsed = urlparse(url)
        display_url = parsed.netloc + (parsed.path if len(parsed.path) <= 40 else parsed.path[:37] + "...")
        source = f"[{display_url}]({url})"
    elif url.startswith("app://"):
        source = app_name if app_name else ""
    else:
        source = ""

    # Colored callout card — color from Swift bubble palette
    global _color_index
    ci = data.get("colorIndex")
    if ci is not None:
        color_name = THOUGHT_COLORS[int(ci) % len(THOUGHT_COLORS)]
    else:
        color_name = THOUGHT_COLORS[_color_index % len(THOUGHT_COLORS)]
        _color_index = (_color_index + 1) % len(THOUGHT_COLORS)

    # Save screenshot if present
    screenshot_filename = None
    screenshot_b64 = data.get("screenshot")
    if screenshot_b64:
        ts = now.strftime("%Y%m%d_%H%M%S")
        screenshot_filename = f"tc_{ts}.png"
        img_path = ATTACHMENTS_DIR / screenshot_filename
        img_path.write_bytes(base64.b64decode(screenshot_b64))

    entry_lines = [""]
    entry_lines.append(f"> [!thought-{color_name}] {time_str}")
    entry_lines.append(f"> {thought}")
    if screenshot_filename:
        entry_lines.append(f"> ![[{screenshot_filename}]]")
    if selected_text:
        # Sanitize content that breaks Obsidian callout nesting
        safe = selected_text
        safe = re.sub(r'^-{3,}\s*$', '– – –', safe, flags=re.MULTILINE)
        safe = re.sub(r'^[═─━┈┉─]{3,}', '———', safe, flags=re.MULTILINE)
        safe = re.sub(r'[═─━]{5,}', '———', safe)  # inline long lines
        safe = safe.replace('```', '` ` `')
        quote_text = safe.replace("\n", "\n> > ")
        source_tag = f" 【{source or app_name}】" if (source or app_name) else ""
        entry_lines.append(f"> > {quote_text}{source_tag}")
    elif source:
        entry_lines.append(f"> {source}")
    entry_lines.append("")

    append_to_daily(date_str, "\n".join(entry_lines))

    saved_to = f"01_daily/{date_str}/Daily random thoughts.md"
    msg = "saved"
    if paper_created:
        msg = "saved + stub created"
        saved_to += f" + 30_papers/{paper_link}.md"
    return {"message": msg, "type": "thought", "savedTo": saved_to}


def fetch_arxiv_abstract(arxiv_id):
    """Fetch paper metadata from arxiv API."""
    try:
        api_url = f"http://export.arxiv.org/api/query?id_list={arxiv_id}"
        req = Request(api_url)
        with urlopen(req, timeout=15) as resp:
            xml = resp.read().decode("utf-8")
        # Extract fields from Atom XML
        def extract_tag(tag):
            m = re.search(f"<{tag}[^>]*>(.*?)</{tag}>", xml, re.DOTALL)
            return m.group(1).strip() if m else ""
        abstract = extract_tag("summary")
        real_title = extract_tag("title")
        # Authors
        authors = re.findall(r"<name>(.*?)</name>", xml)
        # Published year
        published = extract_tag("published")
        year = published[:4] if published else ""
        # Categories
        cats = re.findall(r'category term="([^"]+)"', xml)
        return {
            "title": real_title,
            "abstract": abstract,
            "authors": authors[:5],  # first 5
            "year": year,
            "categories": cats[:3],
        }
    except Exception as e:
        print(f"  arxiv fetch error: {e}")
        return None


def action_pr(data):
    """Paper reading — fetch abstract, generate structured note, save to daily folder."""
    url = data.get("url", "")
    title = data.get("title", "")
    selected = data.get("selectedText", "")
    description = data.get("pageDescription", "")
    input_text = data.get("input", "")

    now = datetime.now()
    date_str = now.strftime("%Y-%m-%d")
    day_dir = DAILY_DIR / date_str
    day_dir.mkdir(parents=True, exist_ok=True)
    paper_file = day_dir / "Daily paper.md"
    saved_to = f"01_daily/{date_str}/Daily paper.md"
    short = (title or url)[:40]
    tid = create_task(f"pr: {short}", saved_to=saved_to)

    def _run():
        try:
            # Try to fetch real abstract from arxiv
            arxiv_meta = None
            arxiv_id = extract_arxiv_id(url) if url else None
            if arxiv_id:
                arxiv_meta = fetch_arxiv_abstract(arxiv_id)

            # Use arxiv metadata if available, fallback to browser data
            real_title = (arxiv_meta or {}).get("title") or title or "Unknown"
            abstract = (arxiv_meta or {}).get("abstract") or description or ""
            authors = (arxiv_meta or {}).get("authors", [])
            year = (arxiv_meta or {}).get("year", "")
            author_str = ", ".join(authors) if authors else "Unknown"

            system = (
                "You are a research paper analyst helping a PhD student (Medical MLLM research). "
                "Write structured paper reading notes. "
                "Use mixed Chinese/English: Chinese for analysis/commentary, English for technical terms. "
                "Be specific — include numbers, architectures, dataset names. "
                "Be critical — note limitations and gaps. "
                "Output ONLY the markdown content below the header (no code fences, no YAML frontmatter).\n\n"
                "REQUIRED sections:\n"
                "## Key Contribution\n"
                "- 3-5 bullet points, what's NEW (not what the paper does)\n"
                "- Quote key claims: 论文原话：\"...\"\n\n"
                "## Method\n"
                "- Technical approach, architecture, training details\n"
                "- Be precise: cite numbers, model names\n\n"
                "## Key Findings\n"
                "- Main results with numbers from experiments\n"
                "- Mark your interpretation with ⚠️\n\n"
                "## Limitations & Open Questions\n"
                "- What's missing, what assumptions are questionable\n\n"
                "## Relevance to My Research\n"
                "- Connect to: Medical MLLM, shortcut learning, visual neglect in VLMs, "
                "domain adaptation, MedGrounder, phrase grounding\n"
                "- Suggest [[wiki links]] to related concepts if applicable\n\n"
                "## One-Line Takeaway\n"
                "- 一句话总结：这篇paper对我最重要的启发是什么\n"
            )

            user_prompt = f"Paper: {real_title}\n"
            if url:
                user_prompt += f"URL: {url}\n"
            if author_str != "Unknown":
                user_prompt += f"Authors: {author_str}\n"
            if year:
                user_prompt += f"Year: {year}\n"
            if abstract:
                user_prompt += f"\nAbstract:\n{abstract}\n"
            if selected:
                user_prompt += f"\nUser-selected excerpt:\n{selected}\n"
            if input_text and not re.match(r"^/pr\b", input_text.strip()):
                # User added context beyond the command
                cleaned = re.sub(r"^/pr\s*", "", input_text).strip()
                cleaned = re.sub(r"精读.*?(这篇|paper|论文)\s*", "", cleaned).strip()
                if cleaned:
                    user_prompt += f"\nUser's note: {cleaned}\n"

            result = call_llm(system, user_prompt, max_tokens=2500, model=LLM_MODEL_DEEP)

            # Build the entry
            time_str = datetime.now().strftime("%H:%M")
            header = f"\n---\n\n# {real_title}\n"
            header += f"*{author_str}*"
            if year:
                header += f" *({year})*"
            header += "\n"
            if url and not url.startswith("app://"):
                header += f"🔗 {url}\n"
            header += f"📅 Read: {date_str} {time_str}\n\n"

            entry = header + result + "\n"

            # Append to daily paper file
            if paper_file.exists():
                with open(paper_file, "a", encoding="utf-8") as f:
                    f.write(entry)
            else:
                with open(paper_file, "w", encoding="utf-8") as f:
                    f.write(entry)

            # Also create/update stub in 30_papers for cross-referencing
            safe = slugify(real_title) if real_title != "Unknown" else "Untitled"
            stub_path = PAPERS_DIR / f"{safe}.md"
            if not stub_path.exists():
                stub_lines = [
                    "---",
                    f'title: "{real_title}"',
                    f"url: {url}",
                    f"date_added: {date_str}",
                    f"status: pr_note",
                    f"tags: [needs-pp]",
                    "---", "",
                    f"# {real_title}", "",
                    f"Quick reading note: [[01_daily/{date_str}/Daily paper]]", "",
                ]
                stub_path.write_text("\n".join(stub_lines), encoding="utf-8")

            finish_task(tid, success=True, saved_to=saved_to)
            print(f"  Task {tid} done: {saved_to}")
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  Task {tid} error: {e}")

    run_async(_run)
    return {"message": f"reading paper...", "type": "command", "taskId": tid, "savedTo": saved_to}


def action_plan(data):
    """Turn spoken/typed plan into structured daily checklist via LLM."""
    now = datetime.now()
    date_str = now.strftime("%Y-%m-%d")
    time_str = now.strftime("%H:%M")
    day_dir = DAILY_DIR / date_str
    day_dir.mkdir(parents=True, exist_ok=True)
    plan_file = day_dir / "Daily plan.md"

    input_text = data.get("input", "")
    saved_to = f"01_daily/{date_str}/Daily plan.md"

    if not LLM_API_KEY:
        # No LLM — just append raw text as bullet points
        lines = [line.strip() for line in input_text.split("，") if line.strip()]
        entry = "\n".join(f"- [ ] {line}" for line in lines)
        if plan_file.exists():
            with open(plan_file, "a", encoding="utf-8") as f:
                f.write(f"\n{entry}")
        else:
            with open(plan_file, "w", encoding="utf-8") as f:
                f.write(entry)
        return {"message": "plan saved", "type": "plan", "savedTo": saved_to}

    # Use LLM to structure the spoken plan
    tid = create_task(f"plan: {input_text[:30]}", saved_to=saved_to)

    def _run():
        try:
            system = (
                "You are a daily planner. The user will ramble about their day — "
                "extract tasks AND distill the key context.\n\n"
                "Output TWO sections, exactly this format:\n\n"
                "TASKS:\n"
                "- [ ] task text #urgent-important\n"
                "- [ ] task text #urgent\n"
                "- [ ] task text #important\n"
                "- [ ] task text\n\n"
                "CONTEXT:\n"
                "A brief paragraph (2-4 sentences) capturing the user's current state, "
                "key decisions they're wrestling with, and important background. "
                "This helps future-self understand WHY these tasks exist.\n\n"
                "Task rules:\n"
                "- FLAT list, no nesting, concise\n"
                "- NUMBER each item: `- [ ] 1. task text`\n"
                "- Add priority tag: #urgent-important > #urgent > #important > (none)\n"
                "- SORT by priority\n"
                "- If deadline context exists (明天要汇报), keep as parenthetical\n"
                "- Merge related sub-points into ONE task\n"
                "- Filter out past events, only TODAY's actions\n\n"
                "Context rules:\n"
                "- Distill, don't copy — compress rambling into insight\n"
                "- Capture: current status, open questions, key comparisons, blockers\n"
                "- Use the user's language (Chinese/English mix)\n"
                "- 2-4 sentences max"
            )
            raw = call_llm(system, f"Plan from:\n{input_text}", max_tokens=1000)

            # Parse TASKS and CONTEXT sections
            tasks_part = raw
            context_part = ""
            if "CONTEXT:" in raw:
                parts = raw.split("CONTEXT:", 1)
                tasks_part = parts[0]
                context_part = parts[1].strip()
            if "TASKS:" in tasks_part:
                tasks_part = tasks_part.split("TASKS:", 1)[1]
            tasks_part = tasks_part.strip()

            # Build the final output
            result = tasks_part
            if context_part:
                result += f"\n\n> [!info]- Background\n> {context_part}"

            if plan_file.exists():
                with open(plan_file, "a", encoding="utf-8") as f:
                    f.write(f"\n{result}")
            else:
                with open(plan_file, "w", encoding="utf-8") as f:
                    f.write(result)

            finish_task(tid, success=True, saved_to=saved_to)
            print(f"  Task {tid} done: plan written")
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  Task {tid} error: {e}")

    run_async(_run)
    return {"message": "planning...", "type": "plan", "taskId": tid, "savedTo": saved_to}


def action_summary(data):
    """Summarize page/selection via DeepSeek, write to daily notes."""
    url = data.get("url", "")
    title = data.get("title", "")
    selected = data.get("selectedText", "")
    description = data.get("pageDescription", "")
    short = (title or url)[:40]
    date_str = datetime.now().strftime("%Y-%m-%d")
    saved_to = f"01_daily/{date_str}/Daily random thoughts.md"
    tid = create_task(f"summary: {short}", saved_to=saved_to)

    def _run():
        try:
            system = (
                "You are a concise research summarizer. Write in mixed Chinese/English "
                "(technical terms in English, narrative in Chinese). "
                "Output ONLY the summary text, no markdown headers, no code fences. "
                "Keep it under 200 words."
            )
            context = f"Page: {title}\nURL: {url}\nDescription: {description}"
            if selected:
                context += f"\n\nSelected text:\n{selected}"

            result = call_llm(system, f"Summarize:\n{context}")

            time_str = datetime.now().strftime("%H:%M")
            entry = (
                f"\n\n### {time_str} — Summary: {title or url}\n\n"
                f"**URL:** {url}\n\n"
                f"{result}\n\n---"
            )
            append_to_daily(date_str, entry)

            finish_task(tid, success=True)
            print(f"  Task {tid} done: summary written")
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  Task {tid} error: {e}")

    run_async(_run)
    return {"message": f"summarizing: {short}...", "type": "command", "taskId": tid}


def action_expand(data):
    """Expand idea via DeepSeek, write to daily notes."""
    url = data.get("url", "")
    title = data.get("title", "")
    selected = data.get("selectedText", "")
    input_text = data.get("input", "")
    _, user_thought = detect_intent(input_text)
    short = (title or url)[:40]
    date_str = datetime.now().strftime("%Y-%m-%d")
    saved_to = f"01_daily/{date_str}/Daily random thoughts.md"
    tid = create_task(f"expand: {short}", saved_to=saved_to)

    def _run():
        try:
            system = (
                "You are a research ideation assistant. "
                "Expand and develop the given idea with depth and creativity. "
                "Output ONLY the expanded thoughts, no code fences. Keep it focused and under 300 words."
            )
            context = f"Page: {title}\nURL: {url}"
            if selected:
                context += f"\nSelected text: {selected}"
            if user_thought and user_thought != input_text:
                context += f"\nMy thought direction: {user_thought}"

            result = call_llm(system, f"Expand this idea:\n{context}")

            time_str = datetime.now().strftime("%H:%M")
            entry = (
                f"\n\n### {time_str} — Expanded Idea: {title or url}\n\n"
                f"**URL:** {url}\n\n"
            )
            if selected:
                entry += f"> {selected}\n\n"
            entry += f"{result}\n\n---"
            append_to_daily(date_str, entry)

            finish_task(tid, success=True)
            print(f"  Task {tid} done: idea expanded")
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  Task {tid} error: {e}")

    run_async(_run)
    return {"message": "expanding idea...", "type": "command", "taskId": tid}


def action_experiment(data):
    """Summarize experiment chat into structured notes in daily Experiments.md."""
    input_text = data.get("input", "")
    selected = data.get("selectedText", "")
    app_name = data.get("app", "")
    title = data.get("title", "")

    date_str = datetime.now().strftime("%Y-%m-%d")
    exp_file = DAILY_DIR / date_str / "Experiments.md"
    saved_to = f"01_daily/{date_str}/Experiments"
    tid = create_task(f"experiment log", saved_to=saved_to)

    content = selected if selected else input_text

    def _run():
        try:
            system = (
                "You are a research experiment logger. The user will paste a raw chat log "
                "from their coding/experiment session (Claude Code, VSCode, terminal, etc.). "
                "Your job: extract and structure the key experiment information.\n\n"
                "Output format (markdown):\n"
                "## Experiment Title (infer from content)\n\n"
                "**Goal:** one sentence\n"
                "**Setup:** model, dataset, conditions, parameters\n"
                "**Key Results:**\n- bullet points with specific numbers\n"
                "**Findings:**\n- interpretive bullet points\n"
                "**Next Steps:**\n- what to do next (if mentioned)\n\n"
                "Rules:\n"
                "- Use mixed Chinese/English (technical terms English, narrative Chinese)\n"
                "- Keep tables if they contain important data — clean up formatting\n"
                "- Be thorough — extract ALL findings, don't skip\n"
                "- Strip tool output noise (file paths, ctrl+o prompts, progress bars)\n"
                "- Preserve specific numbers, percentages, model names exactly\n"
                "- Output ONLY the structured notes, no explanations"
            )

            result = call_llm(system, content, max_tokens=3000)

            # Ensure file exists
            exp_file.parent.mkdir(parents=True, exist_ok=True)
            time_str = datetime.now().strftime("%H:%M")

            if exp_file.exists():
                existing = exp_file.read_text(encoding="utf-8")
                new_content = existing.rstrip() + f"\n\n---\n\n*{time_str}*\n\n{result}\n"
            else:
                new_content = f"*{time_str}*\n\n{result}\n"

            exp_file.write_text(new_content, encoding="utf-8")
            finish_task(tid, success=True, saved_to=saved_to)
            print(f"  Task {tid} done: experiment logged")
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  Task {tid} error: {e}")

    run_async(_run)
    return {"message": "logging experiment...", "type": "task", "taskId": tid, "savedTo": saved_to}


def _quick_classify(input_text, selected_text):
    """Fast keyword-based classification for obvious patterns. Returns None if unsure."""
    t = input_text.strip().lower()

    # Question — explicit prefix "问一下" / "问："
    q_prefix = ["问一下", "问:", "问：", "问 "]
    if any(t.startswith(k) for k in q_prefix):
        return "question"

    # Polish / translate — user explicitly asks to polish/rewrite/translate
    polish_kw = ["润色", "polish", "rewrite", "改写", "帮我润色", "润一下", "帮我改写",
                 "翻译", "translate", "帮我翻译"]
    if any(k in t for k in polish_kw):
        if selected_text:
            return "polish"

    # Edit — explicit modification intent
    edit_kw = ["帮我改", "帮我删", "帮我修改", "帮我调整", "帮我排序", "删掉", "删除",
               "重新排", "调整顺序", "合并一下"]
    if any(k in t for k in edit_kw):
        return "edit"

    return None


def classify_intent(input_text, selected_text, app_name):
    """Use LLM to classify user intent. Returns one of: thought, plan, question, polish, edit, experiment."""
    context_parts = [f"User said: {input_text}"]
    if selected_text:
        context_parts.append(f"Selected text: {selected_text[:200]}")
    if app_name:
        context_parts.append(f"App: {app_name}")

    system = (
        "Classify the user's intent into exactly ONE category. Reply with ONLY the category name.\n\n"
        "Categories:\n"
        "- thought: random idea, observation, note to self, anything to just record\n"
        "- plan: describing today's tasks/schedule/plans, wants a structured to-do list\n"
        "- question: asking a specific question that expects an answer\n"
        "- polish: wants to polish/rewrite/improve/润色/翻译/translate the selected text\n"
        "- edit: wants to modify/delete/reorder/add content in the current document (帮我修改/删掉/调整/排序/合并...)\n"
        "- experiment: wants to summarize or log experiment results\n\n"
        "Reply with ONLY one word: thought/plan/question/polish/edit/experiment"
    )
    try:
        result = call_llm(system, "\n".join(context_parts), max_tokens=10, model=LLM_MODEL_FAST, temperature=0)
        label = result.strip().lower().split()[0].rstrip(".,;:")
        if label in ("thought", "plan", "question", "polish", "edit", "experiment"):
            return label
    except Exception as e:
        print(f"  classify error: {e}")
    return "thought"


def action_question(data):
    """Handle AI requests. If selected text is editable, output replacement text and paste back."""
    input_text = data.get("input", "")
    # Strip question prefix
    for prefix in ["问一下", "问:", "问：", "问 "]:
        if input_text.strip().lower().startswith(prefix):
            input_text = input_text.strip()[len(prefix):].strip()
            break
    selected = data.get("selectedText", "")
    editable = data.get("editable", False)
    tid = create_task("thinking...")

    # If editable + selected text → replacement mode (paste back via Cmd+V)
    replace_mode = bool(selected and editable)

    def _run():
        try:
            if selected and replace_mode:
                system = (
                    "The user selected some text in an editable field and gave an instruction. "
                    "Apply the instruction to the selected text. "
                    "Output ONLY the resulting text, nothing else — no explanation, no quotes, no markdown. "
                    "The output will directly replace the selected text."
                )
                context = f"Instruction: {input_text}\n\nSelected text:\n{selected}"
                result = call_llm(system, context, max_tokens=1000)
                finish_task(tid, success=True)
                with tasks_lock:
                    tasks[tid]["polished"] = result
            elif selected:
                system = (
                    "The user selected the following text and is asking about it. "
                    "Answer their question based on the selected content. "
                    "Answer concisely in the same language the user used. "
                    "Keep it under 100 words. Be direct."
                )
                context = f"Selected text:\n{selected}\n\nQuestion: {input_text}"
                result = call_llm(system, context, max_tokens=300)
                finish_task(tid, success=True)
                with tasks_lock:
                    tasks[tid]["answer"] = result
            else:
                system = (
                    "You are a helpful assistant. Answer concisely in the same language the user used. "
                    "Keep it under 100 words. Be direct."
                )
                context = input_text
                result = call_llm(system, context, max_tokens=300)
                finish_task(tid, success=True)
                with tasks_lock:
                    tasks[tid]["answer"] = result
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  question error: {e}")

    run_async(_run)
    # "polish" type triggers paste-back in Swift; "question" shows in bubble
    resp_type = "polish" if replace_mode else "question"
    return {"message": "thinking...", "type": resp_type, "taskId": tid}


def action_polish(data):
    """Polish selected text via LLM, return polished text for clipboard paste-back."""
    selected = data.get("selectedText", "")
    input_text = data.get("input", "")
    if not selected:
        return action_thought(data)

    tid = create_task("polishing...")

    def _run():
        try:
            system = (
                "You are a text polisher. The user has selected some text and wants it improved. "
                "Polish the text: fix grammar, improve clarity, make it more concise and professional. "
                "Keep the same language and meaning. Output ONLY the polished text, nothing else."
            )
            context = f"User instruction: {input_text}\n\nText to polish:\n{selected}"
            result = call_llm(system, context, max_tokens=1000)
            finish_task(tid, success=True)
            with tasks_lock:
                tasks[tid]["polished"] = result
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  polish error: {e}")

    run_async(_run)
    return {"message": "polishing...", "type": "polish", "taskId": tid}


ACTION_MAP = {
    "pr": action_pr,
    "plan": action_plan,
    "experiment": action_experiment,
    "summary": action_summary,
    "expand": action_expand,
}


# --- Obsidian edit ---

def action_obsidian_edit(data):
    """Use LLM to edit Obsidian content based on user instruction."""
    input_text = data.get("input", "")
    selected = data.get("selectedText", "")
    title = data.get("title", "")  # window title = note name in Obsidian

    # Find the file — Obsidian window title is usually "Note Name - Vault - Obsidian"
    note_name = title
    for suffix in [" - Obsidian", " - obsidian-brain", " — Obsidian", " — obsidian-brain"]:
        note_name = note_name.replace(suffix, "")
    # Also strip vault name if present: "Note - vaultname" → "Note"
    if " - " in note_name:
        note_name = note_name.rsplit(" - ", 1)[0].strip()
    note_name = note_name.strip()
    target_file = None

    # Search for the file in vault (exact stem match, then fuzzy)
    for f in VAULT.rglob("*.md"):
        if f.stem == note_name:
            target_file = f
            break
    if not target_file:
        # Fuzzy: check if note_name is contained in stem
        for f in VAULT.rglob("*.md"):
            if note_name.lower() in f.stem.lower():
                target_file = f
                break

    if not target_file or not target_file.exists():
        print(f"  ⚠ Could not find file for note: '{note_name}' (title: '{title}')")
        return action_thought(data)

    original = target_file.read_text(encoding="utf-8")
    saved_to = str(target_file.relative_to(VAULT))
    tid = create_task(f"edit: {note_name[:30]}", saved_to=saved_to)

    def _run():
        try:
            system = (
                "You are an Obsidian note editor. The user has a note open and wants to modify it. "
                "They may have selected specific text and given an instruction about what to change. "
                "Apply their instruction to the note content. Rules:\n"
                "- Return the COMPLETE modified file content\n"
                "- Only change what the user asked for — preserve everything else exactly\n"
                "- If they talk about priority/reordering, reorder the items\n"
                "- If they want to add/remove/edit items, do so\n"
                "- Keep the same markdown format (checkboxes, callouts, etc.)\n"
                "- Output ONLY the file content, no explanations or code fences"
            )
            context = f"File: {note_name}\n\n"
            context += f"Full file content:\n{original}\n\n"
            if selected:
                context += f"User selected this text:\n{selected}\n\n"
            context += f"User instruction: {input_text}"

            result = call_llm(system, context, max_tokens=2000)

            # Write back
            target_file.write_text(result, encoding="utf-8")
            finish_task(tid, success=True, saved_to=saved_to)
            print(f"  Task {tid} done: edited {note_name}")
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  Task {tid} error: {e}")

    run_async(_run)
    return {"message": f"editing {note_name}...", "type": "edit", "taskId": tid, "savedTo": saved_to}


def action_plan_edit(data):
    """Use LLM to modify today's plan based on user instruction."""
    input_text = data.get("input", "")
    selected = data.get("selectedText", "")
    pf = _plan_file_today()
    date_str = datetime.now().strftime("%Y-%m-%d")
    saved_to = f"01_daily/{date_str}/Daily plan.md"

    if not pf.exists():
        return action_thought(data)  # no plan to edit, save as thought

    original = pf.read_text(encoding="utf-8")
    tid = create_task(f"plan edit: {input_text[:30]}", saved_to=saved_to)

    def _run():
        try:
            system = (
                "You are editing a daily plan checklist. The user wants to modify it. "
                "Apply their instruction precisely. Rules:\n"
                "- Return the COMPLETE modified checklist\n"
                "- Keep `- [ ]` / `- [x]` format for all items\n"
                "- Items are numbered: `- [ ] 1. task` — maintain numbering after edits\n"
                "- When splitting a task (e.g. task 1), use sub-numbers: 1.1, 1.2, 1.3\n"
                "- Preserve tags (#urgent-important, #urgent, #important)\n"
                "- Preserve the Background callout section if it exists\n"
                "- Only change what the user asked for\n"
                "- Output ONLY the file content, no explanations"
            )
            context = f"Current plan:\n{original}\n\n"
            if selected:
                context += f"User selected:\n{selected}\n\n"
            context += f"User instruction: {input_text}"

            result = call_llm(system, context, max_tokens=2000)
            pf.write_text(result, encoding="utf-8")
            finish_task(tid, success=True, saved_to=saved_to)
            print(f"  Task {tid} done: plan edited")
        except Exception as e:
            finish_task(tid, success=False)
            print(f"  Task {tid} error: {e}")

    run_async(_run)
    return {"message": "editing plan...", "type": "edit", "taskId": tid, "savedTo": saved_to}


# --- Plan helpers ---

def _plan_file_today():
    date_str = datetime.now().strftime("%Y-%m-%d")
    return DAILY_DIR / date_str / "Daily plan.md"


def get_today_plan():
    """Read today's plan, return structured items."""
    pf = _plan_file_today()
    date_str = datetime.now().strftime("%Y-%m-%d")
    file_path = f"01_daily/{date_str}/Daily plan"
    if not pf.exists():
        return {"items": [], "file": file_path}
    lines = pf.read_text(encoding="utf-8").splitlines()
    items = []
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("- [x]") or stripped.startswith("- [X]"):
            items.append({"text": stripped[6:].strip(), "done": True, "line": i})
        elif stripped.startswith("- [ ]"):
            items.append({"text": stripped[6:].strip(), "done": False, "line": i})
    return {"items": items, "file": file_path}


def toggle_plan_item(index):
    """Toggle a plan item's checkbox by index in the items list."""
    pf = _plan_file_today()
    if not pf.exists() or index < 0:
        return {"ok": False}
    lines = pf.read_text(encoding="utf-8").splitlines()
    plan = get_today_plan()
    if index >= len(plan["items"]):
        return {"ok": False}
    item = plan["items"][index]
    line_no = item["line"]
    if item["done"]:
        lines[line_no] = lines[line_no].replace("- [x]", "- [ ]").replace("- [X]", "- [ ]")
    else:
        lines[line_no] = lines[line_no].replace("- [ ]", "- [x]")
    pf.write_text("\n".join(lines), encoding="utf-8")
    return {"ok": True, "done": not item["done"]}


# --- HTTP Server ---

class Handler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(200)
        self._cors_headers()
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length else {}
        if self.path == "/handle":
            result = self.route(body)
            self._json_response(200, result)
        elif self.path == "/plan/toggle":
            result = toggle_plan_item(body.get("index", -1))
            self._json_response(200, result)
        elif self.path == "/config":
            self._save_config(body)
        elif self.path == "/config/test-llm":
            self._test_llm(body)
        else:
            self._json_response(404, {"error": "not found"})

    def do_GET(self):
        if self.path == "/health":
            self._json_response(200, {"status": "ok", "vault": str(VAULT)})
        elif self.path == "/config":
            self._json_response(200, {
                "vaultName": VAULT_NAME,
                "vaultPath": str(VAULT),
                "storage": STORAGE_BACKEND,
                "hasLLM": bool(LLM_API_KEY),
                "llmApiBase": LLM_API_BASE,
                "llmModel": LLM_MODEL,
            })
        elif self.path == "/tasks":
            self._json_response(200, {"tasks": get_tasks()})
        elif self.path == "/plan":
            self._json_response(200, get_today_plan())
        else:
            self._json_response(404, {"error": "not found"})

    def _save_config(self, body):
        """Write settings to .env and update globals (requires server restart for full effect)."""
        global STORAGE_BACKEND, VAULT, VAULT_NAME, DAILY_DIR, PAPERS_DIR, ATTACHMENTS_DIR
        global LLM_API_KEY, LLM_API_BASE, LLM_MODEL

        key_map = {
            "storage": "STORAGE_BACKEND",
            "vaultPath": "VAULT_PATH",
            "vaultName": "VAULT_NAME",
            "llmApiKey": "LLM_API_KEY",
            "llmApiBase": "LLM_API_BASE",
            "llmModel": "LLM_MODEL",
        }

        # Read existing .env lines (preserve comments and unknown keys)
        env_lines = []
        existing_keys = set()
        if ENV_FILE.exists():
            for line in ENV_FILE.read_text().splitlines():
                stripped = line.strip()
                if stripped and not stripped.startswith("#") and "=" in stripped:
                    k = stripped.split("=", 1)[0].strip()
                    if k in key_map.values():
                        existing_keys.add(k)
                        # Will be rewritten below
                        continue
                env_lines.append(line)

        # Build new key=value pairs
        for json_key, env_key in key_map.items():
            if json_key in body:
                val = str(body[json_key])
                env_lines.append(f"{env_key}={val}")
                existing_keys.add(env_key)
            elif env_key in _env:
                # Keep existing value
                env_lines.append(f"{env_key}={_env[env_key]}")

        ENV_FILE.write_text("\n".join(env_lines) + "\n")

        # Update live globals
        if "storage" in body:
            STORAGE_BACKEND = body["storage"]
        if "vaultPath" in body:
            VAULT = Path(body["vaultPath"]).expanduser()
            DAILY_DIR = VAULT / "01_daily"
            PAPERS_DIR = VAULT / "30_papers"
            ATTACHMENTS_DIR = VAULT / "attachments"
            if STORAGE_BACKEND == "obsidian":
                ATTACHMENTS_DIR.mkdir(parents=True, exist_ok=True)
        if "vaultName" in body:
            VAULT_NAME = body["vaultName"]
        if "llmApiKey" in body:
            LLM_API_KEY = body["llmApiKey"]
        if "llmApiBase" in body:
            LLM_API_BASE = body["llmApiBase"]
        if "llmModel" in body:
            LLM_MODEL = body["llmModel"]

        self._json_response(200, {"ok": True, "vaultName": VAULT_NAME, "storage": STORAGE_BACKEND})

    def _test_llm(self, body):
        """Quick LLM connectivity test — send a tiny prompt and check for a response."""
        api_key = body.get("apiKey", LLM_API_KEY)
        api_base = body.get("apiBase", LLM_API_BASE)
        model = body.get("model", LLM_MODEL)
        if not api_key:
            self._json_response(400, {"ok": False, "error": "No API key"})
            return
        try:
            payload = json.dumps({"model": model, "messages": [{"role": "user", "content": "Say hi"}], "max_tokens": 5}).encode()
            req = Request(api_base, data=payload, method="POST")
            req.add_header("Content-Type", "application/json")
            req.add_header("Authorization", f"Bearer {api_key}")
            with urlopen(req, timeout=10) as resp:
                result = json.loads(resp.read())
                reply = result.get("choices", [{}])[0].get("message", {}).get("content", "")
                self._json_response(200, {"ok": True, "reply": reply})
        except Exception as e:
            self._json_response(200, {"ok": False, "error": str(e)[:200]})

    def route(self, data):
        input_text = data.get("input", "")
        app_name = data.get("app", "")
        selected = data.get("selectedText", "")

        # Rule: starts with "/" → AI handles it; otherwise → thought
        # Accept both half-width / and full-width ／ (Chinese IME often produces ／)
        stripped = input_text.strip()
        if stripped.startswith("／"):
            stripped = "/" + stripped[1:]
        if stripped.startswith("/"):
            ai_text = stripped[1:].strip()
            if not ai_text:
                return action_thought(data)
            data = {**data, "input": ai_text}

            # 1. Explicit slash commands (/pr, /plan, /exp etc.)
            intent, _ = detect_intent(ai_text)
            if intent and intent in ACTION_MAP:
                print(f"  → command: {intent}")
                return ACTION_MAP[intent](data)

            # 2. All other /xxx → let AI handle it directly
            print(f"  → ai (editable={data.get('editable', False)})")
            return action_question(data)

        # No "/" prefix → save as thought (instant, no LLM)
        print(f"  → thought")
        return action_thought(data)

    def _json_response(self, code, data):
        self.send_response(code)
        self._cors_headers()
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def log_message(self, format, *args):
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {args[0]}")


if __name__ == "__main__":
    if not LLM_API_KEY:
        print("WARNING: LLM_API_KEY not set! LLM commands will fail.")
    print(f"Thought Capture server on http://localhost:{PORT}")
    print(f"Vault: {VAULT}")
    print(f"LLM: fast={LLM_MODEL_FAST} | default={LLM_MODEL} | deep={LLM_MODEL_DEEP}")
    print(f"API: {LLM_API_BASE}")
    print(f"Commands: {', '.join(COMMANDS.keys())}")
    print()
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
