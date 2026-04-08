//
//  readers.swift
//  Claude
//
//  Created by Claude Usage Monitor
//  Copyright 2024. All rights reserved.
//

import Foundation
import Kit

// MARK: - History Storage

public struct UsageSnapshot: Codable {
    public let timestamp: Date
    public let fiveHourUtil: Double
    public let sevenDayUtil: Double
    public let hour: Int  // Hour of day (0-23) for peak analysis
    public let weekday: Int  // Day of week (1-7, 1=Sunday)
    public let delta: Double?  // Change from previous reading (for activity detection)
    public let fiveHourResetsAt: Date?  // When the 5-hour session window resets

    // Computed: session starts 5h before reset
    public var sessionStart: Date? {
        fiveHourResetsAt?.addingTimeInterval(-5 * 3600)
    }
}

public struct ChartDataPoint {
    public let timestamp: Date
    public let value: Double
    public let delta: Double

    public var hasActivity: Bool { delta > 5.0 }
    public var hasIntenseActivity: Bool { delta > 15.0 }
}

public enum SessionState {
    case activity   // API calls made this hour (delta > 5%)
    case inSession  // Within 5h window but no activity this hour
    case idle       // Outside any session (show no bar)
}

public struct SessionBarData {
    public let hour: Int
    public let state: SessionState
    public let sessionUsage: Double  // Session's usage % (0-1), same for all hours in session
    public let sessionIndex: Int  // Index for coloring different sessions (0, 1, 2, ...)
}

// MARK: - Claude Code Session Reader

/// Entry from ~/.claude/history.jsonl
public struct ClaudeHistoryEntry: Codable {
    public let sessionId: String
    public let timestamp: Int64  // milliseconds since epoch
    public let display: String?
    public let project: String?
}

/// Reads actual Claude Code sessions from ~/.claude/history.jsonl
public class ClaudeSessionReader {
    public static let shared = ClaudeSessionReader()

    private var historyPath: String {
        NSString(string: "~/.claude/history.jsonl").expandingTildeInPath
    }

    /// Get sessions with their interaction timestamps from the last 24 hours
    /// Returns: Dictionary of [sessionId: [timestamps]] sorted by first interaction time
    public func getSessionsInLast24Hours() -> [(sessionId: String, timestamps: [Date])] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var sessionTimestamps: [String: [Date]] = [:]

        guard let content = try? String(contentsOfFile: historyPath, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(ClaudeHistoryEntry.self, from: data) else {
                continue
            }

            let timestamp = Date(timeIntervalSince1970: Double(entry.timestamp) / 1000.0)
            if timestamp >= cutoff {
                sessionTimestamps[entry.sessionId, default: []].append(timestamp)
            }
        }

