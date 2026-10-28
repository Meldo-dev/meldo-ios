import Foundation

/// When each synced item last changed on any device, and which were deleted.
/// Keys are "<collection>:<id>" for list items and the field name for single
/// values ("preferences", "untisTimetable"). `LocalStore.update` keeps it
/// current for every write, from the app or a widget, so no feature code has
/// to remember to report its changes.
nonisolated struct SyncLedger: Codable, Hashable {
    var stamps: [String: Date] = [:]
    var tombstones: [String: Date] = [:]
}

/// Item-by-item merge of two devices' data: for each item the newer change
/// wins, and a deletion wins over an older edit. Pure, so it is tested without Google Drive.
nonisolated enum SyncMerge {
    /// Stamps what differs between `old` and `new` (both written by this device) at `now`.
    /// A change is always stamped after every stamp this device has seen (a hybrid logical
    /// clock), so a device whose clock runs ahead can't make its edits win over later ones.
    static func record(from old: AppData, to new: inout AppData, at clock: Date) {
        var ledger = new.sync
        let seen = max(ledger.stamps.values.max() ?? .distantPast, ledger.tombstones.values.max() ?? .distantPast)
        let now = max(clock, seen.addingTimeInterval(0.001))
        func note(_ key: String, before: Data?, after: Data?) {
            guard before != after else { return }
            if after == nil {
                ledger.stamps[key] = nil
                ledger.tombstones[key] = now
            } else {
                ledger.stamps[key] = now
                ledger.tombstones[key] = nil
            }
        }
        // A refresh only moving "last updated" is no edit: it must not beat a disconnect
        // (tombstone) made on another device in the meantime.
        var old = old, current = new
        old.untis?.lastSync = nil; current.untis?.lastSync = nil
        old.teams?.lastSync = nil; current.teams?.lastSync = nil
        for field in fields {
            let before = field.items(old), after = field.items(current)
            for key in Set(before.keys).union(after.keys) {
                note(key, before: before[key], after: after[key])
            }
        }
        new.sync = ledger
    }

    /// `local` with `remote` merged in. Device settings (the app icon) stay local.
    static func merge(local: AppData, remote: AppData) -> AppData {
        var result = local
        var ledger = SyncLedger()
        ledger.tombstones = local.sync.tombstones.merging(remote.sync.tombstones, uniquingKeysWith: max)
        for field in fields {
            let mine = field.items(local), theirs = field.items(remote)
            var chosen: [String: Data] = [:]
            for key in Set(mine.keys).union(theirs.keys) {
                let localStamp = stamp(of: key, in: local.sync)
                let remoteStamp = stamp(of: key, in: remote.sync)
                let stamp = max(localStamp, remoteStamp)
                // A deletion newer than the last edit removes the item on both sides.
                if let deleted = ledger.tombstones[key], deleted >= stamp { continue }
                switch (mine[key], theirs[key]) {
                case let (m?, t?): chosen[key] = remoteStamp > localStamp ? t : m
                case let (m?, nil): chosen[key] = m
                case let (nil, t?): chosen[key] = t
                case (nil, nil): continue
                }
                if stamp > .distantPast { ledger.stamps[key] = stamp }
                ledger.tombstones[key] = nil
            }
            field.apply(chosen, &result)
        }
        result.dismissedImports = local.dismissedImports.union(remote.dismissedImports)
        result.preferences.appIcon = local.preferences.appIcon
        result.sync = ledger
        return result
    }

    /// When `key` last changed. Settings stamped before they were merged one by one
    /// carry the stamp of the whole "preferences" block.
    private static func stamp(of key: String, in ledger: SyncLedger) -> Date {
        ledger.stamps[key] ?? (key.hasPrefix("preferences.") ? ledger.stamps["preferences"] : nil) ?? .distantPast
    }

    // MARK: - The synced fields

    /// One synced part of `AppData`, as encoded items by key.
    private struct Field: Sendable {
        let items: @Sendable (AppData) -> [String: Data]
        let apply: @Sendable ([String: Data], inout AppData) -> Void
    }

    private static let fields: [Field] = [
        list("subjects", \.subjects), list("lessons", \.lessons), list("holidays", \.holidays),
        list("participation", \.participation), list("tasks", \.tasks), list("exams", \.exams),
        list("changes", \.changes), list("grades", \.grades),
        single("untis", \.untis), single("untisTimetable", \.untisTimetable),
        single("untisExtras", \.untisExtras), single("teams", \.teams),
        preferences,
    ]

    /// Every setting is its own item ("preferences.studentName", …), so a setting changed
    /// on one device doesn't overwrite a different one changed on another.
    private static let preferences = Field(
        items: { data in
            guard let encoded = try? encoder.encode(data.preferences),
                  let object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return [:] }
            return object.reduce(into: [:]) { items, entry in
                items["preferences.\(entry.key)"] = try? JSONSerialization.data(withJSONObject: entry.value, options: [.fragmentsAllowed, .sortedKeys])
            }
        },
        apply: { chosen, data in
            let object = chosen.reduce(into: [String: Any]()) { object, entry in
                object[String(entry.key.dropFirst("preferences.".count))] = try? JSONSerialization.jsonObject(with: entry.value, options: .fragmentsAllowed)
            }
            // Missing settings decode to their defaults.
            if let json = try? JSONSerialization.data(withJSONObject: object),
               let decoded = try? decoder.decode(Preferences.self, from: json) {
                data.preferences = decoded
            }
        }
    )

    private static func list<T: Codable & Identifiable>(_ name: String, _ path: WritableKeyPath<AppData, [T]> & Sendable) -> Field
    where T.ID == UUID {
        Field(
            items: { data in
                Dictionary(data[keyPath: path].compactMap { item in
                    (try? encoder.encode(item)).map { ("\(name):\(item.id.uuidString)", $0) }
                }, uniquingKeysWith: { first, _ in first })
            },
            apply: { chosen, data in
                // Keep the local order; items new from the other device go at the end.
                let decoded = chosen.compactMapValues { try? decoder.decode(T.self, from: $0) }
                var seen = Set<String>()
                var merged: [T] = data[keyPath: path].compactMap { item in
                    let key = "\(name):\(item.id.uuidString)"
                    seen.insert(key)
                    return decoded[key]
                }
                merged += decoded.filter { !seen.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value)
                data[keyPath: path] = merged
            }
        )
    }

    private static func single<T: Codable>(_ name: String, _ path: WritableKeyPath<AppData, T?> & Sendable) -> Field {
        Field(
            items: { data in
                guard let value = data[keyPath: path], let encoded = try? encoder.encode(value) else { return [:] }
                return [name: encoded]
            },
            apply: { chosen, data in
                data[keyPath: path] = chosen[name].flatMap { try? decoder.decode(T.self, from: $0) }
            }
        )
    }

    private static func single<T: Codable>(_ name: String, _ path: WritableKeyPath<AppData, T> & Sendable) -> Field {
        Field(
            items: { data in (try? encoder.encode(data[keyPath: path])).map { [name: $0] } ?? [:] },
            apply: { chosen, data in
                if let value = chosen[name].flatMap({ try? decoder.decode(T.self, from: $0) }) {
                    data[keyPath: path] = value
                }
            }
        )
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
