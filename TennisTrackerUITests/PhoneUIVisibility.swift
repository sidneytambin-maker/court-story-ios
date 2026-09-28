import XCTest

enum PhoneUIVisibleRegion {
    case full, top, bottom
}

extension XCTestCase {
    @discardableResult
    func revealPhoneElement(_ element: XCUIElement, in app: XCUIApplication,
                            showing region: PhoneUIVisibleRegion = .full,
                            file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        var upward = true
        var previousRows = ""
        var stationarySteps = 0
        for _ in 0..<48 {
            let viewport = phoneContentViewport(in: app)
            var distance = min(180, viewport.height * 0.3)
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
                let rows = app.cells.allElementsBoundByIndex.filter { $0.frame.intersects(viewport) }
                    .map { "\($0.label):\(Int($0.frame.minY))" }.joined(separator: "|")
                stationarySteps = !rows.isEmpty && rows == previousRows ? stationarySteps + 1 : 0
                if stationarySteps == 2 { upward.toggle(); stationarySteps = 0 }
                previousRows = rows
            }
            let travel = min(max(40, distance), viewport.height * 0.4)
            let offset = upward ? travel / 2 : -travel / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX,
                                                  dy: viewport.midY + offset - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX,
                                                dy: viewport.midY - offset - app.frame.minY))
            // Hold before release: a fling can skip short rows or leave them behind the tab bar.
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        capturePhoneEvidence(app, name: "Failed reveal " + element.identifier)
        XCTFail("Could not fully reveal \(element); frame \(element.exists ? element.frame.debugDescription : "missing"); viewport \(phoneContentViewport(in: app))", file: file, line: line)
        return element
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
