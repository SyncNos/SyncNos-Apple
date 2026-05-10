import Foundation
import AuthenticationServices
import UIKit

struct NotionOAuthTokenResponse {
    let accessToken: String
    let workspaceId: String?
    let workspaceName: String?
}

@MainActor
final class NotionOAuthService {
    private var session: ASWebAuthenticationSession?

    func performFullAuthorization() async throws -> NotionOAuthTokenResponse {
        guard let code = try await startAuthorization() else {
            throw NSError(
                domain: "NotionOAuthService",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "User canceled authorization"]
            )
        }
        return try await exchangeCodeForToken(code: code)
    }

    private func startAuthorization() async throws -> String? {
        let state = NotionOAuthConfig.statePrefix + UUID().uuidString + "_" + String(Int(Date().timeIntervalSince1970))

        var components = URLComponents(string: NotionOAuthConfig.authorizationURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: NotionOAuthConfig.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
            URLQueryItem(name: "redirect_uri", value: NotionOAuthConfig.redirectURI),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components.url else {
            throw NSError(
                domain: "NotionOAuthService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create authorization URL"]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let s = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: NotionOAuthConfig.callbackScheme
            ) { callbackURL, error in
                defer { self.session = nil }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let queryItems = components.queryItems else {
                    continuation.resume(throwing: NSError(
                        domain: "NotionOAuthService",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL"]
                    ))
                    return
                }

                let receivedState = queryItems.first(where: { $0.name == "state" })?.value
                guard receivedState == state else {
                    continuation.resume(throwing: NSError(
                        domain: "NotionOAuthService",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "State mismatch"]
                    ))
                    return
                }

                if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: NSError(
                        domain: "NotionOAuthService",
                        code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "OAuth error: \(errorParam)"]
                    ))
                    return
                }

                guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: NSError(
                        domain: "NotionOAuthService",
                        code: 7,
                        userInfo: [NSLocalizedDescriptionKey: "No authorization code in callback"]
                    ))
                    return
                }

                continuation.resume(returning: code)
            }

            s.presentationContextProvider = IOSPresentationContextProvider.shared
            self.session = s
            if !s.start() {
                self.session = nil
                continuation.resume(throwing: NSError(
                    domain: "NotionOAuthService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to start authorization session"]
                ))
            }
        }
    }

    private func exchangeCodeForToken(code: String) async throws -> NotionOAuthTokenResponse {
        guard let proxyURL = URL(string: NotionOAuthConfig.tokenExchangeProxyURL) else {
            throw NSError(
                domain: "NotionOAuthService",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Invalid token exchange URL"]
            )
        }

        struct ExchangeRequest: Encodable {
            let code: String
            let redirectUri: String
        }

        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(ExchangeRequest(code: code, redirectUri: NotionOAuthConfig.redirectURI))

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            try await Task.sleep(nanoseconds: 700_000_000)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "NotionOAuthService",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "NotionOAuthService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: HTTP \(httpResponse.statusCode) - \(errorBody)"]
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let accessToken = json["access_token"] as? String else {
            throw NSError(
                domain: "NotionOAuthService",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "No access_token in response"]
            )
        }

        let workspace = json["workspace"] as? [String: Any]
        return NotionOAuthTokenResponse(
            accessToken: accessToken,
            workspaceId: workspace?["id"] as? String,
            workspaceName: workspace?["name"] as? String
        )
    }
}

private final class IOSPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = IOSPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first ?? UIWindow()
    }
}
