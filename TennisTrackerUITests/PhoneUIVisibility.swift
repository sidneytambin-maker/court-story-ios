import XCTest

enum PhoneUIVisibleRegion {
    case full, top, bottom
}

extension XCTestCase {
    func choosePhoneOneSetFormat(in app: XCUIApplication) {
        revealPhoneElement(app.buttons["Scoring rules"], in: app).tap()
        revealPhoneElement(app.buttons["courtOfficialFormat"], in: app).tap()
        revealPhoneElement(app.buttons["One set, tie-break at 6-all"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Match rules"].waitForExistence(timeout: 5))
        app.navigationBars["Match rules"].buttons.firstMatch.tap()
    }

    @discardableResult
    func revealPhoneElement(_ element: XCUIElement, in app: XCUIApplication,
                            showing region: PhoneUIVisibleRegion = .full,
                            searchingUp: Bool = false,
                            file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        var upward = !searchingUp
        var previousFirstRow: CGRect?
        var stationarySteps = 0
        let started = Date.timeIntervalSinceReferenceDate
        let timeout: TimeInterval = 120
        for _ in 0..<24 {
            if Date.timeIntervalSinceReferenceDate - started >= timeout { break }
            let viewport = phoneContentViewport(in: app)
            var distance = min(380, viewport.height * 0.65)
            if element.exists {
                let target = phoneVisibleFrame(element.frame, region: region, viewport: viewport)
                if element.isHittable && !target.isEmpty && viewport.contains(target) { return element }
                if target.maxY > viewport.maxY {
                    upward = true
                    distance = min(distance, target.maxY - viewport.maxY + 4)
                } else if target.minY < viewport.minY {
                    upward = false
                    distance = min(distance, viewport.minY - target.minY + 4)
                }
            } else {
                // Query one foreground row, not every offscreen cell on every drag.
                let list = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
                    ?? app.tables.allElementsBoundByIndex.last(where: { $0.isHittable })
                let firstRow = list?.cells.firstMatch
                let frame = firstRow?.exists == true ? firstRow?.frame : nil
                stationarySteps = frame != nil && frame == previousFirstRow ? stationarySteps + 1 : 0
                if stationarySteps == 2 { upward.toggle(); stationarySteps = 0 }
                previousFirstRow = frame
            }
            let travel = min(max(40, distance), viewport.height * 0.65)
            let offset = upward ? travel / 2 : -travel / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX,
                                                  dy: viewport.midY + offset - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX,
                                                dy: viewport.midY - offset - app.frame.minY))
            // Hold before release: a fling can skip short rows or leave them behind the tab bar.
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        // A missing element cannot supply an identifier or snapshot for diagnostics.
        capturePhoneEvidence(app, name: "Failed phone reveal at line \(line)")
        XCTFail("Could not fully reveal the requested element within \(timeout) seconds or 24 scroll attempts. See the screenshot and accessibility tree.", file: file, line: line)
        return element
    }

    func setPhoneSwitch(_ element: XCUIElement, enabled: Bool, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        revealPhoneElement(element, in: app, file: file, line: line)
        XCTAssertTrue(element.isEnabled, file: file, line: line)
        let expected = enabled ? "1" : "0"
        if element.value as? String != expected {
            // SwiftUI exposes a labelled row around the actual native switch.
            let controls = element.descendants(matching: .switch)
            XCTAssertLessThanOrEqual(controls.count, 1, file: file, line: line)
            let control = controls.firstMatch.exists ? controls.firstMatch : element
            XCTAssertTrue(control.isHittable, file: file, line: line)
            control.tap()
        }
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        let result = XCTWaiter.wait(for: [state], timeout: 5)
        if result != .completed { capturePhoneEvidence(app, name: "Switch did not reach requested state") }
        XCTAssertEqual(result, .completed, file: file, line: line)
        XCTAssertEqual(element.value as? String, expected, file: file, line: line)
    }

    func expandPhoneSection(_ identifier: String, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let header = revealPhoneElement(app.buttons[identifier], in: app, file: file, line: line)
        XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1, file: file, line: line)
        XCTAssertEqual(header.value as? String, "Collapsed", file: file, line: line)
        header.tap()
        XCTAssertEqual(header.value as? String, "Expanded", file: file, line: line)
        XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1, file: file, line: line)
    }

    func capturePhoneEvidence(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    func capturePhoneSummary(_ element: XCUIElement, in app: XCUIApplication, name: String) {
        revealPhoneElement(element, in: app, showing: .top)
        capturePhoneEvidence(app, name: name + " top")
        if element.frame.height > phoneContentViewport(in: app).height * 0.7 {
            revealPhoneElement(element, in: app, showing: .bottom)
            capturePhoneEvidence(app, name: name + " bottom")
        }
    }

    private func phoneContentViewport(in app: XCUIApplication) -> CGRect {
        let screen = app.frame
        let navigation = app.navigationBars.allElementsBoundByIndex.last(where: { $0.isHittable })
        let tabBar = app.tabBars.allElementsBoundByIndex.last(where: { $0.isHittable })
        let keyboard = app.keyboards.firstMatch
        let status = app.statusBars.firstMatch
        let top = max(status.exists ? status.frame.maxY : screen.minY, navigation?.frame.maxY ?? screen.minY)
        var bottom = min(screen.maxY, tabBar?.frame.minY ?? screen.maxY)
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        return CGRect(x: screen.minX, y: top, width: screen.width, height: max(0, bottom - top))
    }

    private func phoneVisibleFrame(_ frame: CGRect, region: PhoneUIVisibleRegion, viewport: CGRect) -> CGRect {
        let height = min(frame.height, max(0, viewport.height * 0.7))
        switch region {
        case .full: return frame
        case .top: return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
        case .bottom: return CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        }
    }
}