        // Sort sessions by their first interaction time
        return sessionTimestamps
            .map { (sessionId: $0.key, timestamps: $0.value.sorted()) }
            .sorted { $0.timestamps.first ?? Date.distantPast < $1.timestamps.first ?? Date.distantPast }
    }

    /// Get bar data based on real Claude Code sessions
    public func getSessionBarData() -> [SessionBarData] {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        let sessions = getSessionsInLast24Hours()

        // Build bar data for each hour
        var result: [SessionBarData] = []

        for i in 0..<24 {
            let hoursAgo = 23 - i
            let targetHour = (currentHour - hoursAgo + 24) % 24
            let targetDate = now.addingTimeInterval(-Double(hoursAgo) * 3600)
            let targetDayStart = calendar.startOfDay(for: targetDate)

            // Time bounds for this hour
            let hourStart = targetDayStart.addingTimeInterval(Double(targetHour) * 3600)
            let hourEnd = hourStart.addingTimeInterval(3600)

            // Find which session (if any) has activity in this hour
            var matchingSessionIndex: Int? = nil
            var activityCount = 0

            for (index, session) in sessions.enumerated() {
                let hourActivity = session.timestamps.filter { $0 >= hourStart && $0 < hourEnd }
                if !hourActivity.isEmpty {
                    matchingSessionIndex = index
                    activityCount = hourActivity.count
                    break  // Take the first matching session for this hour
                }
            }

            if let sessionIndex = matchingSessionIndex {
                // Normalize activity count to 0-1 range (cap at 10 interactions = full bar)
                let normalizedUsage = min(Double(activityCount) / 10.0, 1.0)
                result.append(SessionBarData(
                    hour: targetHour,
                    state: .activity,
                    sessionUsage: max(normalizedUsage, 0.2),  // Minimum 20% height for visibility
                    sessionIndex: sessionIndex
                ))
            } else {
                result.append(SessionBarData(
                    hour: targetHour,
                    state: .idle,
                    sessionUsage: 0,
                    sessionIndex: -1
                ))
            }
        }

        return result
    }

    /// Get chart data points from history.jsonl for the 24-Hour History chart
    /// This provides activity data even when the app wasn't running
    public func getChartDataFromHistory(hours: Int = 24) -> [ChartDataPoint] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        var allTimestamps: [Date] = []

        guard let content = try? String(contentsOfFile: historyPath, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(ClaudeHistoryEntry.self, from: data) else {
                continue
            }

            let timestamp = Date(timeIntervalSince1970: Double(entry.timestamp) / 1000.0)
            if timestamp >= cutoff {
                allTimestamps.append(timestamp)
            }
        }

        guard !allTimestamps.isEmpty else { return [] }

        // Sort timestamps
        allTimestamps.sort()

        // Create data points - group by rough intervals and calculate activity
        var result: [ChartDataPoint] = []
        var previousValue: Double = 0

        // Group timestamps into ~15 minute buckets and create chart points
        let bucketSize: TimeInterval = 15 * 60  // 15 minutes
        var currentBucketStart = allTimestamps.first!
        var currentBucketCount = 0

        for timestamp in allTimestamps {
            if timestamp.timeIntervalSince(currentBucketStart) < bucketSize {
                currentBucketCount += 1
            } else {
                // Emit point for previous bucket
                if currentBucketCount > 0 {
                    // Simulate usage value based on activity count (more activity = higher "usage")
                    let value = min(Double(currentBucketCount) * 5.0, 100.0) / 100.0
                    let delta = (value - previousValue) * 100
                    result.append(ChartDataPoint(
                        timestamp: currentBucketStart,
                        value: max(value, 0.1),  // Minimum 10% for visibility
                        delta: delta
                    ))
                    previousValue = value
                }

                // Start new bucket
                currentBucketStart = timestamp
                currentBucketCount = 1
            }
        }

        // Don't forget the last bucket
        if currentBucketCount > 0 {
            let value = min(Double(currentBucketCount) * 5.0, 100.0) / 100.0
            let delta = (value - previousValue) * 100
            result.append(ChartDataPoint(
                timestamp: currentBucketStart,
                value: max(value, 0.1),
                delta: delta
            ))
        }

        return result
    }
}

public class UsageHistory {
    public static let shared = UsageHistory()
    private let historyKey = "Claude_UsageHistory"
    private let maxSnapshots = 7 * 24 * 60  // 7 days at 1-min intervals

    private var _snapshots: [UsageSnapshot] = []
    private let queue = DispatchQueue(label: "eu.exelban.claude.history")

    public var snapshots: [UsageSnapshot] {
        queue.sync { _snapshots }
    }

