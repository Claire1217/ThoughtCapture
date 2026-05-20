#!/usr/bin/env /opt/homebrew/bin/python3
"""
Global Thought Capture — macOS menubar app.
Click menubar icon or use the menu to capture thoughts from any app.
"""

import json
import subprocess
import threading
import time
from urllib.request import Request, urlopen

import AppKit
import Quartz
import objc
from AppKit import (
    NSApplication,
    NSApp,
    NSMenu,
    NSMenuItem,
    NSObject,
    NSStatusBar,
    NSVariableStatusItemLength,
    NSTextField,
    NSPanel,
    NSScreen,
    NSColor,
    NSFont,
    NSBackingStoreBuffered,
    NSWindowStyleMaskBorderless,
    NSFloatingWindowLevel,
    NSMakeRect,
    NSView,
    NSEvent,
    NSPasteboard,
    NSPasteboardTypeString,
)
from Quartz import (
    CGEventSourceCreate,
    CGEventCreateKeyboardEvent,
    CGEventSetFlags,
    CGEventPost,
    kCGEventSourceStateCombinedSessionState,
    kCGEventFlagMaskCommand,
    kCGAnnotatedSessionEventTap,
    CGEventTapCreate,
    CGEventGetIntegerValueField,
    CGEventGetFlags,
    CGEventMaskBit,
    kCGSessionEventTap,
    kCGHeadInsertEventTap,
    kCGEventKeyDown,
    kCGKeyboardEventKeycode,
    kCGEventFlagMaskAlternate,
)
import Quartz

SERVER = "http://127.0.0.1:19876"


