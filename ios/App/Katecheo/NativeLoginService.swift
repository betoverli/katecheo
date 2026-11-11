import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Native sign-in against Katecheo Better Auth → Keychain bearer.
final class NativeLoginService: NSObject {
    static let shared = NativeLoginService()

    struct Providers: Decodable {
        let ok: Bool?
        let google: Bool?
        let apple: Bool?
        let email: Bool?
        let minPasswordLength: Int?
    }

    struct TokenResponse: Decodable {
        let ok: Bool?
        let token: String?
        let error: String?
    }

    private var authSession: ASWebAuthenticationSession?
    private var appleContinuation: CheckedContinuation<String, Error>?
    private var appleNonce: String?

    private var anchor = AuthPresentationAnchor()

    // MARK: - Providers

    func fetchProviders(force: Bool = false) async -> Providers {
        // Apple defaults on so App Store 4.8 always shows the button next to Google
        // even if /auth/providers is unreachable; the server still gates the exchange.
        let fallback = Providers(
            ok: true,
            google: true,
            apple: true,
            email: true,
            minPasswordLength: NativeEmailAuthForm.minPasswordLength
        )
        if !force,
           let at = NativeSWR.authProvidersFetchedAt(),
           Date().timeIntervalSince(at) < NativeSWR.TTL.authProviders,
           let cached = NativeSWR.loadAuthProvidersJSON(),
           let decoded = try? JSONDecoder().decode(Providers.self, from: cached)
        {
            NativeSWR.recordNetworkHit("cache:auth/providers")
            return decoded
        }
        do {
            var request = URLRequest(url: NativeAPIClient.baseURL.appendingPathComponent("api/native/v1/auth/providers"))
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            NativeSWR.recordNetworkHit("/api/native/v1/auth/providers")
            let (data, _) = try await NativeAPIClient.session.data(for: request)
            if let decoded = try? JSONDecoder().decode(Providers.self, from: data) {
                NativeSWR.saveAuthProvidersJSON(data)
                NativeSWR.markFetched(.authProviders, value: decoded)
                return decoded
            }
            return fallback
        } catch {
            if let cached = NativeSWR.loadAuthProvidersJSON(),
               let decoded = try? JSONDecoder().decode(Providers.self, from: cached)
            {
                return decoded
            }
            return fallback
        }
    }

    // MARK: - Google (ASWebAuthenticationSession + PKCE claim)

    private enum GoogleReturnMode {
        case https
        case scheme

        var queryValue: String {
            switch self {
            case .https: return "https"
            case .scheme: return "scheme"
            }
        }
    }

