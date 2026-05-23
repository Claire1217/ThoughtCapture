#!/usr/bin/env swift
// Layout consistency test for ThoughtCapture CapturePanel
// Verifies that quote, question, and answer positions don't shift between phases.
//
// Run: swift layout_test.swift

import Foundation

// --- Constants (must match ThoughtCaptureHotkey.swift) ---
let pw: CGFloat = 440
let baseInputH: CGFloat = 24
let quoteOffsetFromTop: CGFloat = 36   // topPad(10) + boxH(26)
let topRegionH_quote: CGFloat = 46     // topPad(10) + boxH(26) + gap(10)
let topRegionH_noQuote: CGFloat = 10   // topPad(10) only

struct LayoutResult {
    let totalH: CGFloat
    let ctxBoxY: CGFloat       // ctxBox.frame.origin.y (bottom edge in macOS coords)
    let ctxBoxTopEdge: CGFloat // ctxBox.frame.origin.y + 26
    let quoteLabelY: CGFloat
    let inputOrQuestionY: CGFloat
    let inputOrQuestionTopEdge: CGFloat
    let gapCtxToContent: CGFloat // visual gap between ctxBox bottom and content top
}

func repositionTopElements(_ totalH: CGFloat) -> (ctxBoxY: CGFloat, ctxBoxTop: CGFloat, labelY: CGFloat) {
    let ctxY = totalH - quoteOffsetFromTop  // = totalH - 36
    let boxY = ctxY - 2
    let boxTop = boxY + 26
    let labelY = ctxY + 2
    return (boxY, boxTop, labelY)
}

// ========== PHASE 1: show() — initial panel with input field ==========

func testShow(hasQuote: Bool) -> LayoutResult {
    let topRegionH = hasQuote ? topRegionH_quote : topRegionH_noQuote
    let thumbH: CGFloat = 0
    let ph = topRegionH + baseInputH + 14 + thumbH

    let inputY: CGFloat = 14
    let inputTopEdge = inputY + baseInputH  // = 38

    if hasQuote {
        let pos = repositionTopElements(ph)
        let gap = pos.ctxBoxY - inputTopEdge
        return LayoutResult(
            totalH: ph, ctxBoxY: pos.ctxBoxY, ctxBoxTopEdge: pos.ctxBoxTop,
            quoteLabelY: pos.labelY,
            inputOrQuestionY: inputY, inputOrQuestionTopEdge: inputTopEdge,
            gapCtxToContent: gap
        )
    } else {
        return LayoutResult(
            totalH: ph, ctxBoxY: 0, ctxBoxTopEdge: 0, quoteLabelY: 0,
            inputOrQuestionY: inputY, inputOrQuestionTopEdge: inputTopEdge,
            gapCtxToContent: 0
        )
    }
}

// ========== PHASE 2: resizeToFit() — as user types ==========

func testResizeToFit(hasQuote: Bool, neededH: CGFloat) -> LayoutResult {
    let topRegionH = hasQuote ? topRegionH_quote : topRegionH_noQuote
    let inputY: CGFloat = 14
    let thumbH: CGFloat = 0
    let totalH = topRegionH + neededH + inputY + thumbH

    let inputTopEdge = inputY + neededH

    if hasQuote {
        let pos = repositionTopElements(totalH)
        let gap = pos.ctxBoxY - inputTopEdge
        return LayoutResult(
            totalH: totalH, ctxBoxY: pos.ctxBoxY, ctxBoxTopEdge: pos.ctxBoxTop,
            quoteLabelY: pos.labelY,
            inputOrQuestionY: inputY, inputOrQuestionTopEdge: inputTopEdge,
            gapCtxToContent: gap
        )
    } else {
        return LayoutResult(
            totalH: totalH, ctxBoxY: 0, ctxBoxTopEdge: 0, quoteLabelY: 0,
            inputOrQuestionY: inputY, inputOrQuestionTopEdge: inputTopEdge,
            gapCtxToContent: 0
        )
    }
}

// ========== PHASE 3: showWorking() — dots animation ==========

