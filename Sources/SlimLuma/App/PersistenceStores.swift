import Foundation
import SlimLumaKit

enum SettingsStore {
    private static let key = "compression-settings-v1"

    static func load() -> CompressionSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              var settings = try? JSONDecoder().decode(CompressionSettings.self, from: data) else {
            return .default
        }
        // Interactive PDF structure is a safety invariant. Older builds exposed
        // this as an opt-out even though dropping forms or links was not verified.
        settings.pdf.preserveForms = true
        // Older builds presented quality 100 as "lossless" for formats whose
        // encoders still change pixels. Keep those saved settings honest.
        switch settings.image.format {
        case .jpeg, .avif, .heic:
            settings.image.lossless = false
        case .keep, .png, .webp:
            break
        }
        return settings
    }

    static func save(_ settings: CompressionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum PresetStore {
    private static let key = "custom-presets-v1"

    static func load() -> [CompressionPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([CompressionPreset].self, from: data) else {
            return []
        }
        return presets
    }

    static func save(_ presets: [CompressionPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum AutomationSettingsStore {
    private static let key = "automation-settings-v1"

    static func load() -> AutomationSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(
                  AutomationSettings.self,
                  from: data
              ) else {
            return AutomationSettings()
        }
        return settings
    }

    static func save(_ settings: AutomationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum HistoryStore {
    private static var fileURL: URL? {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return directory
            .appendingPathComponent("SlimLuma", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    static func load() -> [HistoryEntry] {
        guard let fileURL else { return [] }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fileURL.deletingLastPathComponent().path
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    static func save(_ history: [HistoryEntry]) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: fileURL.deletingLastPathComponent().path
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Array(history.prefix(500)))
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // History is supplementary; a write failure must not fail compression.
        }
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
