//
//  webapi.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Foundation
import Kit

/// Fetches usage data from claude.ai web API using session cookies
public class ClaudeWebAPI {
    public static let shared = ClaudeWebAPI()

    private let baseURL = "https://claude.ai"

    // Storage keys
    private let sessionKeyKey = "Claude_sessionKey"
    private let orgIdKey = "Claude_orgId"
    private let browserCookiesKey = "Claude_browserCookies"

    /// Check if session token auth is configured
    public var hasSessionToken: Bool {
        let sessionKey = Store.shared.string(key: sessionKeyKey, defaultValue: "")
        let orgId = Store.shared.string(key: orgIdKey, defaultValue: "")
        return !sessionKey.isEmpty && !orgId.isEmpty
    }

    /// Check if browser cookies auth is configured
    public var hasBrowserCookies: Bool {
        let cookies = Store.shared.string(key: browserCookiesKey, defaultValue: "")
        return !cookies.isEmpty && extractOrgIdFromCookies(cookies) != nil
    }

    /// Check if any web auth is configured
    public var hasWebAuth: Bool {
        return hasSessionToken || hasBrowserCookies
    }

    /// Fetch usage using session token
    public func fetchUsageWithSessionToken(completion: @escaping (Claude_Usage?, String?) -> Void) {
        let sessionKey = Store.shared.string(key: sessionKeyKey, defaultValue: "")
        let orgId = Store.shared.string(key: orgIdKey, defaultValue: "")

        guard !sessionKey.isEmpty, !orgId.isEmpty else {
            completion(nil, "Session token or org ID not configured")
            return
        }

        let cookieString = "sessionKey=\(sessionKey); lastActiveOrg=\(orgId)"
        fetchUsage(orgId: orgId, cookies: cookieString, completion: completion)
    }

    /// Fetch usage using browser cookies
    public func fetchUsageWithBrowserCookies(completion: @escaping (Claude_Usage?, String?) -> Void) {
        let cookies = Store.shared.string(key: browserCookiesKey, defaultValue: "")

        guard !cookies.isEmpty else {
            completion(nil, "Browser cookies not configured")
            return
        }

        guard let orgId = extractOrgIdFromCookies(cookies) else {
            completion(nil, "Could not extract org ID from cookies")
            return
        }

        fetchUsage(orgId: orgId, cookies: cookies, completion: completion)
    }

    /// Extract lastActiveOrg from cookie string
    private func extractOrgIdFromCookies(_ cookies: String) -> String? {
        // Parse "lastActiveOrg=uuid-here" from cookie string
        let pattern = "lastActiveOrg=([a-f0-9-]{36})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: cookies, range: NSRange(cookies.startIndex..., in: cookies)),
              let range = Range(match.range(at: 1), in: cookies) else {
            return nil
        }
        return String(cookies[range])
    }

    /// Core fetch method
    private func fetchUsage(orgId: String, cookies: String, completion: @escaping (Claude_Usage?, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/organizations/\(orgId)/usage") else {
            completion(nil, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(nil, "Invalid response")
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    completion(nil, "Session expired - please update credentials")
                } else {
                    completion(nil, "HTTP \(httpResponse.statusCode)")
                }
                return
            }

            guard let data = data else {
                completion(nil, "No data")
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(WebUsageResponse.self, from: data)
                let usage = self.parseResponse(apiResponse)
                let timeStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                debug("[\(timeStr)] Web fetch: 5h=\(Int(usage.fiveHourUtil * 100))%, 7d=\(Int(usage.sevenDayUtil * 100))%")
                completion(usage, nil)
            } catch {
                debug("Web API parse error: \(error)")
                if let str = String(data: data, encoding: .utf8) {
                    debug("Raw response: \(str)")
                }
                completion(nil, "Parse error: \(error.localizedDescription)")
            }
        }
        task.resume()
    }

    private func parseResponse(_ response: WebUsageResponse) -> Claude_Usage {
        var usage = Claude_Usage()
        usage.lastUpdated = Date()
        usage.viaWebAPI = true

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let fiveHour = response.fiveHour {
            usage.fiveHourUtil = fiveHour.utilization ?? 0
            if let resetsAt = fiveHour.resetsAt {
                usage.fiveHourResetsAt = formatter.date(from: resetsAt) ?? Date().addingTimeInterval(5 * 3600)
            }
        }

        if let sevenDay = response.sevenDay {
            usage.sevenDayUtil = sevenDay.utilization ?? 0
            if let resetsAt = sevenDay.resetsAt {
                usage.sevenDayResetsAt = formatter.date(from: resetsAt) ?? Date().addingTimeInterval(7 * 24 * 3600)
            }
        }

        if let opus = response.sevenDayOpus {
            usage.opusUtil = opus.utilization ?? 0
        }

        if let sonnet = response.sevenDaySonnet {
            usage.sonnetUtil = sonnet.utilization ?? 0
        }

        return usage
    }

    // MARK: - Credential Management

    public func setSessionToken(_ sessionKey: String, orgId: String) {
        Store.shared.set(key: sessionKeyKey, value: sessionKey)
        Store.shared.set(key: orgIdKey, value: orgId)
    }

    public func clearSessionToken() {
        Store.shared.remove(sessionKeyKey)
        Store.shared.remove(orgIdKey)
    }

    public func setBrowserCookies(_ cookies: String) {
        Store.shared.set(key: browserCookiesKey, value: cookies)
    }

    public func clearBrowserCookies() {
        Store.shared.remove(browserCookiesKey)
    }

    public func getSessionKey() -> String {
        return Store.shared.string(key: sessionKeyKey, defaultValue: "")
    }

    public func getOrgId() -> String {
        return Store.shared.string(key: orgIdKey, defaultValue: "")
    }

    public func getBrowserCookies() -> String {
        return Store.shared.string(key: browserCookiesKey, defaultValue: "")
    }
}

// MARK: - Web API Response Models

struct WebUsageResponse: Codable {
    let fiveHour: WebUsageWindow?
    let sevenDay: WebUsageWindow?
    let sevenDayOpus: WebUsageWindow?
    let sevenDaySonnet: WebUsageWindow?
    let sevenDayOauthApps: WebUsageWindow?
    let sevenDayCowork: WebUsageWindow?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }
}

struct WebUsageWindow: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}