func testShowWorking(hasQuote: Bool) -> LayoutResult {
    let dotsH: CGFloat = 20
    let totalH = quoteOffsetFromTop + 16 + 12 + dotsH + 12

    let newQY = totalH - quoteOffsetFromTop - 16 - 12
    let questionTopEdge = newQY + 16

    if hasQuote {
        let pos = repositionTopElements(totalH)
        let gap = pos.ctxBoxY - questionTopEdge
        return LayoutResult(
            totalH: totalH, ctxBoxY: pos.ctxBoxY, ctxBoxTopEdge: pos.ctxBoxTop,
            quoteLabelY: pos.labelY,
            inputOrQuestionY: newQY, inputOrQuestionTopEdge: questionTopEdge,
            gapCtxToContent: gap
        )
    } else {
        return LayoutResult(
            totalH: totalH, ctxBoxY: 0, ctxBoxTopEdge: 0, quoteLabelY: 0,
            inputOrQuestionY: newQY, inputOrQuestionTopEdge: questionTopEdge,
            gapCtxToContent: 0
        )
    }
}

// ========== PHASE 4: showAnswer() — streaming answer ==========

func testShowAnswer(hasQuote: Bool, answerH: CGFloat) -> LayoutResult {
    let qOffFromTop = quoteOffsetFromTop + 16 + 12
    let footerH: CGFloat = 14
    let totalH = qOffFromTop + 1 + 6 + answerH + footerH

    let qY = totalH - quoteOffsetFromTop - 16 - 12
    let questionTopEdge = qY + 16

    if hasQuote {
        let pos = repositionTopElements(totalH)
        let gap = pos.ctxBoxY - questionTopEdge
        return LayoutResult(
            totalH: totalH, ctxBoxY: pos.ctxBoxY, ctxBoxTopEdge: pos.ctxBoxTop,
            quoteLabelY: pos.labelY,
            inputOrQuestionY: qY, inputOrQuestionTopEdge: questionTopEdge,
            gapCtxToContent: gap
        )
    } else {
        return LayoutResult(
            totalH: totalH, ctxBoxY: 0, ctxBoxTopEdge: 0, quoteLabelY: 0,
            inputOrQuestionY: qY, inputOrQuestionTopEdge: questionTopEdge,
            gapCtxToContent: 0
        )
    }
}

// ========== RUN TESTS ==========

var passed = 0
var failed = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL: \(name) \(detail)")
    }
}

print("=== Layout Consistency Tests ===\n")

// Test 1: show() and resizeToFit() produce same height for baseInputH
print("--- Test 1: show() vs resizeToFit() initial consistency ---")
do {
    let show = testShow(hasQuote: true)
    let resize = testResizeToFit(hasQuote: true, neededH: baseInputH)
    check("totalH matches", show.totalH == resize.totalH,
          "show=\(show.totalH) resize=\(resize.totalH)")
    check("ctxBoxY matches", show.ctxBoxY == resize.ctxBoxY,
          "show=\(show.ctxBoxY) resize=\(resize.ctxBoxY)")
    check("content Y matches", show.inputOrQuestionY == resize.inputOrQuestionY,
          "show=\(show.inputOrQuestionY) resize=\(resize.inputOrQuestionY)")
    check("gap matches", show.gapCtxToContent == resize.gapCtxToContent,
          "show=\(show.gapCtxToContent) resize=\(resize.gapCtxToContent)")
    print("  show:   totalH=\(show.totalH) ctxBoxY=\(show.ctxBoxY) inputY=\(show.inputOrQuestionY) gap=\(show.gapCtxToContent)")
    print("  resize: totalH=\(resize.totalH) ctxBoxY=\(resize.ctxBoxY) inputY=\(resize.inputOrQuestionY) gap=\(resize.gapCtxToContent)")
}

// Test 2: show() without quote
print("\n--- Test 2: show() vs resizeToFit() without quote ---")
do {
    let show = testShow(hasQuote: false)
    let resize = testResizeToFit(hasQuote: false, neededH: baseInputH)
    check("totalH matches (no quote)", show.totalH == resize.totalH,
          "show=\(show.totalH) resize=\(resize.totalH)")
    print("  show:   totalH=\(show.totalH) inputY=\(show.inputOrQuestionY)")
    print("  resize: totalH=\(resize.totalH) inputY=\(resize.inputOrQuestionY)")
}

