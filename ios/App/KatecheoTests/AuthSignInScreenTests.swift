import XCTest
@testable import Katecheo

/// Auth screen redesign: sign-in / create-account modes, validation, light/dark snapshots.
@MainActor
final class AuthSignInScreenTests: XCTestCase {
    func testValidation_signInRejectsInvalidEmailAndEmptyPassword() {
        let badEmail = NativeEmailAuthForm.validate(
            mode: .signIn,
            name: "",
            email: "not-an-email",
            password: "",
            passwordConfirm: ""
        )
        XCTAssertEqual(badEmail.email, .invalidEmail)
        XCTAssertEqual(badEmail.password, .emptyPassword)
        XCTAssertFalse(badEmail.isValid)

        let ok = NativeEmailAuthForm.validate(
            mode: .signIn,
            name: "",
            email: "person@example.com",
            password: "secret",
            passwordConfirm: ""
        )
        XCTAssertTrue(ok.isValid)
    }

    func testValidation_createAccountChecksNameLengthMatchAndMinPassword() {
        let short = NativeEmailAuthForm.validate(
            mode: .createAccount,
            name: "",
            email: "person@example.com",
            password: "short",
            passwordConfirm: "other"
        )
        XCTAssertEqual(short.name, .emptyName)
        XCTAssertEqual(short.password, .passwordTooShort)
        XCTAssertEqual(short.passwordConfirm, .passwordMismatch)
        XCTAssertEqual(NativeEmailAuthForm.minPasswordLength, 8)

        let ok = NativeEmailAuthForm.validate(
            mode: .createAccount,
            name: "Ana",
            email: "ana@example.com",
            password: "password1",
            passwordConfirm: "password1"
        )
        XCTAssertTrue(ok.isValid)
    }

    func testScreen_togglesCreateAccountFieldsAndInlineErrors() {
        let (vc, nav, window) = makeSignIn(style: .dark)
        XCTAssertEqual(vc.title, String(localized: "Entrar ou criar conta"))
        XCTAssertEqual(vc.testing_socialCaptionText, String(localized: "Google e Apple criam a conta no primeiro acesso."))
        XCTAssertFalse(vc.testing_isNameFieldVisible)
        XCTAssertFalse(vc.testing_isPasswordConfirmVisible)
        XCTAssertEqual(vc.testing_emailButtonTitle, String(localized: "Entrar com email"))

        vc.testing_setEmailMode(.createAccount)
        XCTAssertTrue(vc.testing_isNameFieldVisible)
        XCTAssertTrue(vc.testing_isPasswordConfirmVisible)
        XCTAssertEqual(vc.testing_emailButtonTitle, String(localized: "Criar conta com email"))

        vc.testing_fill(name: "", email: "bad", password: "123", passwordConfirm: "456")
        let result = vc.testing_validateCurrentFields()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(vc.testing_emailErrorText, String(localized: "Informe um email válido."))
        XCTAssertEqual(vc.testing_passwordErrorText, String(localized: "A senha deve ter pelo menos 8 caracteres."))
        XCTAssertEqual(vc.testing_passwordConfirmErrorText, String(localized: "As senhas não coincidem."))

        vc.testing_setEmailMode(.signIn)
        XCTAssertFalse(vc.testing_isNameFieldVisible)
        XCTAssertFalse(vc.testing_isPasswordConfirmVisible)
        _ = nav
        window.isHidden = true
    }

    func testScreen_snapshotsLightDark_signInAndCreateModes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let tag = style == .light ? "light" : "dark"
            let (vc, nav, window) = makeSignIn(style: style)
            nav.view.layoutIfNeeded()
            let signInSnap = try XCTUnwrap(Self.render(nav.view, size: CGSize(width: 390, height: 844)))
            XCTAssertTrue(Self.hasVisiblePixels(signInSnap), "auth-\(tag)-signin must not be blank")
            Self.write(signInSnap, name: "auth-\(tag)-signin.png", into: self)

            vc.testing_setEmailMode(.createAccount)
            vc.testing_fill(
                name: "Maria Silva",
                email: "maria@example.com",
                password: "",
                passwordConfirm: ""
            )
            nav.view.layoutIfNeeded()
            let createSnap = try XCTUnwrap(Self.render(nav.view, size: CGSize(width: 390, height: 844)))
            XCTAssertTrue(Self.hasVisiblePixels(createSnap), "auth-\(tag)-create must not be blank")
            Self.write(createSnap, name: "auth-\(tag)-create.png", into: self)

            // Validation error state (create mode).
            _ = vc.testing_validateCurrentFields()
            nav.view.layoutIfNeeded()
            let errorsSnap = try XCTUnwrap(Self.render(nav.view, size: CGSize(width: 390, height: 844)))
            XCTAssertTrue(Self.hasVisiblePixels(errorsSnap), "auth-\(tag)-create-errors must not be blank")
            Self.write(errorsSnap, name: "auth-\(tag)-create-errors.png", into: self)
            window.isHidden = true
        }
    }

    private func makeSignIn(style: UIUserInterfaceStyle) -> (
        NativeSignInViewController,
        UINavigationController,
        UIWindow
    ) {
        let vc = NativeSignInViewController()
        let nav = UINavigationController(rootViewController: vc)
        KCChrome.style(navigationController: nav)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = style
        AppAppearance.apply(to: window)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        nav.overrideUserInterfaceStyle = style
        vc.overrideUserInterfaceStyle = style
        vc.loadViewIfNeeded()
        vc.viewWillAppear(false)
        nav.view.layoutIfNeeded()
        return (vc, nav, window)
    }

    private static func render(_ view: UIView, size: CGSize) -> UIImage? {
        view.bounds = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    /// Reject pure-black draws so CI cannot upload blank auth screenshots.
    private static func hasVisiblePixels(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
            return false
        }
        let bpp = max(cg.bitsPerPixel / 8, 1)
        let row = cg.bytesPerRow
        var samples = 0
        var nonZero = 0
        // Sparse sample across the frame.
        for y in stride(from: 0, to: cg.height, by: max(cg.height / 40, 1)) {
            for x in stride(from: 0, to: cg.width, by: max(cg.width / 40, 1)) {
                let idx = y * row + x * bpp
                samples += 1
                if ptr[idx] > 8 || (bpp > 1 && ptr[idx + 1] > 8) || (bpp > 2 && ptr[idx + 2] > 8) {
                    nonZero += 1
                }
            }
        }
        return samples > 0 && nonZero > samples / 20
    }

    private static func write(_ image: UIImage, name: String, into test: XCTestCase) {
        let xct = XCTAttachment(image: image)
        xct.name = name
        xct.lifetime = .keepAlways
        test.add(xct)
        // Write under the Simulator sandbox temp dir so CI harvest
        // (`find … CoreSimulator`) can copy auth-*.png into artifacts/.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("katecheo-auth", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? image.pngData()?.write(to: url, options: .atomic)
        NSLog("auth artifact written: %@", url.path)
    }
}
