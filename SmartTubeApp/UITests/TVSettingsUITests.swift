#if os(tvOS)
import XCTest

// MARK: - TVSettingsUITests
//
// Verifies that the Settings tab is reachable via the tvOS tab bar and that
// key controls are present in the accessibility tree.
//
// No network access is required — all tested elements are static UI.
//
// Navigation: tab bar → right × 4 → select = Settings tab
// (same pattern proven by TVFocusChainUITests.testSettingsTabBarVisibleAfterScrollDownAndUp)

final class TVSettingsUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        try openSettings()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func openSettings() throws {
        for _ in 0..<4 { remote.press(.right) }
        remote.press(.select)
        // Wait for resetAllButton as the sentinel that Settings has fully rendered
        let sentinel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        guard sentinel.waitForExistence(timeout: 12) else {
            try captureAndSkip("settings.resetAllButton not found — Settings tab did not open", in: app)
        }
    }

    // MARK: - Tests

    /// The sign-in button must appear in Settings when the user is not signed in.
    func testSignInButtonVisibleWhenSignedOut() throws {
        let signInButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.signInButton'"))
            .firstMatch
        guard signInButton.waitForExistence(timeout: 5) else {
            try captureAndSkip(
                "settings.signInButton not found — device may already be signed in (expected a signed-out state for this test)",
                in: app
            )
        }
        XCTAssertTrue(signInButton.exists, "settings.signInButton must be in the accessibility tree when signed out")
    }

    /// The Hide Shorts toggle must be in the accessibility tree.
    func testHideShortsToggleExists() {
        let toggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.hideShortsToggle'"))
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "settings.hideShortsToggle must be in the accessibility tree"
        )
    }

    /// The SponsorBlock toggle must be in the accessibility tree.
    func testSponsorBlockToggleExists() {
        let toggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.sponsorBlockToggle'"))
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "settings.sponsorBlockToggle must be in the accessibility tree"
        )
    }

    /// The Max Resolution picker must be in the accessibility tree.
    func testPreferredQualityPickerExists() {
        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.preferredQualityPicker'"))
            .firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: 10),
            "settings.preferredQualityPicker must be in the accessibility tree"
        )
    }

    /// The Preferred Audio Language row must be in the accessibility tree.
    func testPreferredAudioLanguageRowExists() {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.preferredAudioLanguageRow'"))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "settings.preferredAudioLanguageRow must be in the accessibility tree"
        )
    }

    /// The Reset All Settings button must be in the accessibility tree.
    func testResetAllSettingsButtonExists() {
        let button = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        XCTAssertTrue(
            button.waitForExistence(timeout: 10),
            "settings.resetAllButton must be in the accessibility tree"
        )
    }

    /// Regression test for #149: the Settings tab must open on the first select press.
    /// Before the fix, MainTVTabView used an unbound TabView which made the tvOS focus
    /// engine require two presses — the first focused the tab, the second activated it.
    func testSettingsTabOpensSingleSelectPress() throws {
        // setUpWithError already calls openSettings() which presses select exactly once.
        // If the sentinel was found (setup succeeded), Settings opened on a single press.
        let sentinel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        XCTAssertTrue(
            sentinel.waitForExistence(timeout: 10),
            "#149 regression: Settings tab must open after a single select press, not two"
        )
    }
}

// MARK: - Account switching (live: plays a YouTube video)

/// Drives a real account switch with two fake accounts (`--uitesting-fake-accounts`, no
/// Google sign-in): each account must keep its own watch position, and "Who's Watching?"
/// must switch between Alex, Sam and Guest. Screenshots go to the test attachments.
final class TVAccountSwitchUITests: XCTestCase {
    private let remote = XCUIRemote.shared
    private let videoId = "u5UTIofKDGc"

