#!/usr/bin/env /opt/homebrew/bin/python3
"""Tests for the Thought Capture server."""

import json
import os
import shutil
import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

# Patch VAULT before importing server
TEST_VAULT = Path(tempfile.mkdtemp(prefix="tc-test-"))
(TEST_VAULT / "01_daily").mkdir()
(TEST_VAULT / "30_papers").mkdir()

import server
server.VAULT = TEST_VAULT
server.DAILY_DIR = TEST_VAULT / "01_daily"
server.PAPERS_DIR = TEST_VAULT / "30_papers"

passed = 0
failed = 0

def test(name):
    global passed, failed
    def decorator(fn):
        global passed, failed
        try:
            fn()
            print(f"  PASS  {name}")
            passed += 1
        except Exception as e:
            print(f"  FAIL  {name}: {e}")
            failed += 1
    return decorator


# --- Intent detection ---

@test("detect plain thought")
def _():
    intent, text = server.detect_intent("interesting finding here")
    assert intent is None, f"expected None, got {intent}"

@test("detect /pp command")
def _():
    intent, _ = server.detect_intent("/pp https://arxiv.org/abs/2605.14621")
    assert intent == "pp"

@test("detect 精读 command")
def _():
    intent, _ = server.detect_intent("精读这篇paper")
    assert intent == "pp"

@test("detect /plan command")
def _():
    intent, _ = server.detect_intent("/plan review results")
    assert intent == "plan"

@test("detect 加到plan command")
def _():
    intent, _ = server.detect_intent("加到plan里 review shortcut paper")
    assert intent == "plan"

@test("detect /summary command")
def _():
    intent, _ = server.detect_intent("/summary")
    assert intent == "summary"

@test("detect 总结 command")
def _():
    intent, _ = server.detect_intent("总结一下这篇paper")
    assert intent == "summary"

@test("detect /expand command")
def _():
    intent, _ = server.detect_intent("/expand this idea")
    assert intent == "expand"

@test("detect 展开 command")
def _():
    intent, _ = server.detect_intent("展开这个想法")
    assert intent == "expand"


# --- Page type detection ---

@test("detect arxiv as paper")
def _():
    assert server.detect_page_type("https://arxiv.org/abs/2605.14621") == "paper"

@test("detect arxiv pdf as paper")
def _():
    assert server.detect_page_type("https://arxiv.org/pdf/2605.14621") == "paper"

@test("detect github")
def _():
    assert server.detect_page_type("https://github.com/foo/bar") == "github"

@test("detect regular webpage")
def _():
    assert server.detect_page_type("https://example.com") == "webpage"

@test("detect app:// Preview as pdf")
def _():
    assert server.detect_page_type("app://Preview") == "pdf"

@test("detect app:// Zotero as reference-manager")
def _():
    assert server.detect_page_type("app://Zotero") == "reference-manager"

@test("detect app:// Visual Studio Code as code")
def _():
    assert server.detect_page_type("app://Visual Studio Code") == "code"

@test("detect app:// unknown as app")
def _():
    assert server.detect_page_type("app://Notes") == "app"


# --- arXiv ID extraction ---

@test("extract arxiv id from abs url")
def _():
    assert server.extract_arxiv_id("https://arxiv.org/abs/2605.14621") == "2605.14621"

@test("extract arxiv id from pdf url")
def _():
    assert server.extract_arxiv_id("https://arxiv.org/pdf/2406.12345") == "2406.12345"

@test("no arxiv id from non-arxiv url")
def _():
    assert server.extract_arxiv_id("https://example.com") is None


# --- Thought saving ---

@test("save basic thought to daily note")
def _():
    data = {
        "input": "test thought",
        "selectedText": "some highlighted text",
        "url": "https://example.com/page",
        "title": "Test Page",
        "pageDescription": "",
    }
    result = server.action_thought(data)
    assert result["type"] == "thought"
    assert "saved" in result["message"]
    assert "Daily random thoughts.md" in result["savedTo"]

    date_str = datetime.now().strftime("%Y-%m-%d")
    daily_file = TEST_VAULT / "01_daily" / date_str / "Daily random thoughts.md"
    assert daily_file.exists(), "daily note file not created"
    content = daily_file.read_text()
    assert "test thought" in content, "thought not in file"
    assert "> some highlighted text" in content, "selected text not in file"
    assert "https://example.com/page" in content, "URL not in file"

@test("save thought with selected text preserved")
def _():
    data = {
        "input": "my idea about this",
        "selectedText": "This is the exact text I highlighted on the page",
        "url": "https://example.com/article",
        "title": "Article",
        "pageDescription": "",
    }
    result = server.action_thought(data)
    date_str = datetime.now().strftime("%Y-%m-%d")
    daily_file = TEST_VAULT / "01_daily" / date_str / "Daily random thoughts.md"
    content = daily_file.read_text()
    assert "> This is the exact text I highlighted on the page" in content
    assert "my idea about this" in content

@test("save thought without selected text")
def _():
    data = {
        "input": "random thought no selection",
        "selectedText": None,
        "url": "https://example.com",
        "title": "Page",
        "pageDescription": "",
    }
    result = server.action_thought(data)
    assert result["message"] == "saved"