    init() {
        load()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([UsageSnapshot].self, from: data) {
            queue.sync { _snapshots = decoded }
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(_snapshots) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }

    public func add(_ usage: Claude_Usage) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .weekday], from: usage.lastUpdated)

        queue.sync {
            // Only add if last snapshot is >1 min old (avoid duplicates)
            if let last = _snapshots.last {
                let timeSince = usage.lastUpdated.timeIntervalSince(last.timestamp)
                if timeSince < 60 { return }
            }

            // Calculate delta from previous reading
            let delta: Double? = _snapshots.last.map { usage.fiveHourUtil - $0.fiveHourUtil }

            let snapshot = UsageSnapshot(
                timestamp: usage.lastUpdated,
                fiveHourUtil: usage.fiveHourUtil,
                sevenDayUtil: usage.sevenDayUtil,
                hour: components.hour ?? 0,
                weekday: components.weekday ?? 1,
                delta: delta,
                fiveHourResetsAt: usage.fiveHourResetsAt
            )

            _snapshots.append(snapshot)

            // Trim old snapshots
            if _snapshots.count > maxSnapshots {
                _snapshots.removeFirst(_snapshots.count - maxSnapshots)
            }
        }
        save()
    }

    /// Get recent history points for chart (last N hours)
    public func getChartData(hours: Int = 24) -> [Double] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return queue.sync {
            _snapshots
                .filter { $0.timestamp >= cutoff }
                .map { $0.fiveHourUtil / 100.0 }
        }
    }

    /// Get chart data with timestamps and activity indicators
    public func getChartDataWithActivity(hours: Int = 24) -> [ChartDataPoint] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return queue.sync {
            _snapshots
                .filter { $0.timestamp >= cutoff }
                .map { ChartDataPoint(
                    timestamp: $0.timestamp,
                    value: $0.fiveHourUtil / 100.0,
                    delta: $0.delta ?? 0
                )}
        }
    }

    /// Get all snapshots (for persistence verification)
    public var snapshotCount: Int {
        queue.sync { _snapshots.count }
    }

    /// Get hourly data for bar chart (24 bars, one per hour)
    /// Returns data for each hour in the last 24 hours, ordered from oldest to newest
    public func getHourlyBarData() -> [(hour: Int, usage: Double, hasData: Bool, hasActivity: Bool)] {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // Create 24 slots for the last 24 hours
        var hourlyData: [(hour: Int, usage: Double, hasData: Bool, hasActivity: Bool)] = []

        // Go back 23 hours from current hour
        for i in 0..<24 {
            let hoursAgo = 23 - i
            let targetHour = (currentHour - hoursAgo + 24) % 24
            let targetDate = now.addingTimeInterval(-Double(hoursAgo) * 3600)
            let targetDayStart = calendar.startOfDay(for: targetDate)

            // Find snapshots for this hour
            let hourSnapshots = queue.sync {
                _snapshots.filter { snapshot in
                    let snapshotHour = calendar.component(.hour, from: snapshot.timestamp)
                    let snapshotDayStart = calendar.startOfDay(for: snapshot.timestamp)
                    return snapshotHour == targetHour && snapshotDayStart == targetDayStart
                }
            }

            if hourSnapshots.isEmpty {
                hourlyData.append((hour: targetHour, usage: 0, hasData: false, hasActivity: false))
            } else {
                let avgUsage = hourSnapshots.map { $0.fiveHourUtil }.reduce(0, +) / Double(hourSnapshots.count)
                let hasActivity = hourSnapshots.contains { ($0.delta ?? 0) > 5.0 }
                hourlyData.append((hour: targetHour, usage: avgUsage / 100.0, hasData: true, hasActivity: hasActivity))
            }
        }

        return hourlyData
    }

    /// Get session-based bar data for the last 24 hours
    /// Shows session windows with proper gaps between them
    public func getSessionBarData() -> [SessionBarData] {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // Get snapshots from last 30 hours
        let cutoff = now.addingTimeInterval(-30 * 3600)
        let recentSnapshots = queue.sync {
            _snapshots.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
        }

        var sessions: [(start: Date, end: Date, maxUsage: Double)] = []

        // 1. Get current session from latest fiveHourResetsAt
        if let latestWithResetTime = recentSnapshots.last(where: { $0.fiveHourResetsAt != nil }),
           let currentResetsAt = latestWithResetTime.fiveHourResetsAt {
            let currentSessionStart = currentResetsAt.addingTimeInterval(-5 * 3600)
            let currentSessionEnd = currentResetsAt

            // Find max usage within current session window
            let currentSessionSnapshots = recentSnapshots.filter {
                $0.timestamp >= currentSessionStart && $0.timestamp <= currentSessionEnd
            }
            let currentMaxUsage = currentSessionSnapshots.map { $0.fiveHourUtil }.max() ?? latestWithResetTime.fiveHourUtil
            sessions.append((start: currentSessionStart, end: currentSessionEnd, maxUsage: currentMaxUsage))

            // 2. Look for activity BEFORE current session started
            let previousSnapshots = recentSnapshots.filter {
                $0.timestamp < currentSessionStart && $0.fiveHourUtil > 0
            }

            if !previousSnapshots.isEmpty {
                // Find the latest activity before current session
                if let lastPrevActivity = previousSnapshots.last {
                    // This activity belonged to a previous session
                    // Estimate: session ended around when activity stopped or 5h after it started
                    let prevSessionEnd = min(lastPrevActivity.timestamp.addingTimeInterval(5 * 3600), currentSessionStart)
                    let prevSessionStart = prevSessionEnd.addingTimeInterval(-5 * 3600)
                    let prevMaxUsage = previousSnapshots.filter {
                        $0.timestamp >= prevSessionStart && $0.timestamp <= prevSessionEnd
                    }.map { $0.fiveHourUtil }.max() ?? lastPrevActivity.fiveHourUtil

                    sessions.append((start: prevSessionStart, end: prevSessionEnd, maxUsage: prevMaxUsage))
                }
            }
        } else {
            // No fiveHourResetsAt data - fall back to activity-based detection
            let activeSnapshots = recentSnapshots.filter { $0.fiveHourUtil > 0 }
            if let lastActive = activeSnapshots.last {
                let sessionEnd = lastActive.timestamp.addingTimeInterval(5 * 3600)
                let sessionStart = lastActive.timestamp
                let maxUsage = activeSnapshots.map { $0.fiveHourUtil }.max() ?? 0
                sessions.append((start: sessionStart, end: sessionEnd, maxUsage: maxUsage))
            }
        }

        // Build bar data for each hour
        var result: [SessionBarData] = []

        for i in 0..<24 {
            let hoursAgo = 23 - i
            let targetHour = (currentHour - hoursAgo + 24) % 24
            let targetDate = now.addingTimeInterval(-Double(hoursAgo) * 3600)
            let targetDayStart = calendar.startOfDay(for: targetDate)

            // Time bounds for this hour
            let hourStart = targetDayStart.addingTimeInterval(Double(targetHour) * 3600)
            let hourEnd = hourStart.addingTimeInterval(3600)

            // Find if any session covers this hour
            var matchingSession: (start: Date, end: Date, maxUsage: Double)? = nil

            for session in sessions {
                // Check if session covers this hour (overlap check)
                if session.start < hourEnd && session.end > hourStart {
                    // Prefer session with higher usage or more recent
                    if matchingSession == nil || session.maxUsage > matchingSession!.maxUsage {
                        matchingSession = session
                    }
                }
            }

            if let session = matchingSession {
                // Check if there's actual activity in this hour
                let hasActivity = recentSnapshots.contains { snapshot in
                    let snapshotHour = calendar.component(.hour, from: snapshot.timestamp)
                    let snapshotDayStart = calendar.startOfDay(for: snapshot.timestamp)
                    return snapshotHour == targetHour &&
                           snapshotDayStart == targetDayStart &&
                           (snapshot.delta ?? 0) > 5.0
                }

                let state: SessionState = hasActivity ? .activity : .inSession
                result.append(SessionBarData(
                    hour: targetHour,
                    state: state,
                    sessionUsage: session.maxUsage / 100.0,
                    sessionIndex: 0
                ))
            } else {
                result.append(SessionBarData(
                    hour: targetHour,
                    state: .idle,
                    sessionUsage: 0,
                    sessionIndex: -1
                ))
            }
        }

        return result
    }

    /// Analyze peak usage hours (returns hours sorted by average usage)
    public func analyzePeakHours() -> [(hour: Int, avgUsage: Double)] {
        var hourlyUsage: [Int: [Double]] = [:]

        queue.sync {
            for snapshot in _snapshots {
                // Only weekdays
                if snapshot.weekday >= 2 && snapshot.weekday <= 6 {
                    hourlyUsage[snapshot.hour, default: []].append(snapshot.fiveHourUtil)
                }
            }
        }

        return hourlyUsage.map { hour, usages in
            (hour: hour, avgUsage: usages.reduce(0, +) / Double(usages.count))
        }.sorted { $0.avgUsage > $1.avgUsage }
    }
}

