//
//  AmbientAudio.swift
//  Couche audio du jeu : ambiance d'exploration (drone "donjon"), musique
//  de combat avec crossfade, et pool de sons courts pour les événements.
//
//  Les fichiers principaux sont chargés depuis Audio/*.m4a (assets CC0 issus
//  d'OpenGameArt). Si un fichier manque ou refuse de se charger, on retombe
//  sur le synthétiseur procédural d'origine — pratique en dev quand on
//  manipule les assets.
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
final class AmbientAudio: ObservableObject {

    static let shared = AmbientAudio()

    // Clés UserDefaults pour les préférences persistées.
    private static let kAmbient = "tomb.audio.ambient"
    private static let kEffects = "tomb.audio.effects"

    /// Format commun utilisé pour la chaîne audio. Les fichiers sont ré-encodés
    /// en 44.1 kHz stéréo à l'import (`afconvert -d aac@44100 -c 2`), ce qui
    /// évite tout reformat coûteux à l'exécution.
    private static let mixFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100,
                                                  channels: 2)!

    /// Mapping event → nom de fichier audio (sans extension .m4a). Les events
    /// non listés ici retombent sur le synth procédural.
    private static let eventFileNames: [SoundEvent: String] = [
        .gainItem: "item_gem_02",
        .heal:     "spell_01",
        .hitDealt: "blade_01",
        // takeHit utilise un choc métallique plutôt qu'un cri de créature :
        // c'est le joueur qui prend, pas l'ennemi — sensation d'impact sur
        // l'armure plus juste qu'un grognement.
        .takeHit:  "metal_01",
        .enemyDie: "creature_die_01",
        .diceRoll: "item_wood_01",
        .lucky:    "item_coins_01",
        .unlucky:  "creature_misc_02",
        .pageTurn: "page_turn"
        // .victory et .death restent procéduraux : pas d'asset adapté.
    ]

    // MARK: - État runtime

    /// Drone d'ambiance ou musique de combat est-il joué en ce moment ?
    @Published private(set) var isPlaying = false

    /// Combat en cours : la musique de combat tourne et le drone est muet.
    @Published private(set) var isInBattle = false

    @Published var ambientEnabled: Bool {
        didSet {
            UserDefaults.standard.set(ambientEnabled, forKey: Self.kAmbient)
            if ambientEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    @Published var effectsEnabled: Bool {
        didSet { UserDefaults.standard.set(effectsEnabled, forKey: Self.kEffects) }
    }

    // MARK: - Engine + nodes

    private let engine = AVAudioEngine()

    /// Player du drone d'ambiance (exploration).
    private let ambientPlayer = AVAudioPlayerNode()
    /// Player de la musique de combat.
    private let battlePlayer = AVAudioPlayerNode()

    private var ambientBuffer: AVAudioPCMBuffer?
    private var battleBuffer: AVAudioPCMBuffer?

    /// Volume cible du drone hors combat.
    private let ambientTargetVolume: Float = 0.32
    /// Volume cible de la musique de combat.
    private let battleTargetVolume: Float = 0.45

    /// Pool d'event players (3 nodes round-robin pour superposer les FX).
    private var eventPlayers: [AVAudioPlayerNode] = []
    private var eventCursor: Int = 0
    private var eventBuffers: [SoundEvent: AVAudioPCMBuffer] = [:]

    /// Task en cours de crossfade : annulée si un autre crossfade démarre.
    private var crossfadeTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        // Charger les préférences persistées avant tout (default true).
        let defs = UserDefaults.standard
        self.ambientEnabled = (defs.object(forKey: Self.kAmbient) as? Bool) ?? true
        self.effectsEnabled = (defs.object(forKey: Self.kEffects) as? Bool) ?? true

        // Buffers principaux : fichiers si dispo, fallback synth sinon.
        ambientBuffer = Self.loadBundleBuffer("dungeon_ambient")
            ?? Self.makeProceduralDrone(format: Self.mixFormat, seconds: 8)
        battleBuffer  = Self.loadBundleBuffer("combat_music")

        // Players musique
        engine.attach(ambientPlayer)
        engine.connect(ambientPlayer, to: engine.mainMixerNode, format: Self.mixFormat)
        ambientPlayer.volume = 0

        engine.attach(battlePlayer)
        engine.connect(battlePlayer, to: engine.mainMixerNode, format: Self.mixFormat)
        battlePlayer.volume = 0

        // Pool d'event players
        for _ in 0..<3 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: Self.mixFormat)
            p.volume = 0.8
            eventPlayers.append(p)
        }

        // Buffers d'event : fichiers si mappé + chargeable, fallback synth.
        for event in SoundEvent.allCases {
            if let name = Self.eventFileNames[event],
               let buf = Self.loadBundleBuffer(name) {
                eventBuffers[event] = buf
            } else {
                eventBuffers[event] = SoundSynth.buffer(for: event, format: Self.mixFormat)
            }
        }

        configureAudioSession()
    }

    // MARK: - Public — ambient/combat

    func start() {
        guard !isPlaying, ambientEnabled, let buffer = ambientBuffer else { return }
        do {
            if !engine.isRunning { try engine.start() }
            ambientPlayer.scheduleBuffer(buffer, at: nil, options: [.loops])
            ambientPlayer.play()
            // Volume cible direct (pas de fade-in à l'allumage du jeu).
            ambientPlayer.volume = ambientTargetVolume
            battlePlayer.volume = 0
            isPlaying = true
            isInBattle = false
        } catch {
            print("[AmbientAudio] start failed: \(error)")
        }
    }

    func stop() {
        guard isPlaying else { return }
        crossfadeTask?.cancel()
        ambientPlayer.stop()
        battlePlayer.stop()
        for p in eventPlayers { p.stop() }
        engine.pause()
        isPlaying = false
        isInBattle = false
    }

    /// Bouton "muet" du HUD : coupe ou réactive **tout** d'un coup (ambiance,
    /// musique de combat et effets — page qui tourne, dés, etc.). Les deux
    /// préférences restent dissociables individuellement depuis l'écran de
    /// Réglages ; ce bouton-là sert juste à zapper l'audio en bloc.
    func toggle() {
        let newValue = !(ambientEnabled || effectsEnabled)
        ambientEnabled = newValue
        effectsEnabled = newValue
    }

    /// Entre en "mode combat" : crossfade ambient → musique de combat.
    /// Idempotent : un second appel pendant un crossfade en cours est ignoré.
    func enterBattle() {
        guard ambientEnabled, isPlaying, !isInBattle else { return }
        guard let buffer = battleBuffer else { return }
        isInBattle = true

        battlePlayer.scheduleBuffer(buffer, at: nil, options: [.loops])
        battlePlayer.play()

        crossfadeTask?.cancel()
        crossfadeTask = Task { @MainActor in
            async let down: Void = Self.rampVolume(self.ambientPlayer, to: 0, over: 0.6)
            async let up:   Void = Self.rampVolume(self.battlePlayer, to: self.battleTargetVolume, over: 0.6)
            _ = await (down, up)
        }
    }

    /// Sort du mode combat : crossfade combat → ambient.
    func exitBattle() {
        guard isInBattle else { return }
        isInBattle = false

        crossfadeTask?.cancel()
        crossfadeTask = Task { @MainActor in
            async let down: Void = Self.rampVolume(self.battlePlayer, to: 0, over: 0.8)
            async let up:   Void = Self.rampVolume(self.ambientPlayer, to: self.ambientTargetVolume, over: 0.8)
            _ = await (down, up)
            self.battlePlayer.stop()
        }
    }

    // MARK: - Public — events

    func play(_ event: SoundEvent) {
        guard effectsEnabled, let buffer = eventBuffers[event] else { return }
        let player = eventPlayers[eventCursor]
        eventCursor = (eventCursor + 1) % eventPlayers.count

        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        if !player.isPlaying { player.play() }
    }

    // MARK: - Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[AmbientAudio] session error: \(error)")
        }
    }

    // MARK: - File loading

    /// Charge un fichier `<name>.m4a` du bundle en buffer PCM. Retourne nil
    /// si absent ou non lisible.
    private static func loadBundleBuffer(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            return nil
        }
        guard let file = try? AVAudioFile(forReading: url) else {
            print("[AmbientAudio] failed to open \(name).m4a")
            return nil
        }
        let length = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: length) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            print("[AmbientAudio] failed to read \(name).m4a: \(error)")
            return nil
        }
        // Si le fichier n'est pas déjà au format de mix, on le convertit.
        // Tous nos assets sont déjà en 44.1k stéréo donc cette branche ne
        // devrait pas se déclencher en pratique — mais robustesse.
        if buffer.format == mixFormat {
            return buffer
        }
        return convert(buffer: buffer, to: mixFormat)
    }

    private static func convert(buffer: AVAudioPCMBuffer,
                                 to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: target) else {
            return nil
        }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let dest = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }
        var done = false
        var error: NSError?
        _ = converter.convert(to: dest, error: &error) { _, status in
            if done {
                status.pointee = .endOfStream
                return nil
            }
            done = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return nil }
        return dest
    }

    // MARK: - Volume helpers

    /// Rampe linéaire du volume d'un player vers `target` sur `over` secondes.
    /// Implémentée en pas de 25 ms pour rester smooth sans saturer la main
    /// queue. Annulable via la Task englobante.
    private static func rampVolume(_ player: AVAudioPlayerNode,
                                    to target: Float,
                                    over duration: TimeInterval) async {
        let stepMs = 25
        let steps = max(1, Int(duration * 1000) / stepMs)
        let start = player.volume
        let delta = (target - start) / Float(steps)

        for i in 1...steps {
            try? await Task.sleep(for: .milliseconds(stepMs))
            if Task.isCancelled { return }
            player.volume = start + delta * Float(i)
        }
    }

    // MARK: - Drone synthétique de fallback

    /// Identique à l'ancienne implémentation : utilisé seulement si
    /// `dungeon_ambient.m4a` n'est pas embarqué dans le bundle.
    private static func makeProceduralDrone(format: AVAudioFormat,
                                             seconds: Double) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = Int(sampleRate * seconds)
        let warmupFrames = Int(sampleRate * 0.5)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else { return nil }

        let twoPi = 2.0 * Double.pi

        let fSub:  Double = 110.0
        let fMid:  Double = 165.0
        let fHigh: Double = 220.0

        let lfoMid:  Double = 0.5
        let lfoHigh: Double = 0.375

        let lpfAlpha = 0.06
        var nLowL: Double = 0
        var nLowR: Double = 0

        for _ in 0..<warmupFrames {
            let nL = Double.random(in: -1...1)
            let nR = Double.random(in: -1...1)
            nLowL += lpfAlpha * (nL - nLowL)
            nLowR += lpfAlpha * (nR - nLowR)
        }

        let crossfadeFrames = Int(sampleRate * 0.1)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate

            let envMid  = 0.5 + 0.5 * sin(twoPi * lfoMid  * t)
            let envHigh = 0.5 + 0.5 * sin(twoPi * lfoHigh * t)

            let sub  = sin(twoPi * fSub  * t) * 0.18
            let mid  = sin(twoPi * fMid  * t) * 0.10 * envMid
            let high = sin(twoPi * fHigh * t) * 0.05 * envHigh

            let drone = sub + mid + high

            let nL = Double.random(in: -1...1)
            let nR = Double.random(in: -1...1)
            nLowL += lpfAlpha * (nL - nLowL)
            nLowR += lpfAlpha * (nR - nLowR)

            let noiseGain = 0.28
            var noiseL = nLowL * noiseGain
            var noiseR = nLowR * noiseGain

            if i < crossfadeFrames {
                let alpha = Double(i) / Double(crossfadeFrames)
                noiseL *= alpha
                noiseR *= alpha
            }

            left[i]  = Float(tanh((drone + noiseL) * 0.8))
            right[i] = Float(tanh((drone + noiseR) * 0.8))
        }

        return buffer
    }
}