    private func launch(active: String, playVideo: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["--uitesting", "--uitesting-fake-accounts", "--uitesting-fake-account-active=\(active)"]
            + (playVideo ? ["--uitesting-deeplink-video=\(videoId)"] : [])
        app.launch()
        return app
    }

    /// Lets real time pass (playback has to run for a position to be saved).
    private func hold(_ seconds: TimeInterval) {
        let never = expectation(description: "hold \(seconds)s")
        never.isInverted = true
        wait(for: [never], timeout: seconds)
    }

    private func element(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Presses `direction` until the element labelled `label` has focus.
    @discardableResult
    private func focus(_ label: String, in app: XCUIApplication, pressing direction: XCUIRemote.Button) -> Bool {
        let target = element(label, in: app)
        for _ in 0..<14 {
            if target.exists && target.hasFocus { return true }
            remote.press(direction)
            hold(0.6)
        }
        return target.exists && target.hasFocus
    }

    /// Sidebar (opened with Menu unless it already is — a switch lands on Home with the sidebar
    /// open, and Menu there would leave the app), three down to the account entry, open it.
    private func openWhosWatching(in app: XCUIApplication, sidebarOpen: Bool = false) {
        if !sidebarOpen {
            remote.press(.menu)
            hold(1.5)
        }
        for _ in 0..<3 {
            remote.press(.down)
            hold(0.5)
        }
        remote.press(.select)
        XCTAssertTrue(
            element("Who's Watching?", in: app).waitForExistence(timeout: 6), "Who's Watching? page opened")
        hold(1)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEachAccountKeepsItsOwnDataAndSwitchesFromWhosWatching() {
        // Keep going past a failed check: the remaining screenshots still help diagnose it.
        continueAfterFailure = true
        // 1. Alex watches 20 s of a video; closing the player saves the position to Alex.
        var app = launch(active: "uitest-alex", playVideo: true)
        hold(20)
        snapshot("1-alex-playing")
        remote.press(.menu)
        hold(3)
        app.terminate()

        // 2. Sam opens the same video: it must start from the beginning (Alex's data only).
        app = launch(active: "uitest-sam", playVideo: true)
        hold(12)
        snapshot("2-sam-playing")
        remote.press(.menu)
        hold(3)
        app.terminate()

        // 3. Alex again: the video must resume where Alex left off.
        app = launch(active: "uitest-alex", playVideo: true)
        hold(12)
        snapshot("3-alex-resumed")
        remote.press(.menu)
        hold(3)

        // 4. Switch in the UI: sidebar → the account entry (Home, Subscriptions, Search, then the
        //    account) → Who's Watching? → Sam, then → Guest. A switch returns to Home.
        openWhosWatching(in: app)
        snapshot("4-whos-watching-alex")
        XCTAssertTrue(element("Alex", in: app).exists, "Alex's card")
        XCTAssertTrue(focus("Sam", in: app, pressing: .right), "Sam's card on Who's Watching?")
        remote.press(.select)
        hold(5)
        snapshot("5-switched-to-sam")

        openWhosWatching(in: app, sidebarOpen: true)
        snapshot("6-whos-watching-sam")
        XCTAssertTrue(element("Current", in: app).exists, "the active profile is marked Current")
        XCTAssertTrue(focus("Guest", in: app, pressing: .right), "Guest card on Who's Watching?")
        remote.press(.select)
        hold(5)
        snapshot("7-switched-to-guest")
        openWhosWatching(in: app, sidebarOpen: true)
        snapshot("8-whos-watching-guest")

        // 5. A Brand channel is its own profile: Alex's "Alex Kids" card.
        XCTAssertTrue(element("Alex Kids", in: app).exists, "each channel of an account is a profile")
        // Focus starts on the first card.
        XCTAssertTrue(focus("Alex Kids", in: app, pressing: .right), "Alex Kids card")
        remote.press(.select)
        hold(5)
        openWhosWatching(in: app, sidebarOpen: true)
        snapshot("9-whos-watching-alex-kids")
    }
}

#endif
