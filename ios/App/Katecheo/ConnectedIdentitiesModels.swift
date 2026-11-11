import Foundation

/// Sign-in methods that can be linked on Contas conectadas.
enum ConnectedIdentityProvider: String, CaseIterable, Codable, Equatable {
    case apple
    case google
    case password

    var title: String {
        switch self {
        case .apple: return String(localized: "Apple")
        case .google: return String(localized: "Google")
        case .password: return String(localized: "Email e senha")
        }
    }

    var systemImage: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "g.circle"
        case .password: return "key.fill"
        }
    }

    var unlinkPathValue: String { rawValue }
}

struct ConnectedIdentityDTO: Codable, Equatable {
    let provider: ConnectedIdentityProvider
    let linked: Bool
    let emailMasked: String?
}

struct ConnectedIdentitiesResponse: Codable, Equatable {
    let ok: Bool?
    let identities: [ConnectedIdentityDTO]?
    let minPasswordLength: Int?
    let error: String?
}

/// Pure UI / validation helpers for Contas conectadas (unit-tested).
enum ConnectedIdentitiesLogic {
    static func localizedStatus(linked: Bool) -> String {
        linked ? String(localized: "Conectado") : String(localized: "Conectar")
    }

    static func canUnlink(identities: [ConnectedIdentityDTO], provider: ConnectedIdentityProvider) -> Bool {
        guard let row = identities.first(where: { $0.provider == provider }), row.linked else {
            return false
        }
        let linkedCount = identities.filter(\.linked).count
        return linkedCount > 1
    }

    static func orderedIdentities(_ identities: [ConnectedIdentityDTO]) -> [ConnectedIdentityDTO] {
        let byProvider = Dictionary(uniqueKeysWithValues: identities.map { ($0.provider, $0) })
        return ConnectedIdentityProvider.allCases.map { provider in
            byProvider[provider] ?? ConnectedIdentityDTO(provider: provider, linked: false, emailMasked: nil)
        }
    }

    static func conflictMessage(for provider: ConnectedIdentityProvider) -> String {
        switch provider {
        case .apple:
            return String(localized: "Essa conta Apple já está ligada a outra conta Katecheo.")
        case .google:
            return String(localized: "Essa conta Google já está ligada a outra conta Katecheo.")
        case .password:
            return String(localized: "Não foi possível ligar este método.")
        }
    }

    static func extractErrorCode(from raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = obj["error"] as? String
        {
            return error
        }
        for code in [
            "identity_in_use", "last_method", "current_password_required", "credentials",
            "password_short", "rate_limited", "no_email", "not_linked",
            "apple_disabled", "google_disabled", "email_disabled",
        ] where trimmed.contains(code) {
            return code
        }
        return trimmed
    }

    static func localizedError(code: String?, provider: ConnectedIdentityProvider? = nil, status: Int = 0) -> String {
        let normalized = extractErrorCode(from: code) ?? code
        switch normalized {
        case "identity_in_use":
            return conflictMessage(for: provider ?? .apple)
        case "last_method":
            return String(localized: "Mantenha pelo menos um método de entrada.")
        case "current_password_required":
            return String(localized: "Informe a senha atual para alterar.")
        case "credentials":
            return String(localized: "Senha atual incorreta.")
        case "password_short":
            return String(localized: "A senha deve ter pelo menos 8 caracteres.")
        case "rate_limited":
            return String(localized: "Muitas tentativas. Aguarde um momento.")
        case "no_email":
            return String(localized: "Adicione um email no perfil antes de criar uma senha.")
        case "not_linked":
            return String(localized: "Este método não está conectado.")
        case "apple_disabled", "google_disabled", "email_disabled":
            return String(localized: "Entrar está desligado neste ambiente.")
        default:
            if status == 409 {
                return conflictMessage(for: provider ?? .apple)
            }
            return String(localized: "Não foi possível atualizar as contas conectadas.")
        }
    }

    enum SetPasswordFieldError: Equatable {
        case emptyPassword
        case passwordTooShort
        case passwordMismatch
        case emptyCurrentPassword

        var localizedMessage: String {
            switch self {
            case .emptyPassword:
                return String(localized: "Informe sua senha.")
            case .passwordTooShort:
                return String(localized: "A senha deve ter pelo menos 8 caracteres.")
            case .passwordMismatch:
                return String(localized: "As senhas não coincidem.")
            case .emptyCurrentPassword:
                return String(localized: "Informe a senha atual para alterar.")
            }
        }
    }

    struct SetPasswordValidation: Equatable {
        var currentPassword: SetPasswordFieldError?
        var password: SetPasswordFieldError?
        var passwordConfirm: SetPasswordFieldError?

        var isValid: Bool {
            currentPassword == nil && password == nil && passwordConfirm == nil
        }

        var firstMessage: String? {
            currentPassword?.localizedMessage
                ?? password?.localizedMessage
                ?? passwordConfirm?.localizedMessage
        }
    }

    static func validateSetPassword(
        password: String,
        passwordConfirm: String,
        currentPassword: String,
        hasPassword: Bool,
        minLength: Int = NativeEmailAuthForm.minPasswordLength
    ) -> SetPasswordValidation {
        var result = SetPasswordValidation()
        if hasPassword, currentPassword.isEmpty {
            result.currentPassword = .emptyCurrentPassword
        }
        if password.isEmpty {
            result.password = .emptyPassword
        } else if password.count < minLength {
            result.password = .passwordTooShort
        }
        if passwordConfirm != password {
            result.passwordConfirm = .passwordMismatch
        }
        return result
    }
}
