import XCTest

final class CalorieTrackerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Displayed text: the value for text fields, the label for everything else.
    private func text(of element: XCUIElement) -> String {
        if element.elementType == .textField {
            return (element.value as? String) ?? ""
        }
        return element.label
    }

    /// Digits of the displayed text, e.g. "2,510" -> 2510.
    private func number(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> Int? {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(element)", file: file, line: line)
        return Int(text(of: element).filter(\.isNumber))
    }

    private func waitForLabel(_ element: XCUIElement, toEqual expected: Int, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, Int(text(of: element).filter(\.isNumber)) == expected { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Expected \(expected), found \(element.exists ? text(of: element) : "no element")", file: file, line: line)
    }

    /// Replaces the content of a (right-aligned) number field.
    private func replaceText(in field: XCUIElement, with newText: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Tap the trailing edge so the cursor lands after the existing digits.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let existing = (field.value as? String) ?? ""
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4)
        field.typeText(deletes + newText)
    }

    // MARK: - Flows

    func testOnboardingCalculatesGoalAndOpensDashboard() {
        launch([])
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        screenshot("01-welcome")
        next.tap()

        // Gender is required.
        XCTAssertFalse(next.isEnabled)
        app.buttons["onboarding.gender.male"].tap()
        XCTAssertTrue(next.isEnabled)
        screenshot("02-gender")
        next.tap()

        // Age, height, weight: keep the defaults (20 years, 180 cm, 80 kg).
        next.tap()
        next.tap()
        screenshot("03-weight")
        next.tap()

        XCTAssertTrue(app.buttons["onboarding.activity.medium"].waitForExistence(timeout: 5))
        screenshot("04-activity")
        next.tap()
        XCTAssertTrue(app.buttons["onboarding.goal.keep_weight"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["macros.total"].waitForExistence(timeout: 5))
        screenshot("05-macros")
        next.tap()

        // Harris-Benedict: male, 20 y, 180 cm, 80 kg, medium activity -> 2510 kcal.
        XCTAssertEqual(number(app.staticTexts["onboarding.summary.goal"]), 2510)
        screenshot("06-summary")
        next.tap()

        XCTAssertEqual(number(app.staticTexts["summary.goal"]), 2510)
        XCTAssertEqual(number(app.staticTexts["summary.consumed"]), 0)
        XCTAssertEqual(number(app.staticTexts["summary.remaining"]), 2510)
        XCTAssertTrue(app.buttons["home.cameraButton"].exists)
        screenshot("07-home-empty")
    }

    func testScanMealEditPortionAndSave() {
        launch(["-skip-onboarding"])
        let camera = app.buttons["home.cameraButton"]
        XCTAssertTrue(camera.waitForExistence(timeout: 10))
        camera.tap()

        let save = app.buttons["scan.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 15), "scan review did not appear")
        XCTAssertTrue(app.buttons["scan.item.Grilled chicken breast"].exists)
        XCTAssertTrue(app.buttons["scan.item.White rice"].exists)
        XCTAssertTrue(app.buttons["scan.item.Steamed broccoli"].exists)
        waitForLabel(app.staticTexts["scan.totalCalories"], toEqual: 513)
        screenshot("10-scan-review")

        // Halve the rice portion: 180 g -> 90 g, 234 kcal -> 117 kcal.
        app.buttons["scan.item.White rice"].tap()
        let grams = app.textFields["editor.grams"]
        replaceText(in: grams, with: "90")
        waitForLabel(app.textFields["editor.calories"], toEqual: 117)
        screenshot("11-scan-edit-item")
        app.buttons["editor.save"].tap()

        waitForLabel(app.staticTexts["scan.totalCalories"], toEqual: 396)
        save.tap()

        waitForLabel(app.staticTexts["summary.consumed"], toEqual: 396)
        waitForLabel(app.staticTexts["summary.remaining"], toEqual: 2510 - 396)
        XCTAssertTrue(app.buttons["entry.White rice"].exists)
        screenshot("12-home-after-scan")
    }

    func testManualEntryEditAndDelete() {
        launch(["-skip-onboarding"])
        let addBreakfast = app.buttons["addFood.breakfast"]
        XCTAssertTrue(addBreakfast.waitForExistence(timeout: 10))
        addBreakfast.tap()
        let manualItem = app.buttons["Enter manually"]
        if !manualItem.waitForExistence(timeout: 5) {
            // The menu occasionally needs a second tap while the list is still settling.
            addBreakfast.tap()
        }
        XCTAssertTrue(manualItem.waitForExistence(timeout: 5), "add-food menu did not open")
        screenshot("19-add-food-menu")
        manualItem.tap()

        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Banana")
        replaceText(in: app.textFields["editor.grams"], with: "120")
        replaceText(in: app.textFields["editor.calories"], with: "107")
        screenshot("20-manual-entry")
        app.buttons["editor.save"].tap()

        waitForLabel(app.staticTexts["summary.consumed"], toEqual: 107)
        waitForLabel(app.staticTexts["mealTotal.breakfast"], toEqual: 107)

        // Doubling the amount doubles the calories.
        let row = app.buttons["entry.Banana"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        replaceText(in: app.textFields["editor.grams"], with: "240")
        waitForLabel(app.textFields["editor.calories"], toEqual: 214)
        app.buttons["editor.save"].tap()
        waitForLabel(app.staticTexts["summary.consumed"], toEqual: 214)

        // Delete from the editor.
        row.tap()
        app.buttons["editor.delete"].tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        waitForLabel(app.staticTexts["summary.consumed"], toEqual: 0)
        XCTAssertFalse(app.buttons["entry.Banana"].exists)
    }

    func testSearchFoodAndAddAmount() {
        launch(["-skip-onboarding"])
        let search = app.buttons["home.searchButton"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("oats\n")

        let result = app.buttons["search.result.Rolled oats"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        screenshot("30-search-results")
        result.tap()

        replaceText(in: app.textFields["search.amount"], with: "50")
        screenshot("31-search-amount")
        app.buttons["search.add"].tap()

        // 379 kcal / 100 g * 50 g = 189.5 -> 190
        waitForLabel(app.staticTexts["summary.consumed"], toEqual: 190)
    }

    func testScreensWithSampleData() {
        launch(["-skip-onboarding", "-sample-data"])
        XCTAssertTrue(app.buttons["home.cameraButton"].waitForExistence(timeout: 10))
        // Oatmeal 320 + yogurt 145.5 + chicken salad 377.6 + apple 93.6 = 936.7
        waitForLabel(app.staticTexts["summary.consumed"], toEqual: 937)
        screenshot("40-home")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["history.average"].waitForExistence(timeout: 5))
        screenshot("41-history")

        app.tabBars.buttons["Profile"].tap()
        XCTAssertEqual(number(app.staticTexts["profile.goal"]), 2510)
        screenshot("42-profile")
    }
}
