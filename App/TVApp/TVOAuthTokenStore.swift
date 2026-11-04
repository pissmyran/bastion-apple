#if os(tvOS)
import Foundation
import SSHCore

// `OAuthError.cancelled` togs bort (cubic P3) — inget här kastar den, riktigt
// avbrott representeras redan av Swifts egen `CancellationError`.
enum OAuthError: Error, LocalizedError {
    case notConfigured
    case notLoggedIn
    case invalidCallback
    case requestFailed(String)
    case keychainWriteFailed
    case accessDenied
    case expired

    // Utan detta visade UI:t bara ett generiskt "operationen kunde inte
    // slutföras" — även `requestFailed`s faktiska detaljer föll bort
    // (cubic P3).
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Inte konfigurerad — se README \"Kontointegration\"."
        case .notLoggedIn: return "Inte inloggad."
        case .invalidCallback: return "Ogiltigt svar från inloggningen."
        case .requestFailed(let detail): return detail
        case .keychainWriteFailed: return "Kunde inte spara i nyckelringen."
        case .accessDenied: return "Inloggningen nekades."
        case .expired: return "Koden hann gå ut innan inloggningen slutfördes."
        }
    }
}

private struct OAuthErrorBody: Decodable {
    let error: String
    let error_description: String?
}

private struct OAuthTokenRefreshError: Error, LocalizedError {
    // Bara OAuth-protokollets EGET `error_description`-fält (om servern gav
    // ett) — ALDRIG den råa svarskroppen. En proxy/felsida framför
    // token-endpointen kan annars läcka intern diagnostik/HTML rakt in i
    // UI:t via `LocalizedError` (cubic+devin säkerhetsfynd, "Information
    // Disclosure"). Rått svar loggas separat internt, inte här.
    let serverDescription: String?
    let isInvalidGrant: Bool

    var errorDescription: String? {
        serverDescription ?? "Tokenförnyelsen misslyckades."
    }
}

/// tvOS-motsvarighet till `App/OAuthTokenStore.swift` — nyckeln är
/// leverantörens `id`-sträng direkt istället för hela `OAuthProviderConfig`
/// (den PKCE-baserade konfigurationstypen finns inte här, se
/// `TVDeviceFlowOAuthManager.swift` för varför: `ASWebAuthenticationSession`
/// är `API_UNAVAILABLE` på tvOS, device-flow-token-lagringen behöver bara
/// ett id att nyckla på). `OAuthTokenResponse`/`StoredOAuthToken` återanvänds
/// direkt från SSHCore (redan plattformsneutrala, delade med App/).
enum TVOAuthTokenStore {
    // Refreshes are serialized per provider, while the state lock coordinates
    // Keychain mutations without holding a lock across network requests.
    private final class ProviderState {
        let refreshLock = NSLock()
        let stateLock = NSLock()
        var generation = UUID()
    }

    private static let statesLock = NSLock()
    private static var providerStates: [String: ProviderState] = [:]

    private static func state(for providerID: String) -> ProviderState {
        statesLock.lock()
        defer { statesLock.unlock() }
        if let existing = providerStates[providerID] { return existing }
        let new = ProviderState()
        providerStates[providerID] = new
        return new
    }

    private static func keychainKey(_ providerID: String) -> String { "oauth-\(providerID)-token" }

    // `load(for:)`, inte en rå Keychain-koll — en malformerad eller
    // schema-inkompatibel post finns visserligen i Keychain men avvisas
    // av `validAccessToken` som `notLoggedIn` vid varje synk. Genom att
    // basera detta på samma avkodning som `validAccessToken` faktiskt
    // använder hålls "Inloggad"-status i UI:t konsekvent med vad en synk
    // verkligen accepterar (cubic P3).
    static func isLoggedIn(_ providerID: String) -> Bool {
        load(for: providerID) != nil
    }

    // Samma Keychain-IPC-på-main-actor-problem som `Keychain.getAsync` löser
    // — `isLoggedIn`/`load(for:)` läser/avkodar synkront och kan stalla
    // UI:t om den körs vid vy-initiering (cubic P2, tredje
    // granskningsrundan). Samma avkodningslogik som `load(for:)`, bara
    // via den asynkrona Keychain-vägen.
    static func isLoggedInAsync(_ providerID: String) async -> Bool {
        guard let json = await Keychain.getAsync(keychainKey(providerID)) else { return false }
        return (try? JSONDecoder().decode(StoredOAuthToken.self, from: Data(json.utf8))) != nil
    }

    // Returvärdet propageras hela vägen till UI:t (cubic P2) — annars kan
    // "Logga ut" rapportera lyckat medan credentialet faktiskt blir kvar i
    // Keychain om raderingen misslyckas.
    @discardableResult
    static func logout(_ providerID: String) -> Bool {
        let state = state(for: providerID)
        state.stateLock.lock()
        defer { state.stateLock.unlock() }
        state.generation = UUID()
        return Keychain.delete(keychainKey(providerID))
    }

