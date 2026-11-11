import AuthenticationServices
import UIKit

/// Full-screen native sign-in / create-account when Keychain has no bearer.
final class NativeSignInViewController: UIViewController {
    var onSignedIn: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let socialCaptionLabel = UILabel()
    private let nameField = UITextField()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let passwordConfirmField = UITextField()
    private let nameErrorLabel = UILabel()
    private let emailErrorLabel = UILabel()
    private let passwordErrorLabel = UILabel()
    private let passwordConfirmErrorLabel = UILabel()
    private var modeControl: UISegmentedControl!
    private var googleButton: UIButton!
    private var appleButton: ASAuthorizationAppleIDButton!
    private var emailButton: UIButton!
    private var forgotPasswordButton: UIButton!
    private var emailFieldsStack: UIStackView!
    private var busy = false
    private(set) var emailMode: NativeEmailAuthMode = .signIn

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Entrar ou criar conta")
        navigationItem.largeTitleDisplayMode = .never
        if let nav = navigationController {
            KCChrome.applyNavigationBarAppearance(to: nav.navigationBar)
            nav.view.backgroundColor = KCDesign.screenBackground
        }

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        view.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = KCDesign.Space.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let brandMark = UIImageView(image: UIImage(named: "BrandMark"))
        brandMark.contentMode = .scaleAspectFit
        brandMark.translatesAutoresizingMaskIntoConstraints = false
        brandMark.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            brandMark.heightAnchor.constraint(equalToConstant: 80),
        ])

        let title = UILabel()
        title.text = String(localized: "Katecheo")
        title.font = KCDesign.displayTitle()
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header

        let subtitle = UILabel()
        subtitle.text = String(localized: "Na primeira vez, criamos sua conta automaticamente.")
        subtitle.font = KCDesign.body()
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        subtitle.adjustsFontForContentSizeCategory = true

        googleButton = UIButton(type: .system)
        KCButtonStyle.applySecondary(to: googleButton, title: String(localized: "Continuar com Google"))
        googleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        googleButton.addTarget(self, action: #selector(tapGoogle), for: .touchUpInside)

        appleButton = makeAppleButton()

        socialCaptionLabel.text = String(localized: "Google e Apple criam a conta no primeiro acesso.")
        socialCaptionLabel.font = KCDesign.caption()
        socialCaptionLabel.textColor = .secondaryLabel
        socialCaptionLabel.textAlignment = .center
        socialCaptionLabel.numberOfLines = 0
        socialCaptionLabel.adjustsFontForContentSizeCategory = true

        modeControl = UISegmentedControl(items: [
            String(localized: "Entrar"),
            String(localized: "Criar conta"),
        ])
        modeControl.selectedSegmentIndex = NativeEmailAuthMode.signIn.rawValue
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.accessibilityLabel = String(localized: "Entrar ou criar conta")

        styleField(nameField, placeholder: String(localized: "Nome"), contentType: .name)
        nameField.autocapitalizationType = .words
        nameField.textContentType = .name

        styleField(emailField, placeholder: String(localized: "Email"), contentType: .username)
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.textContentType = .emailAddress

        styleField(passwordField, placeholder: String(localized: "Senha"), contentType: .password)
        passwordField.isSecureTextEntry = true

        styleField(passwordConfirmField, placeholder: String(localized: "Confirmar senha"), contentType: .newPassword)
        passwordConfirmField.isSecureTextEntry = true
        passwordConfirmField.textContentType = .newPassword

        styleInlineError(nameErrorLabel)
        styleInlineError(emailErrorLabel)
        styleInlineError(passwordErrorLabel)
        styleInlineError(passwordConfirmErrorLabel)

        emailButton = UIButton(type: .system)
        KCButtonStyle.applyPrimary(to: emailButton, title: String(localized: "Entrar com email"))
        emailButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        emailButton.addTarget(self, action: #selector(tapEmail), for: .touchUpInside)

        forgotPasswordButton = UIButton(type: .system)
        forgotPasswordButton.setTitle(String(localized: "Esqueci minha senha"), for: .normal)
        forgotPasswordButton.titleLabel?.font = KCDesign.caption()
        forgotPasswordButton.titleLabel?.adjustsFontForContentSizeCategory = true
        forgotPasswordButton.setTitleColor(KCDesign.accent, for: .normal)
        forgotPasswordButton.contentHorizontalAlignment = .center
        forgotPasswordButton.addTarget(self, action: #selector(tapForgotPassword), for: .touchUpInside)
        forgotPasswordButton.accessibilityLabel = String(localized: "Esqueci minha senha")

        statusLabel.font = KCDesign.caption()
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityTraits = .updatesFrequently

        emailFieldsStack = UIStackView(arrangedSubviews: [
            modeControl,
            nameField,
            nameErrorLabel,
            emailField,
            emailErrorLabel,
            passwordField,
            passwordErrorLabel,
            passwordConfirmField,
            passwordConfirmErrorLabel,
            emailButton,
            forgotPasswordButton,
        ])
        emailFieldsStack.axis = .vertical
        emailFieldsStack.spacing = KCDesign.Space.xs

        stack.addArrangedSubview(brandMark)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(KCDesign.Space.lg, after: subtitle)
        stack.addArrangedSubview(googleButton)
        stack.addArrangedSubview(appleButton)
        stack.addArrangedSubview(socialCaptionLabel)
        stack.setCustomSpacing(KCDesign.Space.md, after: socialCaptionLabel)
        stack.addArrangedSubview(emailFieldsStack)
        stack.setCustomSpacing(KCDesign.Space.sm, after: emailFieldsStack)
        stack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: KCDesign.Space.xl),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: KCDesign.Space.lg),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -KCDesign.Space.lg),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -KCDesign.Space.xl),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -KCDesign.Space.lg * 2),
        ])

        applyEmailMode(.signIn, clearErrors: true)
        Task { await loadProviders() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        rebuildAppleButtonForCurrentStyle()
    }

    private func appleButtonStyle() -> ASAuthorizationAppleIDButton.Style {
        traitCollection.userInterfaceStyle == .dark ? .white : .black
    }

    private func makeAppleButton() -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: appleButtonStyle())
        button.cornerRadius = KCDesign.Radius.md
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.addTarget(self, action: #selector(tapApple), for: .touchUpInside)
        button.accessibilityLabel = String(localized: "Continuar com Apple")
        return button
    }

    private func rebuildAppleButtonForCurrentStyle() {
        guard let current = appleButton, let index = stack.arrangedSubviews.firstIndex(of: current) else { return }
        let wasHidden = current.isHidden
        let wasEnabled = current.isEnabled
        stack.removeArrangedSubview(current)
        current.removeFromSuperview()
        let next = makeAppleButton()
        next.isHidden = wasHidden
        next.isEnabled = wasEnabled
        appleButton = next
        stack.insertArrangedSubview(next, at: index)
    }

    private func styleField(_ field: UITextField, placeholder: String, contentType: UITextContentType) {
        field.placeholder = placeholder
        field.borderStyle = .none
        field.backgroundColor = KCDesign.surface
        field.layer.cornerRadius = KCDesign.Radius.md
        field.layer.cornerCurve = .continuous
        field.layer.borderWidth = 1
        field.layer.borderColor = KCDesign.separator.cgColor
        field.textContentType = contentType
        field.font = KCDesign.body()
        field.heightAnchor.constraint(equalToConstant: 50).isActive = true
        let pad = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftView = pad
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.rightViewMode = .always
        field.accessibilityLabel = placeholder
    }

    private func styleInlineError(_ label: UILabel) {
        label.font = KCDesign.caption()
        label.textColor = KCDesign.danger
        label.numberOfLines = 0
        label.isHidden = true
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityTraits = .staticText
    }

    private func loadProviders() async {
        let providers = await NativeLoginService.shared.fetchProviders()
        await MainActor.run {
            googleButton.isHidden = !(providers.google ?? true)
            // Keep Sign in with Apple visible whenever Google is (Guideline 4.8).
            let googleOn = providers.google ?? true
            let appleOn = providers.apple ?? true
            appleButton.isHidden = !(appleOn || googleOn)
            socialCaptionLabel.isHidden = googleButton.isHidden && appleButton.isHidden
            let emailOn = providers.email ?? true
            emailFieldsStack.isHidden = !emailOn
        }
    }

    @objc private func modeChanged() {
        let mode = NativeEmailAuthMode(rawValue: modeControl.selectedSegmentIndex) ?? .signIn
        applyEmailMode(mode, clearErrors: true)
    }

    private func applyEmailMode(_ mode: NativeEmailAuthMode, clearErrors: Bool) {
        emailMode = mode
        modeControl.selectedSegmentIndex = mode.rawValue
        let creating = mode == .createAccount
        nameField.isHidden = !creating
        passwordConfirmField.isHidden = !creating
        passwordField.textContentType = creating ? .newPassword : .password
        passwordField.placeholder = creating
            ? String(localized: "Senha (mín. 8)")
            : String(localized: "Senha")
        passwordField.accessibilityLabel = passwordField.placeholder
        let buttonTitle = creating
            ? String(localized: "Criar conta com email")
            : String(localized: "Entrar com email")
        KCButtonStyle.applyPrimary(to: emailButton, title: buttonTitle)
        forgotPasswordButton.isHidden = creating
        if clearErrors {
            clearFieldErrors()
            statusLabel.text = nil
        } else {
            nameErrorLabel.isHidden = nameErrorLabel.isHidden || !creating
            passwordConfirmErrorLabel.isHidden = passwordConfirmErrorLabel.isHidden || !creating
        }
    }

    private func clearFieldErrors() {
        for label in [nameErrorLabel, emailErrorLabel, passwordErrorLabel, passwordConfirmErrorLabel] {
            label.text = nil
            label.isHidden = true
        }
        for field in [nameField, emailField, passwordField, passwordConfirmField] {
            field.layer.borderColor = KCDesign.separator.cgColor
        }
    }

    private func showFieldErrors(_ result: NativeEmailAuthForm.Result) {
        func apply(_ label: UILabel, _ field: UITextField, _ error: NativeEmailAuthForm.FieldError?) {
            if let error {
                label.text = error.localizedMessage
                label.isHidden = false
                field.layer.borderColor = KCDesign.danger.cgColor
            } else {
                label.text = nil
                label.isHidden = true
                field.layer.borderColor = KCDesign.separator.cgColor
            }
        }
        apply(nameErrorLabel, nameField, result.name)
        apply(emailErrorLabel, emailField, result.email)
        apply(passwordErrorLabel, passwordField, result.password)
        apply(passwordConfirmErrorLabel, passwordConfirmField, result.passwordConfirm)
        if emailMode == .signIn {
            nameErrorLabel.isHidden = true
            passwordConfirmErrorLabel.isHidden = true
        }
    }

    @objc private func tapGoogle() {
        guard !busy else { return }
        KCHaptics.light()
        setBusy(true, message: String(localized: "Abrindo Google…"))
        Task { @MainActor in
            do {
                try await NativeLoginService.shared.signInWithGoogle(from: self)
                finishSignedIn()
            } catch NativeLoginService.LoginError.cancelled {
                setBusy(false, message: nil)
            } catch {
                setBusy(false, message: error.localizedDescription)
            }
        }
    }

    @objc private func tapApple() {
        guard !busy else { return }
        KCHaptics.light()
        setBusy(true, message: String(localized: "Apple…"))
        Task { @MainActor in
            do {
                try await NativeLoginService.shared.signInWithApple(from: self)
                finishSignedIn()
            } catch NativeLoginService.LoginError.cancelled {
                setBusy(false, message: nil)
            } catch {
                setBusy(false, message: error.localizedDescription)
            }
        }
    }

    @objc private func tapEmail() {
        guard !busy else { return }
        let name = nameField.text ?? ""
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""
        let confirm = passwordConfirmField.text ?? ""
        let validation = NativeEmailAuthForm.validate(
            mode: emailMode,
            name: name,
            email: email,
            password: password,
            passwordConfirm: confirm
        )
        showFieldErrors(validation)
        guard validation.isValid else {
            statusLabel.text = validation.firstMessage
            statusLabel.textColor = KCDesign.danger
            return
        }
        KCHaptics.light()
        let creating = emailMode == .createAccount
        setBusy(true, message: creating ? String(localized: "Criando conta…") : String(localized: "Entrando…"))
        Task { @MainActor in
            do {
                if creating {
                    try await NativeLoginService.shared.signUpWithEmail(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        email: email,
                        password: password
                    )
                } else {
                    try await NativeLoginService.shared.signInWithEmail(email: email, password: password)
                }
                finishSignedIn()
            } catch {
                setBusy(false, message: error.localizedDescription)
            }
        }
    }

    @objc private func tapForgotPassword() {
        guard !busy else { return }
        KCHaptics.light()
        let forgot = NativeForgotPasswordViewController()
        forgot.initialEmail = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Forgot VC already dismisses the auth nav and posts session notifications.
        forgot.onSignedIn = { [weak self] in
            self?.onSignedIn?()
        }
        navigationController?.pushViewController(forgot, animated: true)
    }

    private func finishSignedIn() {
        setBusy(false, message: String(localized: "Sessão iniciada."))
        KCHaptics.success()
        NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
        Task { @MainActor in
            _ = await NativePushService.shared.enable()
            await LegacyWebStorageImporter.runIfNeeded()
            await NativeOutbox.flushIfPossible()
        }
        if presentingViewController != nil {
            dismiss(animated: true) { [weak self] in self?.onSignedIn?() }
        } else {
            onSignedIn?()
        }
    }

    private func setBusy(_ value: Bool, message: String?) {
        busy = value
        googleButton.isEnabled = !value
        appleButton.isEnabled = !value
        emailButton.isEnabled = !value
        forgotPasswordButton.isEnabled = !value
        modeControl.isEnabled = !value
        statusLabel.text = message
        statusLabel.textColor = value ? .secondaryLabel : KCDesign.danger
        if message == String(localized: "Sessão iniciada.") { statusLabel.textColor = KCDesign.accent }
    }

    // MARK: - Testing hooks

    func testing_setEmailMode(_ mode: NativeEmailAuthMode) {
        applyEmailMode(mode, clearErrors: true)
    }

    func testing_fill(
        name: String? = nil,
        email: String? = nil,
        password: String? = nil,
        passwordConfirm: String? = nil
    ) {
        if let name { nameField.text = name }
        if let email { emailField.text = email }
        if let password { passwordField.text = password }
        if let passwordConfirm { passwordConfirmField.text = passwordConfirm }
    }

    @discardableResult
    func testing_validateCurrentFields() -> NativeEmailAuthForm.Result {
        let result = NativeEmailAuthForm.validate(
            mode: emailMode,
            name: nameField.text ?? "",
            email: emailField.text ?? "",
            password: passwordField.text ?? "",
            passwordConfirm: passwordConfirmField.text ?? ""
        )
        showFieldErrors(result)
        statusLabel.text = result.firstMessage
        statusLabel.textColor = KCDesign.danger
        return result
    }

    var testing_isNameFieldVisible: Bool { !nameField.isHidden }
    var testing_isPasswordConfirmVisible: Bool { !passwordConfirmField.isHidden }
    var testing_isForgotPasswordVisible: Bool { !forgotPasswordButton.isHidden }
    var testing_forgotPasswordTitle: String? { forgotPasswordButton.title(for: .normal) }
    var testing_emailButtonTitle: String? { emailButton.configuration?.title }
    var testing_statusText: String? { statusLabel.text }
    var testing_emailErrorText: String? { emailErrorLabel.isHidden ? nil : emailErrorLabel.text }
    var testing_passwordErrorText: String? { passwordErrorLabel.isHidden ? nil : passwordErrorLabel.text }
    var testing_passwordConfirmErrorText: String? {
        passwordConfirmErrorLabel.isHidden ? nil : passwordConfirmErrorLabel.text
    }
    var testing_socialCaptionText: String? { socialCaptionLabel.text }

    func testing_openForgotPassword() {
        tapForgotPassword()
    }
}
