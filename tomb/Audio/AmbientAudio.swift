@preconcurrency import AVFoundation
import Combine
import SwiftUI

@MainActor
final class AmbientAudio: ObservableObject {
    static let shared = AmbientAudio()

    private static let kAmbient = "tomb.audio.ambient"
    private static let kEffects = "tomb.audio.effects"
    private static let kAmbientVolume = "tomb.audio.ambient_vol"
    private static let kEffectsVolume = "tomb.audio.effects_vol"

    private static let mixFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100,
                                                  channels: 2)!

    private static let eventFileNames: [SoundEvent: String] = [
        .gainItem: "item_gem_02",
        .hitDealt: "blade_01",
        .takeHit:  "metal_01",
        .enemyDie: "creature_die_01",
        .diceRoll: "item_wood_01",
        .lucky:    "item_coins_01",
        .unlucky:  "creature_misc_02",
        .pageTurn: "page_turn"
    ]

    // MARK: - État runtime

    @Published private(set) var isPlaying = false

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

    @Published var ambientVolume: Float {
        didSet {
            UserDefaults.standard.set(ambientVolume, forKey: Self.kAmbientVolume)
            applyAmbientVolume()
        }
    }

    @Published var effectsVolume: Float {
        didSet { UserDefaults.standard.set(effectsVolume, forKey: Self.kEffectsVolume) }
    }

    // MARK: - Musiques (streaming disque)

    private var ambientPlayer: AVAudioPlayer?
    private var battlePlayer: AVAudioPlayer?

    private let ambientTargetVolume: Float = 0.32
    private let battleTargetVolume: Float = 0.45

    private var crossfadeTask: Task<Void, Never>?

    // MARK: - Effets courts (engine + pool)

    private let engine = AVAudioEngine()

    private var eventPlayers: [AVAudioPlayerNode] = []
    private var eventCursor: Int = 0
    private var eventBuffers: [SoundEvent: AVAudioPCMBuffer] = [:]

    // MARK: - Init

    private init() {
        let defs = UserDefaults.standard
        self.ambientEnabled = (defs.object(forKey: Self.kAmbient) as? Bool) ?? true
        self.effectsEnabled = (defs.object(forKey: Self.kEffects) as? Bool) ?? true
        self.ambientVolume = (defs.object(forKey: Self.kAmbientVolume) as? Float) ?? 1.0
        self.effectsVolume = (defs.object(forKey: Self.kEffectsVolume) as? Float) ?? 1.0

        ambientPlayer = Self.makeLoopingPlayer(named: "dungeon_ambient")
            ?? Self.makeProceduralDronePlayer()
        battlePlayer = Self.makeLoopingPlayer(named: "combat_music")

        for _ in 0..<3 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: Self.mixFormat)
            p.volume = 0.8
            eventPlayers.append(p)
        }

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
        guard !isPlaying, ambientEnabled, let ambient = ambientPlayer else { return }
        ambient.volume = ambientTargetVolume * chapterBias * ambientVolume
        ambient.play()
        battlePlayer?.volume = 0
        isPlaying = true
        isInBattle = false
    }

    private func applyAmbientVolume() {
        if isInBattle {
            battlePlayer?.volume = currentBattleVolume * ambientVolume
        } else if isPlaying {
            ambientPlayer?.volume = ambientTargetVolume * chapterBias * ambientVolume
        }
    }

    private var chapterBias: Float = 1.0

    func setChapterAmbience(_ chapter: Chapter) {
        let newBias: Float
        switch chapter {
        case .village:    newBias = 0.55
        case .forest:     newBias = 0.85
        case .marsh:      newBias = 1.05
        case .ruins:      newBias = 0.95
        case .tomb:       newBias = 1.20
        case .chamber:    newBias = 1.10
        case .homecoming: newBias = 0.60
        case .ending:     newBias = 0.50
        }
        guard abs(newBias - chapterBias) > 0.001 else { return }
        chapterBias = newBias
        guard isPlaying, !isInBattle else { return }
        ambientPlayer?.setVolume(ambientTargetVolume * chapterBias * ambientVolume,
                                 fadeDuration: 1.2)
    }

    private var battleIntensityBoost: Float = 1.0

    private var currentBattleVolume: Float {
        battleTargetVolume * battleIntensityBoost
    }

    func setBattleIntensity(enemyHpRatio: Double) {
        let newBoost: Float = enemyHpRatio < 0.30 ? 1.15 : 1.0
        guard newBoost != battleIntensityBoost else { return }
        battleIntensityBoost = newBoost
        if isInBattle {
            battlePlayer?.setVolume(currentBattleVolume * ambientVolume,
                                    fadeDuration: 0.6)
        }
    }

    func stop() {
        guard isPlaying else { return }
        crossfadeTask?.cancel()
        ambientPlayer?.stop()
        battlePlayer?.stop()
        for p in eventPlayers { p.stop() }
        engine.pause()
        isPlaying = false
        isInBattle = false
    }

    func toggle() {
        let newValue = !(ambientEnabled || effectsEnabled)
        ambientEnabled = newValue
        effectsEnabled = newValue
    }

    func enterBattle() {
        guard ambientEnabled, isPlaying, !isInBattle else { return }
        guard let battle = battlePlayer else { return }
        isInBattle = true

        crossfadeTask?.cancel()
        battle.currentTime = 0
        battle.volume = battleTargetVolume * ambientVolume
        battle.play()

        ambientPlayer?.setVolume(0, fadeDuration: 0.2)
    }

    func exitBattle() {
        guard isInBattle else { return }
        isInBattle = false
        battleIntensityBoost = 1.0

        battlePlayer?.setVolume(0, fadeDuration: 0.8)
        ambientPlayer?.setVolume(ambientTargetVolume * chapterBias * ambientVolume,
                                 fadeDuration: 0.8)

        crossfadeTask?.cancel()
        crossfadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, !self.isInBattle else { return }
            self.battlePlayer?.stop()
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
        player.volume = effectsVolume
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
            #if DEBUG
            print("[AmbientAudio] session error: \(error)")
            #endif
        }
    }

    // MARK: - Chargement des musiques

    private static func makeLoopingPlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            return player
        } catch {
            #if DEBUG
            print("[AmbientAudio] failed to open \(name).m4a: \(error)")
            #endif
            return nil
        }
    }

    private static func makeProceduralDronePlayer() -> AVAudioPlayer? {
        guard let buffer = makeProceduralDrone(format: mixFormat, seconds: 8) else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tomb_procedural_drone.caf")
        do {
            let file = try AVAudioFile(forWriting: url,
                                       settings: buffer.format.settings)
            try file.write(from: buffer)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            return player
        } catch {
            #if DEBUG
            print("[AmbientAudio] procedural drone fallback failed: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Chargement des effets courts

    private static func loadBundleBuffer(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            return nil
        }
        guard let file = try? AVAudioFile(forReading: url) else {
            #if DEBUG
            print("[AmbientAudio] failed to open \(name).m4a")
            #endif
            return nil
        }
        let length = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: length) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            #if DEBUG
            print("[AmbientAudio] failed to read \(name).m4a: \(error)")
            #endif
            return nil
        }
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

    // MARK: - Drone synthétique de fallback

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
