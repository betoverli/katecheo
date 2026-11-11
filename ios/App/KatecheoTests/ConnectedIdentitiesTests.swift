import XCTest
@testable import Katecheo

@MainActor
final class ConnectedIdentitiesTests: XCTestCase {
    func testOrderedIdentities_fillsMissingProviders() {
        let ordered = ConnectedIdentitiesLogic.orderedIdentities([
            ConnectedIdentityDTO(provider: .google, linked: true, emailMasked: "g***@x.com"),
        ])
        XCTAssertEqual(ordered.map(\.provider), [.apple, .google, .password])
        XCTAssertFalse(ordered[0].linked)
        XCTAssertTrue(ordered[1].linked)
        XCTAssertEqual(ordered[1].emailMasked, "g***@x.com")
        XCTAssertFalse(ordered[2].linked)
    }

    func testCanUnlink_requiresAnotherMethod() {
        let onlyApple = ConnectedIdentitiesLogic.orderedIdentities([
            .init(provider: .apple, linked: true, emailMasked: nil),
        ])
        XCTAssertFalse(ConnectedIdentitiesLogic.canUnlink(identities: onlyApple, provider: .apple))

        let two = ConnectedIdentitiesLogic.orderedIdentities([
            .init(provider: .apple, linked: true, emailMasked: nil),
            .init(provider: .google, linked: true, emailMasked: nil),
        ])
        XCTAssertTrue(ConnectedIdentitiesLogic.canUnlink(identities: two, provider: .apple))
        XCTAssertFalse(ConnectedIdentitiesLogic.canUnlink(identities: two, provider: .password))
    }

    func testConflictMessages_mentionKatecheoAndProvider() {
        let apple = ConnectedIdentitiesLogic.conflictMessage(for: .apple)
        let google = ConnectedIdentitiesLogic.conflictMessage(for: .google)
        XCTAssertTrue(apple.contains("Apple"))
        XCTAssertTrue(apple.contains("Katecheo"))
        XCTAssertTrue(google.contains("Google"))
        XCTAssertTrue(google.contains("Katecheo"))
        XCTAssertEqual(
            ConnectedIdentitiesLogic.localizedError(code: "identity_in_use", provider: .apple, status: 409),
            apple
        )
        XCTAssertEqual(
            ConnectedIdentitiesLogic.localizedError(
                code: #"{"ok":false,"error":"identity_in_use"}"#,
                provider: .google,
                status: 409
            ),
            google
        )
    }

    func testLastMethodAndSetPasswordValidation() {
        XCTAssertEqual(
            ConnectedIdentitiesLogic.localizedError(code: "last_method"),
            String(localized: "Mantenha pelo menos um método de entrada.")
        )

        let create = ConnectedIdentitiesLogic.validateSetPassword(
            password: "short",
            passwordConfirm: "other",
            currentPassword: "",
            hasPassword: false,
            minLength: 8
        )
        XCTAssertEqual(create.password, .passwordTooShort)
        XCTAssertEqual(create.passwordConfirm, .passwordMismatch)
        XCTAssertFalse(create.isValid)

        let changeMissingCurrent = ConnectedIdentitiesLogic.validateSetPassword(
            password: "password1",
            passwordConfirm: "password1",
            currentPassword: "",
            hasPassword: true,
            minLength: 8
        )
        XCTAssertEqual(changeMissingCurrent.currentPassword, .emptyCurrentPassword)

        let ok = ConnectedIdentitiesLogic.validateSetPassword(
            password: "password1",
            passwordConfirm: "password1",
            currentPassword: "oldpass12",
            hasPassword: true,
            minLength: 8
        )
        XCTAssertTrue(ok.isValid)
    }

    func testStatusLabels() {
        XCTAssertEqual(ConnectedIdentitiesLogic.localizedStatus(linked: true), String(localized: "Conectado"))
        XCTAssertEqual(ConnectedIdentitiesLogic.localizedStatus(linked: false), String(localized: "Conectar"))
    }

    func testExtractErrorCode_fromJsonBody() {
        XCTAssertEqual(
            ConnectedIdentitiesLogic.extractErrorCode(from: #"{"ok":false,"error":"last_method"}"#),
            "last_method"
        )
        XCTAssertEqual(ConnectedIdentitiesLogic.extractErrorCode(from: "identity_in_use"), "identity_in_use")
    }
}