internal class UsageReader: Reader<Claude_Usage> {
    private var retryCount = 0
    private let maxRetryCount = 5
    private let baseRetryInterval: TimeInterval = 60

    private var credentialsPath: String {
        Store.shared.string(key: "Claude_credentialsPath", defaultValue: "~/.claude/.credentials.json")
    }

    public override func setup() {
        // Use Web interval if Web is configured, otherwise Code interval
        if ClaudeWebAPI.shared.hasWebAuth {
            self.defaultInterval = Store.shared.int(key: "Claude_webUpdateInterval", defaultValue: 60)
        } else {
            self.defaultInterval = Store.shared.int(key: "Claude_codeUpdateInterval", defaultValue: 300)
        }
    }

    public override func read() {
        // Priority: Web API first (faster updates), Claude Code token as fallback
        if ClaudeWebAPI.shared.hasWebAuth {
            self.fetchUsageViaWebAPI()
        } else if let credentials = self.loadCredentialsFromToken() {
            self.fetchUsageViaOAuth(credentials: credentials, isfallback: false)
        } else {
            var errorUsage = Claude_Usage()
            errorUsage.error = "No credentials configured"
            self.callback(errorUsage)
            self.storeLastFetchResult(error: "No credentials configured")
        }
    }

    private func fetchUsageViaWebAPI() {
        // Try session token first
        if ClaudeWebAPI.shared.hasSessionToken {
            ClaudeWebAPI.shared.fetchUsageWithSessionToken { [weak self] usage, error in
                if let usage = usage {
                    UsageHistory.shared.add(usage)
                    self?.callback(usage)
                    self?.storeLastFetchResult(error: nil)
                } else {
                    // Web API failed - try OAuth as fallback
                    self?.tryOAuthFallback(webError: error)
                }
            }
        } else if ClaudeWebAPI.shared.hasBrowserCookies {
            ClaudeWebAPI.shared.fetchUsageWithBrowserCookies { [weak self] usage, error in
                if let usage = usage {
                    UsageHistory.shared.add(usage)
                    self?.callback(usage)
                    self?.storeLastFetchResult(error: nil)
                } else {
                    // Web API failed - try OAuth as fallback
                    self?.tryOAuthFallback(webError: error)
                }
            }
        } else {
            tryOAuthFallback(webError: "Web auth not configured")
        }
    }

