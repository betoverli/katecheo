import UIKit

/// Native two-step forgot-password flow (request code → reset + sign in).
/// No website reset page — everything stays inside the iOS app.
final class NativeForgotPasswordViewController: UIViewController {
    var onSignedIn: (() -> Void)?
    var initialEmail: String = ""

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()

    private let emailField = UITextField()
    private let emailErrorLabel = UILabel()
    private let sendCodeButton = UIButton(type: .system)

    private let codeField = UITextField()
    private let codeErrorLabel = UILabel()
    private let passwordField = UITextField()
    private let passwordErrorLabel = UILabel()
    private let passwordConfirmField = UITextField()
    private let passwordConfirmErrorLabel = UILabel()
    private let resetButton = UIButton(type: .system)
    private let resendButton = UIButton(type: .system)

    private var stepStack: UIStackView!
    private var requestStack: UIStackView!
    private var resetStack: UIStackView!

    private(set) var step: NativeForgotPasswordForm.Step = .requestCode
    private var busy = false
    private var resendAvailableAt: Date?
    private var resendTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Esqueci minha senha")
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

        let lead = UILabel()
        lead.text = String(localized: "Enviaremos um código de 6 dígitos para o seu email.")
        lead.font = KCDesign.body()
        lead.textColor = .secondaryLabel
        lead.numberOfLines = 0
        lead.textAlignment = .center
        lead.adjustsFontForContentSizeCategory = true

        styleField(emailField, placeholder: String(localized: "Email"), contentType: .emailAddress)
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.text = initialEmail

        styleField(codeField, placeholder: String(localized: "Código de 6 dígitos"), contentType: .oneTimeCode)
        codeField.keyboardType = .numberPad
        codeField.textContentType = .oneTimeCode
        codeField.autocorrectionType = .no
        codeField.autocapitalizationType = .none

        styleField(passwordField, placeholder: String(localized: "Nova senha (mín. 8)"), contentType: .newPassword)
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .newPassword

        styleField(passwordConfirmField, placeholder: String(localized: "Confirmar nova senha"), contentType: .newPassword)
        passwordConfirmField.isSecureTextEntry = true
        passwordConfirmField.textContentType = .newPassword

        styleInlineError(emailErrorLabel)
        styleInlineError(codeErrorLabel)
        styleInlineError(passwordErrorLabel)
        styleInlineError(passwordConfirmErrorLabel)

