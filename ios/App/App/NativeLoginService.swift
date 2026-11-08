import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Native sign-in against verse2note.com Better Auth → Keychain bearer.
final class NativeLoginService: NSObject {
    static let shared = NativeLoginService()

    struct Providers: Decodable {
        let ok: Bool?
        let google: Bool?
        let apple: Bool?
        let email: Bool?
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

    func fetchProviders() async -> Providers {
        do {
            var request = URLRequest(url: NativeAPIClient.baseURL.appendingPathComponent("api/native/v1/auth/providers"))
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            return (try? JSONDecoder().decode(Providers.self, from: data)) ?? Providers(ok: true, google: true, apple: false, email: true)
        } catch {
            return Providers(ok: true, google: true, apple: false, email: true)
        }
    }

    // MARK: - Google (ASWebAuthenticationSession + PKCE claim)

    @MainActor
    func signInWithGoogle(from presenter: UIViewController) async throws {
        let verifier = Self.newPkceVerifier()
        let challenge = Self.pkceChallenge(verifier)
        var components = URLComponents(url: NativeAPIClient.baseURL.appendingPathComponent("auth/native-start"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "providerId", value: "google"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "return", value: "scheme"),
        ]
        guard let startURL = components.url else { throw LoginError.invalidURL }

        anchor.windowProvider = { presenter.view.window }
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: startURL, callbackURLScheme: "verse2note") { url, error in
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
                guard let url else {
                    continuation.resume(throwing: LoginError.cancelled)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self.anchor
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                self.authSession = nil
                continuation.resume(throwing: LoginError.failed(String(localized: "Não foi possível abrir o login Google.")))
            }
        }

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

    // MARK: - Sign out

    func signOut() async {
        if let token = KeychainStore.bearerToken(), !token.isEmpty {
            var request = URLRequest(url: NativeAPIClient.baseURL.appendingPathComponent("api/native/v1/auth/sign-out"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainStore.deleteBearerToken()
        LocalSessionCache.clearAll()
        V2NActivityStore.clearAccount()
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

    private static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return Data(hash).base64URLEncodedString()
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
