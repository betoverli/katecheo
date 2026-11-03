import AuthenticationServices
import UIKit

/// Full-screen native sign-in when Keychain has no bearer.
final class NativeSignInViewController: UIViewController {
    var onSignedIn: (() -> Void)?

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
        view.backgroundColor = .systemBackground
        title = "Entrar"

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let title = UILabel()
        title.text = "Verse2Note"
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Entra para ver o teu caderno."
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        googleButton = UIButton(type: .system)
        googleButton.setTitle("Continuar com Google", for: .normal)
        googleButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        googleButton.backgroundColor = .secondarySystemBackground
        googleButton.layer.cornerRadius = 12
        googleButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        googleButton.addTarget(self, action: #selector(tapGoogle), for: .touchUpInside)

        appleButton = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        appleButton.cornerRadius = 12
        appleButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        appleButton.addTarget(self, action: #selector(tapApple), for: .touchUpInside)

        emailField.placeholder = "Email"
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.borderStyle = .roundedRect
        emailField.textContentType = .username

        passwordField.placeholder = "Palavra-passe"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect
        passwordField.textContentType = .password

        emailButton = UIButton(type: .system)
        emailButton.setTitle("Entrar com email", for: .normal)
        emailButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        emailButton.backgroundColor = .systemBlue
        emailButton.setTitleColor(.white, for: .normal)
        emailButton.layer.cornerRadius = 12
        emailButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        emailButton.addTarget(self, action: #selector(tapEmail), for: .touchUpInside)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(28, after: subtitle)
        stack.addArrangedSubview(googleButton)
        stack.addArrangedSubview(appleButton)
        stack.setCustomSpacing(20, after: appleButton)
        stack.addArrangedSubview(emailField)
        stack.addArrangedSubview(passwordField)
        stack.addArrangedSubview(emailButton)
        stack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        Task { await loadProviders() }
    }

    private func loadProviders() async {
        let providers = await NativeLoginService.shared.fetchProviders()
        await MainActor.run {
            googleButton.isHidden = !(providers.google ?? true)
            appleButton.isHidden = !(providers.apple ?? false)
            let emailOn = providers.email ?? true
            emailField.isHidden = !emailOn
            passwordField.isHidden = !emailOn
            emailButton.isHidden = !emailOn
        }
    }

    @objc private func tapGoogle() {
        guard !busy else { return }
        setBusy(true, message: "A abrir Google…")
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
        setBusy(true, message: "Apple…")
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
            statusLabel.text = "Preenche email e palavra-passe."
            return
        }
        setBusy(true, message: "A entrar…")
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
        setBusy(false, message: "Sessão iniciada.")
        Task { @MainActor in
            _ = await NativePushService.shared.enable()
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
        statusLabel.textColor = value ? .secondaryLabel : .systemRed
        if message == "Sessão iniciada." { statusLabel.textColor = .secondaryLabel }
    }
}