        KCButtonStyle.applyPrimary(to: sendCodeButton, title: String(localized: "Enviar código"))
        sendCodeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        sendCodeButton.addTarget(self, action: #selector(tapSendCode), for: .touchUpInside)

        KCButtonStyle.applyPrimary(to: resetButton, title: String(localized: "Redefinir senha"))
        resetButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        resetButton.addTarget(self, action: #selector(tapReset), for: .touchUpInside)

        resendButton.setTitle(String(localized: "Reenviar código"), for: .normal)
        resendButton.titleLabel?.font = KCDesign.body()
        resendButton.titleLabel?.adjustsFontForContentSizeCategory = true
        resendButton.setTitleColor(KCDesign.accent, for: .normal)
        resendButton.setTitleColor(.tertiaryLabel, for: .disabled)
        resendButton.addTarget(self, action: #selector(tapResend), for: .touchUpInside)
        resendButton.accessibilityLabel = String(localized: "Reenviar código")

        statusLabel.font = KCDesign.caption()
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityTraits = .updatesFrequently

        requestStack = UIStackView(arrangedSubviews: [
            emailField,
            emailErrorLabel,
            sendCodeButton,
        ])
        requestStack.axis = .vertical
        requestStack.spacing = KCDesign.Space.xs

        resetStack = UIStackView(arrangedSubviews: [
            codeField,
            codeErrorLabel,
            passwordField,
            passwordErrorLabel,
            passwordConfirmField,
            passwordConfirmErrorLabel,
            resetButton,
            resendButton,
        ])
        resetStack.axis = .vertical
        resetStack.spacing = KCDesign.Space.xs

        stepStack = UIStackView(arrangedSubviews: [requestStack, resetStack])
        stepStack.axis = .vertical
        stepStack.spacing = KCDesign.Space.sm

        stack.addArrangedSubview(lead)
        stack.setCustomSpacing(KCDesign.Space.lg, after: lead)
        stack.addArrangedSubview(stepStack)
        stack.setCustomSpacing(KCDesign.Space.sm, after: stepStack)
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

        applyStep(.requestCode, clearErrors: true)
    }

    deinit {
        resendTimer?.invalidate()
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
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
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
    }

    private func applyStep(_ next: NativeForgotPasswordForm.Step, clearErrors: Bool) {
        step = next
        requestStack.isHidden = next != .requestCode
        resetStack.isHidden = next != .resetPassword
        if clearErrors {
            clearFieldErrors()
            if next == .requestCode {
                statusLabel.text = nil
            }
        }
        updateResendTitle()
    }

    private func clearFieldErrors() {
        for label in [emailErrorLabel, codeErrorLabel, passwordErrorLabel, passwordConfirmErrorLabel] {
            label.text = nil
            label.isHidden = true
        }
        for field in [emailField, codeField, passwordField, passwordConfirmField] {
            field.layer.borderColor = KCDesign.separator.cgColor
        }
    }

    @objc private func tapSendCode() {
        guard !busy else { return }
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = NativeForgotPasswordForm.validateRequest(email: email)
        if let error = validation.email {
            emailErrorLabel.text = error.localizedMessage
            emailErrorLabel.isHidden = false
            emailField.layer.borderColor = KCDesign.danger.cgColor
            statusLabel.text = validation.firstMessage
            statusLabel.textColor = KCDesign.danger
            return
        }
        emailErrorLabel.isHidden = true
        emailField.layer.borderColor = KCDesign.separator.cgColor
        sendCode(email: email, advancing: true)
    }

    @objc private func tapResend() {
        guard !busy, canResend else { return }
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = NativeForgotPasswordForm.validateRequest(email: email)
        guard validation.isValid else {
            statusLabel.text = validation.firstMessage
            statusLabel.textColor = KCDesign.danger
            return
        }
        sendCode(email: email, advancing: false)
    }

    private func sendCode(email: String, advancing: Bool) {
        KCHaptics.light()
        setBusy(true, message: String(localized: "Enviando código…"))
        Task { @MainActor in
            do {
                try await NativeLoginService.shared.requestPasswordReset(
                    email: email,
                    locale: AppLocale.apiCode
                )
                resendAvailableAt = Date().addingTimeInterval(
                    TimeInterval(NativeForgotPasswordForm.resendCooldownSeconds)
                )
                startResendTimer()
                setBusy(false, message: String(localized: "Se existir uma conta, enviamos um código."))
                statusLabel.textColor = KCDesign.accent
                if advancing {
                    applyStep(.resetPassword, clearErrors: true)
                    statusLabel.text = String(localized: "Se existir uma conta, enviamos um código.")
                    statusLabel.textColor = KCDesign.accent
                }
            } catch {
                setBusy(false, message: error.localizedDescription)
            }
        }
    }

    @objc private func tapReset() {
        guard !busy else { return }
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (codeField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""
        let confirm = passwordConfirmField.text ?? ""
        let validation = NativeForgotPasswordForm.validateReset(
            code: code,
            password: password,
            passwordConfirm: confirm
        )
        showResetErrors(validation)
        guard validation.isValid else {
            statusLabel.text = validation.firstMessage
            statusLabel.textColor = KCDesign.danger
            return
        }
        KCHaptics.light()
        setBusy(true, message: String(localized: "Redefinindo senha…"))
        Task { @MainActor in
            do {
                try await NativeLoginService.shared.resetPasswordWithCode(
                    email: email,
                    code: code,
                    newPassword: password
                )
                finishSignedIn()
            } catch {
                setBusy(false, message: error.localizedDescription)
            }
        }
    }

    private func showResetErrors(_ result: NativeForgotPasswordForm.ResetResult) {
        func apply(_ label: UILabel, _ field: UITextField, _ error: NativeForgotPasswordForm.FieldError?) {
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
        apply(codeErrorLabel, codeField, result.code)
        apply(passwordErrorLabel, passwordField, result.password)
        apply(passwordConfirmErrorLabel, passwordConfirmField, result.passwordConfirm)
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
        if let nav = navigationController, nav.presentingViewController != nil {
            nav.dismiss(animated: true) { [weak self] in self?.onSignedIn?() }
        } else if presentingViewController != nil {
            dismiss(animated: true) { [weak self] in self?.onSignedIn?() }
        } else {
            onSignedIn?()
        }
    }

    private var canResend: Bool {
        guard let until = resendAvailableAt else { return true }
        return Date() >= until
    }

    private func startResendTimer() {
        resendTimer?.invalidate()
        updateResendTitle()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateResendTitle()
        }
    }

    private func updateResendTitle() {
        if canResend {
            resendButton.setTitle(String(localized: "Reenviar código"), for: .normal)
            resendButton.isEnabled = !busy
            if resendAvailableAt != nil, Date() >= (resendAvailableAt ?? .distantPast) {
                resendTimer?.invalidate()
                resendTimer = nil
            }
            return
        }
        let remaining = max(0, Int(ceil((resendAvailableAt ?? Date()).timeIntervalSinceNow)))
        resendButton.setTitle(
            String(format: String(localized: "Reenviar em %d s"), remaining),
            for: .normal
        )
        resendButton.isEnabled = false
    }

    private func setBusy(_ value: Bool, message: String?) {
        busy = value
        sendCodeButton.isEnabled = !value
        resetButton.isEnabled = !value
        emailField.isEnabled = !value
        codeField.isEnabled = !value
        passwordField.isEnabled = !value
        passwordConfirmField.isEnabled = !value
        updateResendTitle()
        statusLabel.text = message
        if message == String(localized: "Sessão iniciada.")
            || message == String(localized: "Se existir uma conta, enviamos um código.")
        {
            statusLabel.textColor = KCDesign.accent
        } else if value {
            statusLabel.textColor = .secondaryLabel
        } else {
            statusLabel.textColor = KCDesign.danger
        }
    }

    // MARK: - Testing hooks

    func testing_setStep(_ step: NativeForgotPasswordForm.Step) {
        applyStep(step, clearErrors: true)
    }

    func testing_fill(
        email: String? = nil,
        code: String? = nil,
        password: String? = nil,
        passwordConfirm: String? = nil
    ) {
        if let email { emailField.text = email }
        if let code { codeField.text = code }
        if let password { passwordField.text = password }
        if let passwordConfirm { passwordConfirmField.text = passwordConfirm }
    }

    @discardableResult
    func testing_validateRequest() -> NativeForgotPasswordForm.RequestResult {
        let result = NativeForgotPasswordForm.validateRequest(email: emailField.text ?? "")
        if let error = result.email {
            emailErrorLabel.text = error.localizedMessage
            emailErrorLabel.isHidden = false
            emailField.layer.borderColor = KCDesign.danger.cgColor
        }
        statusLabel.text = result.firstMessage
        statusLabel.textColor = KCDesign.danger
        return result
    }

    @discardableResult
    func testing_validateReset() -> NativeForgotPasswordForm.ResetResult {
        let result = NativeForgotPasswordForm.validateReset(
            code: codeField.text ?? "",
            password: passwordField.text ?? "",
            passwordConfirm: passwordConfirmField.text ?? ""
        )
        showResetErrors(result)
        statusLabel.text = result.firstMessage
        statusLabel.textColor = KCDesign.danger
        return result
    }

    var testing_isRequestVisible: Bool { !requestStack.isHidden }
    var testing_isResetVisible: Bool { !resetStack.isHidden }
    var testing_statusText: String? { statusLabel.text }
    var testing_emailText: String? { emailField.text }
    var testing_codeContentType: UITextContentType? { codeField.textContentType }
    var testing_codeKeyboard: UIKeyboardType { codeField.keyboardType }
}
