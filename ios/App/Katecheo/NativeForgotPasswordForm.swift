import Foundation

/// Client-side validation for the native forgot / reset password flow.
enum NativeForgotPasswordForm {
    static let codeLength = 6
    static let resendCooldownSeconds = 60

    enum Step: Int, CaseIterable {
        case requestCode = 0
        case resetPassword = 1
    }

    enum FieldError: Equatable {
        case invalidEmail
        case invalidCode
        case emptyPassword
        case passwordTooShort
        case passwordMismatch

        var localizedMessage: String {
            switch self {
            case .invalidEmail:
                return String(localized: "Informe um email válido.")
            case .invalidCode:
                return String(localized: "Informe o código de 6 dígitos.")
            case .emptyPassword:
                return String(localized: "Informe sua senha.")
            case .passwordTooShort:
                return String(localized: "A senha deve ter pelo menos 8 caracteres.")
            case .passwordMismatch:
                return String(localized: "As senhas não coincidem.")
            }
        }
    }

    struct RequestResult: Equatable {
        var email: FieldError?

        var isValid: Bool { email == nil }
        var firstMessage: String? { email?.localizedMessage }
    }

    struct ResetResult: Equatable {
        var code: FieldError?
        var password: FieldError?
        var passwordConfirm: FieldError?

        var isValid: Bool {
            code == nil && password == nil && passwordConfirm == nil
        }

        var firstMessage: String? {
            code?.localizedMessage
                ?? password?.localizedMessage
                ?? passwordConfirm?.localizedMessage
        }
    }

    static func isSixDigitCode(_ raw: String) -> Bool {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.count == codeLength && code.allSatisfy(\.isNumber)
    }

    static func validateRequest(email: String) -> RequestResult {
        var result = RequestResult()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || !NativeEmailAuthForm.isValidEmail(trimmed) {
            result.email = .invalidEmail
        }
        return result
    }

    static func validateReset(
        code: String,
        password: String,
        passwordConfirm: String
    ) -> ResetResult {
        var result = ResetResult()
        if !isSixDigitCode(code) {
            result.code = .invalidCode
        }
        if password.isEmpty {
            result.password = .emptyPassword
        } else if password.count < NativeEmailAuthForm.minPasswordLength {
            result.password = .passwordTooShort
        }
        if passwordConfirm.isEmpty || passwordConfirm != password {
            result.passwordConfirm = .passwordMismatch
        }
        return result
    }
}
