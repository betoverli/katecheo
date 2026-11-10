import AuthenticationServices
import UIKit

/// Full-screen native sign-in when Keychain has no bearer.
final class NativeSignInViewController: UIViewController {
    var onSignedIn: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private var googleButton: UIButton!
    private var appleButton: ASAuthorizationAppleIDButton!
    private var emailButton: UIButton!
    private var busy = false

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Entrar")
        navigationItem.largeTitleDisplayMode = .never
        if let nav = navigationController {
            KCChrome.applyNavigationBarAppearance(to: nav.navigationBar)
            nav.view.backgroundColor = KCDesign.screenBackground
        }

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
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
        subtitle.text = String(localized: "Anote versículos e reuniões no seu caderno.")
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

        styleField(emailField, placeholder: String(localized: "Email"), contentType: .username)
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no

        styleField(passwordField, placeholder: String(localized: "Senha"), contentType: .password)
        passwordField.isSecureTextEntry = true

        emailButton = UIButton(type: .system)
        KCButtonStyle.applyPrimary(to: emailButton, title: String(localized: "Entrar com email"))
        emailButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        emailButton.addTarget(self, action: #selector(tapEmail), for: .touchUpInside)

        statusLabel.font = KCDesign.caption()
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityTraits = .updatesFrequently

        stack.addArrangedSubview(brandMark)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(KCDesign.Space.lg, after: subtitle)
        stack.addArrangedSubview(googleButton)
        stack.addArrangedSubview(appleButton)
        stack.setCustomSpacing(KCDesign.Space.md, after: appleButton)
        stack.addArrangedSubview(emailField)
        stack.addArrangedSubview(passwordField)
        stack.addArrangedSubview(emailButton)
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
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: appleButtonStyle())
        button.cornerRadius = KCDesign.Radius.md
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.addTarget(self, action: #selector(tapApple), for: .touchUpInside)
        button.accessibilityLabel = String(localized: "Entrar com Apple")
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

    private func loadProviders() async {
        let providers = await NativeLoginService.shared.fetchProviders()
        await MainActor.run {
            googleButton.isHidden = !(providers.google ?? true)
            // Keep Sign in with Apple visible whenever Google is (Guideline 4.8).
            let googleOn = providers.google ?? true
            let appleOn = providers.apple ?? true
            appleButton.isHidden = !(appleOn || googleOn)
            let emailOn = providers.email ?? true
            emailField.isHidden = !emailOn
            passwordField.isHidden = !emailOn
            emailButton.isHidden = !emailOn
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
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""
        guard !email.isEmpty, !password.isEmpty else {
            statusLabel.text = String(localized: "Preencha email e senha.")
            statusLabel.textColor = KCDesign.danger
            return
        }
        KCHaptics.light()
        setBusy(true, message: String(localized: "Entrando…"))
        Task { @MainActor in
            do {
                try await NativeLoginService.shared.signInWithEmail(email: email, password: password)
                finishSignedIn()
            } catch {
                setBusy(false, message: error.localizedDescription)
            }
        }
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
        statusLabel.text = message
        statusLabel.textColor = value ? .secondaryLabel : KCDesign.danger
        if message == String(localized: "Sessão iniciada.") { statusLabel.textColor = KCDesign.accent }
    }
}
