// SPDX-License-Identifier: GPL-2.0-or-later
// Alvarocrack's fork: the refresh rate games on the translation layer see (Automatic, 60 Hz or 120 Hz), per game or for all,
// the Unity frame-rate unlock, and the app's language (English or Spanish).
import SwiftUI
import UIKit

/// The refresh rate the translation layer tells a game the screen has. Husk upstream always said 60 Hz.
enum HuskFrameRate: Int, CaseIterable, Identifiable, Codable {
    /// The screen's own: 120 Hz on a ProMotion iPhone or iPad, 60 Hz on the rest.
    case auto = 0
    case hz60 = 60
    case hz120 = 120

    static let key = "husk.frameRate"
    static let unlockKey = "husk.unlockUnityFPS"

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .auto: return "Automatic"
        case .hz60: return "60 Hz"
        case .hz120: return "120 Hz"
        }
    }

    /// For every game, unless a game's own settings say otherwise.
    static var global: HuskFrameRate {
        HuskFrameRate(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .auto
    }

    static var unlockUnity: Bool {
        UserDefaults.standard.object(forKey: unlockKey) as? Bool ?? true
    }

    /// The game about to run (or running): its own choice, or nil to follow `global`. Set by the game's screen as it opens.
    static var gameOverride: HuskFrameRate?

    static var current: HuskFrameRate { gameOverride ?? global }

    /// The fastest this screen goes.
    @MainActor static var screenMaxHz: Int { max(60, UIScreen.main.maximumFramesPerSecond) }

    /// The rate that will really be used.
    @MainActor static var effectiveHz: Int {
        switch current {
        case .auto: return screenMaxHz >= 120 ? 120 : 60
        case .hz60: return 60
        case .hz120: return min(120, screenMaxHz)
        }
    }

    /// Before a game starts: tells the translation layer.
    @MainActor static func apply() {
        let hz = effectiveHz
        husk_set_refresh_rate(Int32(hz), unlockUnity ? 1 : 0)
        HuskLog.log("tl", "refresh: \(current) (\(gameOverride == nil ? "global" : "this game")) -> \(hz) Hz, screen \(screenMaxHz) Hz, "
                        + "Unity unlock \(unlockUnity ? "on" : "off")")
    }
}

/// A game's own choice in its settings: the global one, or a rate of its own.
enum GameFrameRate: String, Codable, CaseIterable, Identifiable {
    case `default`, auto, hz60, hz120
    var id: String { rawValue }
    var choice: HuskFrameRate? {
        switch self {
        case .default: return nil
        case .auto: return .auto
        case .hz60: return .hz60
        case .hz120: return .hz120
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .default: return "Default"
        case .auto: return "Automatic"
        case .hz60: return "60 Hz"
        case .hz120: return "120 Hz"
        }
    }
}

/// Asks iOS to keep the screen at the chosen rate while a game is showing. The game presents into a CAMetalLayer on its own
/// (through ANGLE); without this ProMotion can stay at 60 however fast the game draws.
final class FrameRateHint: NSObject {
    private var link: CADisplayLink?

    func start(hz: Int) {
        stop()
        guard hz > 60 else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        let f = Float(hz)
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: f, preferred: f)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ l: CADisplayLink) {}

    deinit { link?.invalidate() }
}

/// Settings › Frame Rate: the rate for every game on the translation layer.
struct FrameRateSettings: View {
    @AppStorage(HuskFrameRate.key) private var rate = HuskFrameRate.auto.rawValue
    @AppStorage(HuskFrameRate.unlockKey) private var unlock = true

    var body: some View {
        HuskForm {
            Section {
                Picker("Refresh Rate", selection: $rate) {
                    ForEach(HuskFrameRate.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                LabeledContent("This screen", value: "\(HuskFrameRate.screenMaxHz) Hz")
            } header: {
                Text("Refresh Rate")
            } footer: {
                Text("What Android games on the translation layer are told the screen runs at. Automatic is 120 Hz on a ProMotion screen and 60 Hz on the rest. At 120 Hz games are smoother but use more battery and run warmer. Each game can change it in its own settings. Applies the next time a game starts.")
            }
            Section {
                Toggle("Unlock Unity Frame Rate", isOn: $unlock)
            } footer: {
                Text("Unity games choose their own frame limit, often 30 or 60. With this on, the limit is raised to the refresh rate, like an FPS unlocker on Android. Only above 60 Hz.")
            }
        }
        .navigationTitle("Frame Rate")
    }
}

/// The app's language. Husk's screens follow it from the next launch, as do the apps in it (iOS's per-app language).
enum HuskLanguage: String, CaseIterable, Identifiable {
    case system, en, es
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    static var current: HuskLanguage {
        guard let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              UserDefaults.standard.object(forKey: "husk.languageChosen") != nil, let first = langs.first else { return .system }
        if first.hasPrefix("es") { return .es }
        if first.hasPrefix("en") { return .en }
        return .system
    }

    func apply() {
        let d = UserDefaults.standard
        switch self {
        case .system:
            d.removeObject(forKey: "AppleLanguages")
            d.removeObject(forKey: "husk.languageChosen")
        case .en, .es:
            d.set([rawValue], forKey: "AppleLanguages")
            d.set(true, forKey: "husk.languageChosen")
            d.set(rawValue, forKey: Onboarding.languageKey)
        }
    }
}

/// Settings › Language.
struct LanguageSettings: View {
    @State private var language = HuskLanguage.current
    @State private var changed = false

    var body: some View {
        HuskForm {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(HuskLanguage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: language) { v in
                    v.apply()
                    changed = true
                    HuskLog.log("ui", "language: \(v.rawValue)")
                }
            } footer: {
                Text("Husk and the apps in it use this language from the next time Husk opens.")
            }
            if changed {
                Section {
                    Button("Close Husk Now") { exit(0) }
                } footer: {
                    Text("Open Husk again to see it in the new language.")
                }
            }
        }
        .navigationTitle("Language")
    }
}
