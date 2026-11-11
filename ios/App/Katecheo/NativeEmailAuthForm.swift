import Foundation

/// Email auth mode for the native sign-in screen.
enum NativeEmailAuthMode: Int, CaseIterable {
    case signIn = 0
    case createAccount = 1
}

/// Client-side validation for native email sign-in / create-account.
/// `minPasswordLength` matches Better Auth’s default (and `/auth/providers`).
enum NativeEmailAuthForm {
    static let minPasswordLength = 8

    enum FieldError: Equatable {
        case emptyName
        case invalidEmail
        case emptyPassword
        case passwordTooShort
        case passwordMismatch

        var localizedMessage: String {
            switch self {
            case .emptyName:
                return String(localized: "Informe seu nome.")
            case .invalidEmail:
                return String(localized: "Informe um email válido.")
            case .emptyPassword:
                return String(localized: "Informe sua senha.")
            case .passwordTooShort:
                return String(localized: "A senha deve ter pelo menos 8 caracteres.")
            case .passwordMismatch:
                return String(localized: "As senhas não coincidem.")
            }
        }
    }

    struct Result: Equatable {
        var name: FieldError?
        var email: FieldError?
        var password: FieldError?
        var passwordConfirm: FieldError?

        var isValid: Bool {
            name == nil && email == nil && password == nil && passwordConfirm == nil
        }

        var firstMessage: String? {
            name?.localizedMessage
                ?? email?.localizedMessage
                ?? password?.localizedMessage
                ?? passwordConfirm?.localizedMessage
        }
    }

    static func isValidEmail(_ raw: String) -> Bool {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.count >= 5, email.count <= 320 else { return false }
        // Practical check aligned with typical client validation (server still re-checks).
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func validate(
        mode: NativeEmailAuthMode,
        name: String,
        email: String,
        password: String,
        passwordConfirm: String
    ) -> Result {
        var result = Result()
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if mode == .createAccount {
            if trimmedName.isEmpty {
                result.name = .emptyName
            }
        }

        if trimmedEmail.isEmpty || !isValidEmail(trimmedEmail) {
            result.email = .invalidEmail
        }

        if password.isEmpty {
            result.password = .emptyPassword
        } else if mode == .createAccount, password.count < minPasswordLength {
            result.password = .passwordTooShort
        }

        if mode == .createAccount {
            if passwordConfirm.isEmpty {
                result.passwordConfirm = .passwordMismatch
            } else if passwordConfirm != password {
                result.passwordConfirm = .passwordMismatch
            }
        }

        return result
    }
}