    static func save(_ token: StoredOAuthToken, for providerID: String) throws {
        let state = state(for: providerID)
        state.stateLock.lock()
        defer { state.stateLock.unlock() }
        state.generation = UUID()
        try saveLocked(token, for: providerID)
    }

    // Caller holds the provider's state lock.
    private static func saveLocked(_ token: StoredOAuthToken, for providerID: String) throws {
        let data = try JSONEncoder().encode(token)
        guard Keychain.set(String(decoding: data, as: UTF8.self), for: keychainKey(providerID)) else {
            throw OAuthError.keychainWriteFailed
        }
    }

    static func load(for providerID: String) -> StoredOAuthToken? {
        guard let json = Keychain.get(keychainKey(providerID)) else { return nil }
        return try? JSONDecoder().decode(StoredOAuthToken.self, from: Data(json.utf8))
    }

    /// Hämtar en giltig access token, förnyar tyst via `refresh_token` om
    /// den gått ut. Blockerande — matchar `SyncProvider`s synkrona gränssnitt.
    static func validAccessToken(for providerID: String, tokenEndpoint: URL, clientID: String) throws -> String {
        let state = state(for: providerID)
        state.refreshLock.lock()
        defer { state.refreshLock.unlock() }

        state.stateLock.lock()
        guard let token = load(for: providerID) else {
            state.stateLock.unlock()
            throw OAuthError.notLoggedIn
        }
        guard token.isExpired else {
            state.stateLock.unlock()
            return token.accessToken
        }
        guard let refreshToken = token.refreshToken else {
            state.generation = UUID()
            _ = Keychain.delete(keychainKey(providerID))
            state.stateLock.unlock()
            throw OAuthError.notLoggedIn
        }
        let generation = state.generation
        state.stateLock.unlock()

        do {
            let refreshed = try refresh(refreshToken, tokenEndpoint: tokenEndpoint, clientID: clientID)
            state.stateLock.lock()
            defer { state.stateLock.unlock() }
            guard state.generation == generation else { throw OAuthError.notLoggedIn }
            try saveLocked(refreshed, for: providerID)
            return refreshed.accessToken
        } catch let error as OAuthTokenRefreshError where error.isInvalidGrant {
            // A stale failure must not delete a newer login.
            state.stateLock.lock()
            defer { state.stateLock.unlock() }
            if state.generation == generation {
                state.generation = UUID()
                _ = Keychain.delete(keychainKey(providerID))
            }
            throw OAuthError.notLoggedIn
        }
    }

    private static func refresh(_ refreshToken: String, tokenEndpoint: URL, clientID: String) throws -> StoredOAuthToken {
        // Ett skickat `refresh_token` är en långlivad hemlighet — vägra
        // skicka den till en icke-HTTPS-endpoint (cubic, säkerhetsfynd).
        // Nuvarande anropare använder alltid hårdkodade HTTPS-endpoints,
        // men funktionen är generell nog att en framtida felkonfiguration
        // annars skulle skicka den i klartext.
        guard tokenEndpoint.scheme == "https" else {
            throw OAuthError.requestFailed("token-endpointen måste använda HTTPS")
        }
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        // Utan ett uttryckligt tak kan en hängande proxy/endpoint blockera
        // `refreshLock` (och därmed ANDRA providers om låset delas) på
        // obestämd tid (cubic P3, andra granskningsrundan).
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        let (data, response) = try synchronousRequest(request)
        guard let http = response as? HTTPURLResponse else { throw OAuthError.requestFailed("inget svar") }
        if !(200..<300).contains(http.statusCode) {
            let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data)
            throw OAuthTokenRefreshError(
                serverDescription: body?.error_description,
                isInvalidGrant: body?.error == "invalid_grant")
        }
        let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        return StoredOAuthToken(response: decoded, previousRefreshToken: refreshToken)
    }

    /// `application/x-www-form-urlencoded` kräver striktare kodning än
    /// `.urlQueryAllowed` — den senare lämnar `&`/`+` okodade, vilket får en
    /// token/refresh-token som råkar innehålla dem tolkad som extra fält
    /// eller mellanslag (cubic P2). `formURLEncoded` är samma
    /// karaktärsuppsättning RFC 3986 "unreserved" tillåter, minus `+`
    /// (kodas alltid, aldrig tolkat som mellanslag av mottagaren).
    static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").data(using: .utf8)!
    }

    // Kastar ALDRIG den råa svarskroppen (kan vara en proxy-/felsida med
    // intern diagnostik) — bara en generisk, statuskodbaserad diagnos.
    // Samma resonemang som `OAuthTokenRefreshError` ovan (devin-fynd:
    // synk-anropen här hade fortfarande läckan kvar trots att
    // device-flow-polling redan härdats mot den).
    static func checkHTTPStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw OAuthError.requestFailed(status.map { "Servern svarade med status \($0)." } ?? "Inget svar från servern.")
        }
    }

    /// Blockerande HTTP-anrop, samma motivering som App/OAuthTokenStore.swift.
    static func synchronousRequest(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>!
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            } else {
                result = .failure(OAuthError.requestFailed("tomt svar"))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.get()
    }
}
#endif
