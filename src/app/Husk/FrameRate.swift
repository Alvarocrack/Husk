// SPDX-License-Identifier: GPL-2.0-or-later
// Fork de Alvarocrack: tasa de refresco de los juegos (Automático, 60 Hz o 120 Hz) y desbloqueo de FPS de Unity.
import SwiftUI
import UIKit

/// La tasa de refresco que se le anuncia a los juegos de la capa de traducción. El Husk original siempre decía 60 Hz.
enum HuskFrameRate: Int, CaseIterable, Identifiable {
    /// La de la pantalla: 120 Hz en un iPhone o iPad con ProMotion, 60 Hz en los demás.
    case auto = 0
    case hz60 = 60
    case hz120 = 120

    static let key = "husk.frameRate"
    static let unlockKey = "husk.unlockUnityFPS"

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automático"
        case .hz60: return "60 Hz"
        case .hz120: return "120 Hz"
        }
    }

    static var current: HuskFrameRate {
        HuskFrameRate(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .auto
    }

    static var unlockUnity: Bool {
        UserDefaults.standard.object(forKey: unlockKey) as? Bool ?? true
    }

    /// Lo más rápido que puede ir esta pantalla.
    @MainActor static var screenMaxHz: Int { max(60, UIScreen.main.maximumFramesPerSecond) }

    /// Los Hz que se usarán de verdad con el ajuste actual.
    @MainActor static var effectiveHz: Int {
        switch current {
        case .auto: return screenMaxHz >= 120 ? 120 : 60
        case .hz60: return 60
        case .hz120: return min(120, screenMaxHz)
        }
    }

    /// Antes de arrancar un juego: se lo dice a la capa de traducción.
    @MainActor static func apply() {
        let hz = effectiveHz
        husk_set_refresh_rate(Int32(hz), unlockUnity ? 1 : 0)
        HuskLog.log("tl", "refresh: \(current.title) → \(hz) Hz (pantalla: \(screenMaxHz) Hz), Unity \(unlockUnity ? "desbloqueado" : "sin tocar")")
    }
}

/// Le pide a iOS que la pantalla vaya a la tasa elegida mientras el juego está en pantalla. El juego presenta sus frames en un
/// CAMetalLayer por su cuenta (ANGLE); sin esto, ProMotion puede quedarse a 60 aunque el juego produzca más.
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

/// La sección de Ajustes › Rendimiento.
struct FrameRateSection: View {
    @AppStorage(HuskFrameRate.key) private var rate = HuskFrameRate.auto.rawValue
    @AppStorage(HuskFrameRate.unlockKey) private var unlock = true

    var body: some View {
        Section {
            Picker("Tasa de refresco", selection: $rate) {
                ForEach(HuskFrameRate.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $unlock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Desbloquear FPS en Unity")
                    Text("Fuerza el límite de FPS del juego a la tasa elegida").font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Pantalla", value: "\(HuskFrameRate.screenMaxHz) Hz máx.")
        } header: {
            Text("Tasa de refresco")
        } footer: {
            Text("Automático usa 120 Hz en pantallas ProMotion y 60 Hz en las demás. A 120 Hz los juegos van más fluidos pero "
               + "gastan más batería y calientan más. Se aplica al abrir un juego. Si alguno va mal, ponlo en 60 Hz.")
        }
    }
}