@test("save thought creates paper stub for arxiv")
def _():
    data = {
        "input": "interesting method",
        "selectedText": "We propose a novel approach",
        "url": "https://arxiv.org/abs/2699.99999",
        "title": "A Novel Paper Title For Testing",
        "pageDescription": "abstract text",
    }
    result = server.action_thought(data)
    assert "stub" in result["message"], f"expected stub creation, got: {result['message']}"
    assert "30_papers" in result["savedTo"]
    # Check stub file exists
    stubs = list(server.PAPERS_DIR.glob("*Novel Paper*"))
    assert len(stubs) > 0, "paper stub not created"

@test("save thought links existing paper")
def _():
    # The stub from previous test should exist
    data = {
        "input": "another thought on same paper",
        "selectedText": None,
        "url": "https://arxiv.org/abs/2699.99999",
        "title": "A Novel Paper Title For Testing",
        "pageDescription": "",
    }
    result = server.action_thought(data)
    assert result["message"] == "saved", f"expected 'saved' (existing paper), got: {result['message']}"

@test("save thought from app:// source formats correctly")
def _():
    data = {
        "input": "this diagram is interesting",
        "selectedText": "Figure 3 shows the architecture",
        "url": "app://Preview",
        "title": "2605.14621.pdf",
        "pageDescription": "",
        "app": "Preview",
    }
    result = server.action_thought(data)
    date_str = datetime.now().strftime("%Y-%m-%d")
    daily_file = TEST_VAULT / "01_daily" / date_str / "Daily random thoughts.md"
    content = daily_file.read_text()
    assert "**App:** Preview" in content, "app source not formatted correctly"
    assert "> Figure 3 shows the architecture" in content


# --- Plan action ---

@test("add to plan")
def _():
    data = {
        "input": "/plan review experiment results",
        "selectedText": "",
        "url": "https://example.com",
        "title": "test",
    }
    result = server.action_plan(data)
    assert result["message"] == "added to plan"
    assert "Daily plan.md" in result["savedTo"]

    date_str = datetime.now().strftime("%Y-%m-%d")
    plan_file = TEST_VAULT / "01_daily" / date_str / "Daily plan.md"
    assert plan_file.exists()
    content = plan_file.read_text()
    assert "review experiment results" in content


# --- LLM call (mock) ---

@test("summary action creates task and calls LLM")
def _():
    with patch.object(server, "call_llm", return_value="This is a test summary."):
        data = {
            "input": "/summary",
            "selectedText": "some text",
            "url": "https://example.com",
            "title": "Test",
            "pageDescription": "",
        }
        result = server.action_summary(data)
        assert result["taskId"] is not None
        assert result["type"] == "command"

        # Wait for async thread
        import time
        time.sleep(1)

        # Check task finished
        tasks = server.get_tasks()
        task = [t for t in tasks if t["id"] == result["taskId"]][0]
        assert task["status"] == "done", f"task status: {task['status']}"

        # Check content written
        date_str = datetime.now().strftime("%Y-%m-%d")
        daily_file = TEST_VAULT / "01_daily" / date_str / "Daily random thoughts.md"
        content = daily_file.read_text()
        assert "This is a test summary." in content

@test("expand action creates task and calls LLM")
def _():
    with patch.object(server, "call_llm", return_value="Expanded idea content here."):
        data = {
            "input": "/expand this concept",
            "selectedText": "contrastive learning",
            "url": "https://arxiv.org/abs/2605.00001",
            "title": "Paper X",
            "pageDescription": "",
        }
        result = server.action_expand(data)
        assert result["taskId"] is not None

        import time
        time.sleep(1)

        tasks = server.get_tasks()
        task = [t for t in tasks if t["id"] == result["taskId"]][0]
        assert task["status"] == "done"

@test("pp action creates task and writes paper note")
def _():
    with patch.object(server, "call_llm", return_value="---\ntitle: Test PP\n---\n# Test PP\nContent here."):
        data = {
            "input": "/pp",
            "selectedText": "",
            "url": "https://arxiv.org/abs/2699.88888",
            "title": "PP Test Paper",
            "pageDescription": "test abstract",
        }
        result = server.action_pp(data)
        assert result["taskId"] is not None

        import time
        time.sleep(1)

        tasks = server.get_tasks()
        task = [t for t in tasks if t["id"] == result["taskId"]][0]
        assert task["status"] == "done"

        stubs = list(server.PAPERS_DIR.glob("*PP Test*"))
        assert len(stubs) > 0, "pp paper note not created"


# --- Task tracking ---

@test("task lifecycle: create -> finish -> get")
def _():
    tid = server.create_task("test task", saved_to="test/path.md")
    tasks = server.get_tasks()
    task = [t for t in tasks if t["id"] == tid][0]
    assert task["status"] == "running"
    assert task["savedTo"] == "test/path.md"

    server.finish_task(tid, success=True)
    tasks = server.get_tasks()
    task = [t for t in tasks if t["id"] == tid][0]
    assert task["status"] == "done"

@test("task error status")
def _():
    tid = server.create_task("failing task")
    server.finish_task(tid, success=False)
    tasks = server.get_tasks()
    task = [t for t in tasks if t["id"] == tid][0]
    assert task["status"] == "error"


# --- Cleanup & report ---

shutil.rmtree(TEST_VAULT)

print(f"\n{'='*40}")
print(f"  {passed} passed, {failed} failed")
print(f"{'='*40}")
exit(1 if failed > 0 else 0)
