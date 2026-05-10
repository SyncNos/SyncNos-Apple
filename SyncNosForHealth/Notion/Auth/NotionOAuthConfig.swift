import Foundation

enum NotionOAuthConfig {
    static let clientId = "2a8d872b-594c-8060-9a2b-00377c27ec32"
    static let redirectURI = "https://chiimagnus.github.io/syncnos-oauth/callback"
    static let callbackScheme = "syncnos-health-ios"
    static let statePrefix = "syncnos_health_ios_"

    static let authorizationURL = "https://api.notion.com/v1/oauth/authorize"
    static let tokenExchangeProxyURL = "https://syncnos-notion-oauth.chiimagnus.workers.dev/notion/oauth/exchange"
}
