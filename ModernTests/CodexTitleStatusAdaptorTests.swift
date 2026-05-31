//
//  CodexTitleStatusAdaptorTests.swift
//  ModernTests
//
//  Verifies the foreground-ancestry gate matches Codex regardless of
//  install method (brew, npm/npx, etc.) and refuses to claim sessions
//  where no codex process is in the foreground.
//

import XCTest
@testable import iTerm2SharedARC

final class CodexTitleStatusAdaptorTests: XCTestCase {

    private func newStatus() -> iTermSessionTabStatus {
        return iTermSessionTabStatus(sessionID: "test")
    }

    // Spinner glyph captured from real Codex sessions; treated as opaque here.
    private let spinnerTitle = "⠙ project"
    private let idleTitle = "project"

    // MARK: - Foreground match

    func testBrewInstall_codexPath_matches() {
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["/opt/homebrew/bin/codex", "-zsh"],
            tabStatus: status)
        XCTAssertTrue(changed)
        XCTAssertEqual(status.statusText, "Working")
        XCTAssertTrue(status.hasIndicator)
    }

    func testNpmInstall_nodeWrapperAndRustChild_matches() {
        // Empirically observed npm process tree:
        //   1. Rust binary at .../codex-<platform>/.../bin/codex (deepest, has TTY)
        //   2. node ./node_modules/.bin/codex
        //   3. shell
        // iTermProcessInfo lists deepest first, lowercased.
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: [
                "/private/tmp/codex-npm-test/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex",
                "node",
                "-zsh",
            ],
            tabStatus: status)
        XCTAssertTrue(changed)
        XCTAssertEqual(status.statusText, "Working")
    }

    func testPlainCodexInPath_matches() {
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertTrue(changed)
        XCTAssertEqual(status.statusText, "Working")
    }

    func testNoCodexInAncestors_noChange() {
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["node", "-zsh"],
            tabStatus: status)
        XCTAssertFalse(changed)
        XCTAssertNil(status.statusText)
        XCTAssertFalse(status.hasIndicator)
    }

    func testNilAncestors_noChange() {
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: nil,
            tabStatus: status)
        XCTAssertFalse(changed)
    }

    func testCodexAsSubstring_doesNotMatch() {
        // Only the last path component counts; "codex-ish" must not match.
        let status = newStatus()
        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["/usr/local/bin/codex-ish", "node", "-zsh"],
            tabStatus: status)
        XCTAssertFalse(changed)
    }

    // MARK: - Title-driven state transitions

    func testCodexForeground_idleTitle_setsIdle() {
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: idleTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Idle")
        XCTAssertTrue(status.hasIndicator)
    }

    func testWorkingThenCodexExits_clearsState() {
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Working")

        // Codex left the foreground; shim should clear what it owned.
        CodexTitleStatusAdaptor.apply(
            title: idleTitle,
            ancestorJobNames: ["-zsh"],
            tabStatus: status)
        XCTAssertNil(status.statusText)
        XCTAssertFalse(status.hasIndicator)
    }

    func testWorkingThenIdle_titleDrivenTransition() {
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Working")

        // Codex still in foreground but title lost its spinner prefix.
        CodexTitleStatusAdaptor.apply(
            title: idleTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Idle")
    }

    // MARK: - Coexistence with real OSC 21337 emitters

    func testRealOSCEmitter_wins_overSynthesizedState() {
        // A real OSC 21337 emitter wrote a status before codex started.
        // The shim must not stomp on it.
        let status = newStatus()
        let update = VT100TabStatusUpdate()
        update.indicatorPresence = .set
        update.indicator = iTermSRGBColor(r: 1, g: 0, b: 0)
        update.statusPresence = .set
        update.status = "RealStatus"
        XCTAssertTrue(status.apply(update))

        let changed = CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertFalse(changed)
        XCTAssertEqual(status.statusText, "RealStatus")
    }

    // MARK: - isBusy (what the menu-bar counter consumes)

    func testWorkingState_isBusy() {
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertTrue(status.isBusy)
    }

    func testIdleState_isNotBusy_butKeepsIndicator() {
        // The core stuck-count guard: a synthesized idle agent still shows a
        // (green) dot, but must NOT count as busy.
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        CodexTitleStatusAdaptor.apply(
            title: idleTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        XCTAssertEqual(status.statusText, "Idle")
        XCTAssertEqual(status.synthesizedStatusSource, "codex")
        XCTAssertTrue(status.hasIndicator)
        XCTAssertFalse(status.isBusy)
    }

    func testCodexExits_isNotBusy() {
        let status = newStatus()
        CodexTitleStatusAdaptor.apply(
            title: spinnerTitle,
            ancestorJobNames: ["codex", "-zsh"],
            tabStatus: status)
        CodexTitleStatusAdaptor.apply(
            title: idleTitle,
            ancestorJobNames: ["-zsh"],
            tabStatus: status)
        XCTAssertFalse(status.isBusy)
    }

    func testRealOSCIndicator_countsAsBusy_viaHasIndicatorFallback() {
        // A real OSC 21337 emitter (not owned by the codex shim) that leaves an
        // indicator set will count as busy through the hasIndicator fallback.
        // This is the deterministic "one tab stuck busy" path: if such a status
        // exists and never clears, the menu-bar count never drops for that tab.
        let status = newStatus()
        let update = VT100TabStatusUpdate()
        update.indicatorPresence = .set
        update.indicator = iTermSRGBColor(r: 1, g: 0, b: 0)
        update.statusPresence = .set
        update.status = "RealStatus"
        XCTAssertTrue(status.apply(update))
        XCTAssertNil(status.synthesizedStatusSource)
        XCTAssertTrue(status.isBusy)
    }

    private func realOSCStatus(text: String) -> iTermSessionTabStatus {
        // Mimics a non-codex agent (e.g. Claude Code) emitting OSC 21337: it keeps
        // an indicator dot and conveys the live state through statusText.
        let status = newStatus()
        let update = VT100TabStatusUpdate()
        update.indicatorPresence = .set
        update.indicator = iTermSRGBColor(r: 0, g: 0.84, b: 0.37)
        update.statusPresence = .set
        update.status = text
        XCTAssertTrue(status.apply(update))
        return status
    }

    func testRealOSCEmitter_idleStatusText_isNotBusy() {
        // Claude Code keeps a dot while idle; the explicit "Idle" label must win.
        let status = realOSCStatus(text: "Idle")
        XCTAssertTrue(status.hasIndicator)
        XCTAssertNil(status.synthesizedStatusSource)
        XCTAssertFalse(status.isBusy)
    }

    func testRealOSCEmitter_workingStatusText_isBusy() {
        let status = realOSCStatus(text: "Working…")
        XCTAssertTrue(status.isBusy)
    }
}