    private func tryOAuthFallback(webError: String?) {
        if let credentials = self.loadCredentialsFromToken() {
            self.fetchUsageViaOAuth(credentials: credentials, isfallback: true)
        } else {
            var errorUsage = Claude_Usage()
            errorUsage.error = webError ?? "No credentials"
            self.callback(errorUsage)
            self.storeLastFetchResult(error: webError)
        }
    }

    private func fetchUsageViaOAuth(credentials: ClaudeCredentials, isfallback: Bool) {
        var usage = Claude_Usage()
        usage.lastUpdated = Date()
        usage.tier = credentials.subscriptionType ?? "Unknown"
        usage.rateLimitTier = credentials.rateLimitTier ?? ""

        self.fetchUsage(credentials: credentials) { [weak self] apiUsage in
            var finalUsage = apiUsage
            if finalUsage.tier.isEmpty {
                finalUsage.tier = usage.tier
            }
            if finalUsage.rateLimitTier.isEmpty {
                finalUsage.rateLimitTier = usage.rateLimitTier
            }

            if finalUsage.error == nil {
                UsageHistory.shared.add(finalUsage)
                self?.storeLastFetchResult(error: nil)
            } else {
                self?.storeLastFetchResult(error: finalUsage.error)
            }

            self?.callback(finalUsage)
        }
    }