    /// Prefer HTTPS Universal Links on iOS 17.4+; fall back once to the custom scheme
    /// when the HTTPS session fails for a non-cancel reason (missing webcredentials, etc.).
    @MainActor
    func signInWithGoogle(from presenter: UIViewController) async throws {
        anchor.windowProvider = { presenter.view.window }

        if #available(iOS 17.4, *) {
            do {
                try await completeGoogleSignIn(returnMode: .https)
            } catch {
                if Self.shouldFallBackToScheme(error) {
                    // Fresh PKCE for the scheme retry — previous verifier is bound to the failed https attempt.
                    try await completeGoogleSignIn(returnMode: .scheme)
                } else {
                    throw error
                }
            }
        } else {
            try await completeGoogleSignIn(returnMode: .scheme)
        }
    }

    @MainActor
    private func completeGoogleSignIn(returnMode: GoogleReturnMode) async throws {
        let verifier = Self.newPkceVerifier()
        let challenge = Self.pkceChallenge(verifier)
        var components = URLComponents(
            url: NativeAPIClient.baseURL.appendingPathComponent("auth/native-start"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "providerId", value: "google"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "return", value: returnMode.queryValue),
        ]
        guard let startURL = components.url else { throw LoginError.invalidURL }

        let callbackURL = try await runAuthSession(url: startURL, returnMode: returnMode)

        let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        if comps?.queryItems?.contains(where: { $0.name == "error" }) == true {
            throw LoginError.failed(String(localized: "Login Google cancelado ou falhou."))
        }
        guard let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw LoginError.failed(String(localized: "Código de login em falta."))
        }
        let token = try await claim(code: code, verifier: verifier)
        _ = KeychainStore.setBearerToken(token)
    }

    /// Runs `ASWebAuthenticationSession` for either HTTPS Universal Link or custom-scheme return.
    @MainActor
    private func runAuthSession(url: URL, returnMode: GoogleReturnMode) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let finish: ASWebAuthenticationSession.CompletionHandler = { callbackURL, error in
                self.authSession = nil
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    {
                        continuation.resume(throwing: LoginError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: LoginError.cancelled)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                let callback: ASWebAuthenticationSession.Callback
                switch returnMode {
                case .https:
                    callback = .https(host: AppSite.primaryHost, path: "/auth/native-return")
                case .scheme:
                    callback = .customScheme("katecheo")
                }
                session = ASWebAuthenticationSession(url: url, callback: callback, completionHandler: finish)
            } else {
                session = ASWebAuthenticationSession(url: url, callbackURLScheme: "katecheo", completionHandler: finish)
            }
            session.presentationContextProvider = self.anchor
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                self.authSession = nil
                continuation.resume(throwing: LoginError.failed(String(localized: "Não foi possível abrir o login Google.")))
            }
        }
    }

    /// Mirror of server `shouldFallBackToScheme`: retry scheme only when the HTTPS attempt
    /// failed for a reason that is not a user cancel.
    private static func shouldFallBackToScheme(_ error: Error) -> Bool {
        if case LoginError.cancelled = error { return false }
        let message: String
        if let localized = error as? LocalizedError, let desc = localized.errorDescription {
            message = desc
        } else {
            message = error.localizedDescription
        }
        return message.range(of: "cancel", options: .caseInsensitive) == nil
    }

    private func claim(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: NativeAPIClient.baseURL.appendingPathComponent("api/native/v1/auth/claim"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "verifier": verifier])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)
        guard status >= 200, status < 300, let token = decoded?.token, !token.isEmpty else {
            throw LoginError.failed(decoded?.error ?? String(localized: "Falha ao obter sessão."))
        }
        return token
    }

    // MARK: - Apple

    @MainActor
    func signInWithApple(from presenter: UIViewController) async throws {
        let rawNonce = Self.randomNonce()
        appleNonce = rawNonce
        let hashed = Self.sha256(rawNonce)

        let token: String = try await withCheckedThrowingContinuation { continuation in
            self.appleContinuation = continuation
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashed
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
        _ = KeychainStore.setBearerToken(token)
    }

    // MARK: - Email

    func signInWithEmail(email: String, password: String) async throws {
        var request = URLRequest(url: NativeAPIClient.baseURL.appendingPathComponent("api/native/v1/auth/email"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)
        guard status >= 200, status < 300, let token = decoded?.token, !token.isEmpty else {
            throw LoginError.failed(decoded?.error == "credentials" ? String(localized: "Email ou senha incorretos.") : (decoded?.error ?? String(localized: "Falha no login.")))
        }
        _ = KeychainStore.setBearerToken(token)
    }

    func signUpWithEmail(name: String, email: String, password: String) async throws {
        var request = URLRequest(url: NativeAPIClient.baseURL.appendingPathComponent("api/native/v1/auth/email/sign-up"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "email": email,
            "password": password,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)
        guard status >= 200, status < 300, let token = decoded?.token, !token.isEmpty else {
            throw LoginError.failed(Self.localizedSignUpError(code: decoded?.error, status: status))
        }
        _ = KeychainStore.setBearerToken(token)
    }

    private static func localizedSignUpError(code: String?, status: Int) -> String {
        switch code {
        case "email_exists":
            return String(localized: "Este email já tem conta. Entre com a senha ou use Google/Apple.")
        case "password_short":
            return String(localized: "A senha deve ter pelo menos 8 caracteres.")
        case "invalid_email":
            return String(localized: "Informe um email válido.")
        case "email_disabled":
            return String(localized: "Entrar está desligado neste ambiente.")
        case "rate_limited":
            return String(localized: "Muitas tentativas. Aguarde um momento.")
        default:
            if status == 409 {
                return String(localized: "Este email já tem conta. Entre com a senha ou use Google/Apple.")
            }
            return code ?? String(localized: "Não foi possível criar a conta.")
        }
    }

    // MARK: - Sign out

    func signOut() async {
        if let token = KeychainStore.bearerToken(), !token.isEmpty {
            var request = URLRequest(url: NativeAPIClient.baseURL.appendingPathComponent("api/native/v1/auth/sign-out"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            _ = try? await URLSession.shared.data(for: request)
        }
        let accountId = LocalSessionCache.loadMe()?.id
        KeychainStore.deleteBearerToken()
        KCActivityStore.clearAccount(accountId)
        LocalSessionCache.clearAll()
        NativeSWR.clearAccountScoped()
        LocalSessionCache.showOfflineHint = false
        UserDefaults.standard.removeObject(forKey: NativeSessionBootstrap.migratedFlagKey)
    }

    // MARK: - PKCE / nonce helpers

    private static func newPkceVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func pkceChallenge(_ verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Apple expects the SHA-256 digest of the raw nonce (hex) on the request;
    /// the identity token echoes that digest in its `nonce` claim.
    private static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    enum LoginError: LocalizedError {
        case cancelled
        case invalidURL
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return String(localized: "Login cancelado.")
            case .invalidURL: return String(localized: "URL de login inválida.")
            case .failed(let message): return message
            }
        }
    }
}

extension NativeLoginService: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor.windowProvider() ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            appleContinuation?.resume(throwing: LoginError.failed(String(localized: "Token Apple em falta.")))
            appleContinuation = nil
            return
        }
        let nonce = appleNonce
        Task {
            do {
                var request = URLRequest(url: NativeAPIClient.baseURL.appendingPathComponent("api/native/v1/auth/apple"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                var body: [String: Any] = ["identityToken": identityToken]
                if let nonce { body["nonce"] = nonce }
                if let codeData = credential.authorizationCode,
                   let code = String(data: codeData, encoding: .utf8),
                   !code.isEmpty
                {
                    body["authorizationCode"] = code
                }
                // Apple only returns the person's name on the first authorization.
                if let fullName = credential.fullName {
                    var name: [String: String] = [:]
                    if let given = fullName.givenName, !given.isEmpty { name["givenName"] = given }
                    if let family = fullName.familyName, !family.isEmpty { name["familyName"] = family }
                    if !name.isEmpty { body["fullName"] = name }
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)
                if status == 501 {
                    throw LoginError.failed(String(localized: "Sign in with Apple ainda não está configurado no servidor."))
                }
                guard status >= 200, status < 300, let token = decoded?.token, !token.isEmpty else {
                    throw LoginError.failed(decoded?.error ?? String(localized: "Falha no login Apple."))
                }
                appleContinuation?.resume(returning: token)
            } catch {
                appleContinuation?.resume(throwing: error)
            }
            appleContinuation = nil
            appleNonce = nil
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let ns = error as NSError
        if ns.code == ASAuthorizationError.canceled.rawValue {
            appleContinuation?.resume(throwing: LoginError.cancelled)
        } else {
            appleContinuation?.resume(throwing: error)
        }
        appleContinuation = nil
        appleNonce = nil
    }
}

private final class AuthPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    var windowProvider: () -> UIWindow? = { nil }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = windowProvider(), window.windowScene != nil { return window }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.keyWindow { return window }
        if let window = scene?.windows.first(where: { $0.isKeyWindow && !$0.isHidden }) { return window }
        if let scene { return UIWindow(windowScene: scene) }
        return ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