// Test 3: Gap between ctx and content across phases
print("\n--- Test 3: ctx→content gap across phases (with quote) ---")
do {
    let show = testShow(hasQuote: true)
    let working = testShowWorking(hasQuote: true)
    let answer = testShowAnswer(hasQuote: true, answerH: 80)

    print("  show():       gap=\(show.gapCtxToContent)  totalH=\(show.totalH)")
    print("  showWorking(): gap=\(working.gapCtxToContent)  totalH=\(working.totalH)")
    print("  showAnswer():  gap=\(answer.gapCtxToContent)  totalH=\(answer.totalH)")

    check("gap >= 6 in show", show.gapCtxToContent >= 6,
          "gap=\(show.gapCtxToContent)")
    check("gap >= 6 in showWorking", working.gapCtxToContent >= 6,
          "gap=\(working.gapCtxToContent)")
    check("gap >= 6 in showAnswer", answer.gapCtxToContent >= 6,
          "gap=\(answer.gapCtxToContent)")
    check("no overlap in show", show.gapCtxToContent > 0,
          "gap=\(show.gapCtxToContent)")
    check("no overlap in showWorking", working.gapCtxToContent > 0,
          "gap=\(working.gapCtxToContent)")
    check("no overlap in showAnswer", answer.gapCtxToContent > 0,
          "gap=\(answer.gapCtxToContent)")
}

// Test 4: ctxBox position from top stays constant
print("\n--- Test 4: ctxBox distance from top edge ---")
do {
    let show = testShow(hasQuote: true)
    let resize = testResizeToFit(hasQuote: true, neededH: 60)
    let working = testShowWorking(hasQuote: true)
    let answer = testShowAnswer(hasQuote: true, answerH: 100)

    let showFromTop = show.totalH - show.ctxBoxTopEdge
    let resizeFromTop = resize.totalH - resize.ctxBoxTopEdge
    let workingFromTop = working.totalH - working.ctxBoxTopEdge
    let answerFromTop = answer.totalH - answer.ctxBoxTopEdge

    check("ctxBox from top: show == resize", showFromTop == resizeFromTop,
          "show=\(showFromTop) resize=\(resizeFromTop)")
    check("ctxBox from top: show == working", showFromTop == workingFromTop,
          "show=\(showFromTop) working=\(workingFromTop)")
    check("ctxBox from top: show == answer", showFromTop == answerFromTop,
          "show=\(showFromTop) answer=\(answerFromTop)")

    print("  show:       fromTop=\(showFromTop)")
    print("  resizeToFit: fromTop=\(resizeFromTop)")
    print("  showWorking: fromTop=\(workingFromTop)")
    print("  showAnswer:  fromTop=\(answerFromTop)")
}

// Test 5: Question position consistent between showWorking and showAnswer
print("\n--- Test 5: question position in showWorking vs showAnswer ---")
do {
    let working = testShowWorking(hasQuote: true)
    let answer = testShowAnswer(hasQuote: true, answerH: 80)

    let workingQFromTop = working.totalH - working.inputOrQuestionTopEdge
    let answerQFromTop = answer.totalH - answer.inputOrQuestionTopEdge

    check("question from top: working == answer", workingQFromTop == answerQFromTop,
          "working=\(workingQFromTop) answer=\(answerQFromTop)")

    print("  showWorking: qFromTop=\(workingQFromTop) qY=\(working.inputOrQuestionY)")
    print("  showAnswer:  qFromTop=\(answerQFromTop) qY=\(answer.inputOrQuestionY)")
}

// Test 6: No negative heights or overlaps with various answer sizes
print("\n--- Test 6: edge cases for showAnswer ---")
for answerH in [CGFloat(10), 18, 50, 100, 200] {
    let r = testShowAnswer(hasQuote: true, answerH: answerH)
    check("totalH > 0 (answerH=\(answerH))", r.totalH > 0)
    check("no overlap (answerH=\(answerH))", r.gapCtxToContent > 0,
          "gap=\(r.gapCtxToContent)")
    check("question above dots area (answerH=\(answerH))", r.inputOrQuestionY > 14)
}

// Test 7: resizeToFit with growing input
print("\n--- Test 7: resizeToFit with growing input ---")
do {
    var prevGap: CGFloat = -1
    for neededH in stride(from: baseInputH, through: CGFloat(120), by: 12) {
        let r = testResizeToFit(hasQuote: true, neededH: neededH)
        check("gap stable (neededH=\(neededH))", prevGap < 0 || r.gapCtxToContent == prevGap,
              "prev=\(prevGap) now=\(r.gapCtxToContent)")
        prevGap = r.gapCtxToContent
    }
    print("  gap stays at \(prevGap) regardless of input height ✓")
}

print("\n=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 { exit(1) }