    private func storeLastFetchResult(error: String?) {
        Store.shared.set(key: "Claude_lastFetchTime", value: Int(Date().timeIntervalSince1970))
        if let error = error {
            Store.shared.set(key: "Claude_lastFetchError", value: error)
        } else {
            Store.shared.remove("Claude_lastFetchError")
        }
        // Notify settings UI to update
        NotificationCenter.default.post(name: .claudeAuthStateChanged, object: nil)
    }

    /// Load credentials from manually entered token or Keychain
    private func loadCredentialsFromToken() -> ClaudeCredentials? {
        // First check manually entered token
        let token = Store.shared.string(key: "Claude_accessToken", defaultValue: "")
        if !token.isEmpty {
            return ClaudeCredentials(
                accessToken: token,
                refreshToken: "",
                expiresAt: Int64(Date().timeIntervalSince1970 * 1000) + 86400000, // 24h from now
                scopes: ["user:inference"],
                subscriptionType: nil,
                rateLimitTier: nil
            )
        }

        // Fall back to Keychain credentials
        if let creds = ClaudeAuth.shared.getCredentials() {
            return creds
        }

        return nil
    }

    private func loadCredentials() -> ClaudeCredentials? {
        // First try manually entered token
        if let tokenCreds = loadCredentialsFromToken() {
            return tokenCreds
        }

        // Fallback to file path for manual configuration
        let path = NSString(string: self.credentialsPath).expandingTildeInPath

        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }

        do {
            let credentials = try JSONDecoder().decode(CredentialsFile.self, from: data)
            return credentials.claudeAiOauth
        } catch {
            debug("Failed to decode credentials: \(error)")
            return nil
        }
    }

    private func fetchUsage(credentials: ClaudeCredentials, completion: @escaping (Claude_Usage) -> Void) {
        // Correct endpoint: /api/oauth/usage (not /v1/usage)
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            var usage = Claude_Usage()
            usage.error = "Invalid URL"
            completion(usage)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            var usage = Claude_Usage()
            usage.lastUpdated = Date()
            usage.tier = credentials.subscriptionType ?? "Unknown"
            usage.rateLimitTier = credentials.rateLimitTier ?? ""

            if let error = error {
                usage.error = error.localizedDescription
                completion(usage)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                usage.error = "Invalid response"
                completion(usage)
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 429 {
                    self.retryCount += 1
                    let headerRetry = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
                    let backoff = self.baseRetryInterval * pow(2, Double(min(self.retryCount - 1, self.maxRetryCount)))
                    let retryAfter = (headerRetry ?? 0) > 5 ? headerRetry! : backoff  // Ignore retry-after: 0
                    usage.error = "Rate limited (\(Int(retryAfter))s)"
                    debug("429 Rate limited. Retry after: \(retryAfter)s (attempt \(self.retryCount))")
                } else {
                    usage.error = "HTTP \(httpResponse.statusCode)"
                    if let data = data, let errorStr = String(data: data, encoding: .utf8) {
                        debug("API Error: \(errorStr)")
                    }
                }
                completion(usage)
                return
            }

            self.retryCount = 0

            guard let data = data else {
                usage.error = "No data"
                completion(usage)
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(UsageResponse.self, from: data)
                usage = self.parseResponse(apiResponse)
                usage.tier = credentials.subscriptionType ?? usage.tier
            } catch {
                usage.error = "Parse error: \(error.localizedDescription)"
                if let str = String(data: data, encoding: .utf8) {
                    debug("Raw response: \(str)")
                }
            }

            completion(usage)
        }
        task.resume()
    }

    private func parseResponse(_ response: UsageResponse) -> Claude_Usage {
        var usage = Claude_Usage()
        usage.lastUpdated = Date()

        // Configure formatter to handle fractional seconds in API timestamps
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
}

// MARK: - Credential Models

struct CredentialsFile: Codable {
    let claudeAiOauth: ClaudeCredentials
}

struct ClaudeCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int64
    let scopes: [String]
    let subscriptionType: String?
    let rateLimitTier: String?
}

// MARK: - API Response Models (snake_case from API)

struct UsageResponse: Codable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageWindow: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