class ThoughtCaptureApp(NSObject):
    panel = None
    input_field = None
    context_label = None
    current_context = None
    status_item = None
    _event_monitor = None
    _prev_app = None

    def applicationDidFinishLaunching_(self, notification):
        self.setup_menubar()
        self.setup_global_hotkey()

    def setup_global_hotkey(self):
        """Use CGEventTap to intercept Option+T globally."""
        def callback(proxy, event_type, event, refcon):
            keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)
            flags = CGEventGetFlags(event)
            option = bool(flags & kCGEventFlagMaskAlternate)

            if option and keycode == 0x11:  # Option + T
                print("[hotkey] Option+T intercepted!", flush=True)
                self.performSelectorOnMainThread_withObject_waitUntilDone_(
                    "triggerCapture:", None, False
                )
                return None  # swallow the event — no † character

            return event

        self._tap_callback = callback  # prevent GC
        tap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            0,  # active filter (not listen-only)
            CGEventMaskBit(kCGEventKeyDown),
            callback,
            None,
        )
        if tap is None:
            print("ERROR: CGEventTap failed — check Accessibility permissions", flush=True)
            return

        source = Quartz.CFMachPortCreateRunLoopSource(None, tap, 0)
        loop = Quartz.CFRunLoopGetCurrent()
        Quartz.CFRunLoopAddSource(loop, source, Quartz.kCFRunLoopCommonModes)
        Quartz.CGEventTapEnable(tap, True)
        self._tap = tap
        self._tap_source = source
        print("CGEventTap registered for Option+T", flush=True)

    def setup_menubar(self):
        status_bar = NSStatusBar.systemStatusBar()
        self.status_item = status_bar.statusItemWithLength_(NSVariableStatusItemLength)
        self.status_item.setTitle_("TC")

        button = self.status_item.button()
        if button:
            button.setTarget_(self)
            button.setAction_("menubarClicked:")

        menu = NSMenu.alloc().init()
        capture_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Capture Thought (⌥T)", "triggerCapture:", ""
        )
        capture_item.setTarget_(self)
        menu.addItem_(capture_item)
        menu.addItem_(NSMenuItem.separatorItem())
        quit_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Quit", "terminate:", "q"
        )
        menu.addItem_(quit_item)
        self.status_item.setMenu_(menu)

    def menubarClicked_(self, sender):
        self.triggerCapture_(sender)

    @objc.python_method
    def get_frontmost_context(self):
        workspace = AppKit.NSWorkspace.sharedWorkspace()
        active_app = workspace.frontmostApplication()
        app_name = active_app.localizedName() if active_app else "Unknown"
        self._prev_app = active_app

        window_title = ""
        try:
            script = (
                'tell application "System Events" to get name of first window '
                'of (first process whose frontmost is true)'
            )
            result = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True, text=True, timeout=2,
            )
            if result.returncode == 0:
                window_title = result.stdout.strip()
        except Exception:
            pass

        return app_name, window_title

    @objc.python_method
    def get_selected_text(self):
        pb = NSPasteboard.generalPasteboard()
        old_count = pb.changeCount()

        src = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState)
        c_down = CGEventCreateKeyboardEvent(src, 0x08, True)
        c_up = CGEventCreateKeyboardEvent(src, 0x08, False)
        CGEventSetFlags(c_down, kCGEventFlagMaskCommand)
        CGEventSetFlags(c_up, kCGEventFlagMaskCommand)
        CGEventPost(kCGAnnotatedSessionEventTap, c_down)
        CGEventPost(kCGAnnotatedSessionEventTap, c_up)

        time.sleep(0.15)

        if pb.changeCount() != old_count:
            text = pb.stringForType_(NSPasteboardTypeString)
            return text.strip() if text else ""
        return ""

    def triggerCapture_(self, sender):
        app_name, window_title = self.get_frontmost_context()
        selected_text = self.get_selected_text()

        self.current_context = {
            "app": app_name,
            "windowTitle": window_title,
            "selectedText": selected_text,
        }

        self.showPanel_(None)

    def showPanel_(self, sender):
        if self.panel and self.panel.isVisible():
            self.panel.close()
            return

        screen = NSScreen.mainScreen().frame()
        pw, ph = 440, 110
        px = (screen.size.width - pw) / 2
        py = screen.size.height * 0.35

        self.panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(px, py, pw, ph),
            NSWindowStyleMaskBorderless,
            NSBackingStoreBuffered,
            False,
        )
        self.panel.setLevel_(NSFloatingWindowLevel)
        self.panel.setOpaque_(False)
        self.panel.setBackgroundColor_(NSColor.clearColor())
        self.panel.setHasShadow_(True)

        content = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, pw, ph))
        content.setWantsLayer_(True)
        content.layer().setCornerRadius_(12)
        content.layer().setBackgroundColor_(NSColor.whiteColor().CGColor())
        content.layer().setShadowOpacity_(0.15)
        content.layer().setShadowRadius_(12)

        ctx = self.current_context or {}
        app_name = ctx.get("app", "")
        selected = ctx.get("selectedText", "")
        hint = app_name
        if selected:
            short = selected[:50] + ("..." if len(selected) > 50 else "")
            hint += f'  "{short}"'

        self.context_label = NSTextField.labelWithString_(hint)
        self.context_label.setFrame_(NSMakeRect(16, ph - 28, pw - 32, 16))
        self.context_label.setFont_(NSFont.systemFontOfSize_(11))
        self.context_label.setTextColor_(NSColor.grayColor())
        self.context_label.setLineBreakMode_(5)
        content.addSubview_(self.context_label)

        self.input_field = NSTextField.alloc().initWithFrame_(
            NSMakeRect(16, ph - 62, pw - 32, 26)
        )
        self.input_field.setPlaceholderString_("your thought...")
        self.input_field.setFont_(NSFont.systemFontOfSize_(14))
        self.input_field.setBordered_(True)
        self.input_field.setBezeled_(True)
        self.input_field.setFocusRingType_(1)
        self.input_field.setTarget_(self)
        self.input_field.setAction_("submitThought:")
        content.addSubview_(self.input_field)

        hint_label = NSTextField.labelWithString_("↵ save · esc close")
        hint_label.setFrame_(NSMakeRect(16, 8, pw - 32, 14))
        hint_label.setFont_(NSFont.systemFontOfSize_(10))
        hint_label.setTextColor_(NSColor.tertiaryLabelColor())
        content.addSubview_(hint_label)

        self.panel.setContentView_(content)
        self.panel.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)
        self.panel.makeFirstResponder_(self.input_field)

        if self._event_monitor:
            NSEvent.removeMonitor_(self._event_monitor)
        self._event_monitor = NSEvent.addLocalMonitorForEventsMatchingMask_handler_(
            AppKit.NSEventMaskKeyDown,
            lambda event: self._handle_key(event),
        )

    @objc.python_method
    def _handle_key(self, event):
        if event.keyCode() == 53:  # Esc
            self.panel.close()
            if self._event_monitor:
                NSEvent.removeMonitor_(self._event_monitor)
                self._event_monitor = None
            return None
        return event

    def submitThought_(self, sender):
        thought = self.input_field.stringValue().strip()
        self.panel.close()
        if self._event_monitor:
            NSEvent.removeMonitor_(self._event_monitor)
            self._event_monitor = None

        if not thought:
            return

        ctx = self.current_context or {}

        payload = {
            "input": thought,
            "selectedText": ctx.get("selectedText") or None,
            "url": f"app://{ctx.get('app', '')}",
            "title": ctx.get("windowTitle", "") or ctx.get("app", ""),
            "pageDescription": "",
            "timestamp": "",
            "source": "global",
            "app": ctx.get("app", ""),
        }

        def _send():
            try:
                data = json.dumps(payload).encode()
                req = Request(f"{SERVER}/handle", data=data, method="POST")
                req.add_header("Content-Type", "application/json")
                with urlopen(req, timeout=10) as resp:
                    result = json.loads(resp.read())
                    print(f"  -> {result.get('message', 'ok')}: {result.get('savedTo', '')}")
            except Exception as e:
                print(f"  -> error: {e}")

        threading.Thread(target=_send, daemon=True).start()


if __name__ == "__main__":
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)

    delegate = ThoughtCaptureApp.alloc().init()
    app.setDelegate_(delegate)

    print("Thought Capture (Global) running")
    print("Hotkey: Ctrl+Shift+Space")
    print("Menubar: TC")

    NSApp.run()
