@preconcurrency import AVFoundation
import Foundation

nonisolated enum SoundEvent: CaseIterable {
    case gainItem
    case heal
    case hitDealt
    case takeHit
    case enemyDie
    case diceRoll
    case lucky
    case unlucky
    case victory
    case death
    case pageTurn
    case buttonTap
    case chapterStinger
    case epitaph
}

nonisolated enum SoundSynth {
    static func buffer(for event: SoundEvent,
                       format: AVAudioFormat) -> AVAudioPCMBuffer? {
        switch event {
        case .gainItem: return gainItem(format: format)
        case .heal:     return heal(format: format)
        case .hitDealt: return hitDealt(format: format)
        case .takeHit:  return takeHit(format: format)
        case .enemyDie: return enemyDie(format: format)
        case .diceRoll: return diceRoll(format: format)
        case .lucky:    return lucky(format: format)
        case .unlucky:  return unlucky(format: format)
        case .victory:  return victory(format: format)
        case .death:    return death(format: format)
        case .pageTurn: return pageTurn(format: format)
        case .buttonTap: return buttonTap(format: format)
        case .chapterStinger: return chapterStinger(format: format)
        case .epitaph: return epitaph(format: format)
        }
    }

    // MARK: - Implémentations par événement

    private static func gainItem(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.45) { t in
            let n1 = noteEnv(t: t, start: 0.00, attack: 0.005, decay: 0.25)
            let n2 = noteEnv(t: t, start: 0.10, attack: 0.005, decay: 0.30)
            let s1 = sine(1318.0, t) * 0.30 * n1
            let s2 = sine(1760.0, t) * 0.32 * n2
            let h  = sine(2637.0, t) * 0.08 * n2
            return (s1 + s2 + h)
        }
    }

    private static func heal(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.95) { t in
            let envRoot   = noteEnv(t: t, start: 0.00, attack: 0.18, decay: 0.65)
            let envFifth  = noteEnv(t: t, start: 0.05, attack: 0.20, decay: 0.60)
            let envShine  = noteEnv(t: t, start: 0.30, attack: 0.12, decay: 0.35)
            let root  = sine(261.6, t) * 0.22 * envRoot
            let fifth = sine(392.0, t) * 0.18 * envFifth
            let shine = sine(1046.5, t) * 0.06 * envShine
            let breath = Double.random(in: -1...1) * 0.03 * exp(-t * 6)
            return root + fifth + shine + breath
        }
    }

    private static func hitDealt(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.20) { t in
            let env = exp(-t * 24)
            let metal  = sine(1100.0, t) * 0.32 * env
            let bright = sine(2200.0, t) * 0.18 * env
            let click  = Double.random(in: -1...1) * 0.22 * exp(-t * 80)
            return metal + bright + click
        }
    }

    private static func takeHit(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.32) { t in
            let env = exp(-t * 14)
            let sub  = sine(70.0,  t) * 0.55 * env
            let mid  = sine(160.0, t) * 0.22 * env
            let noise = Double.random(in: -1...1) * 0.32 * env
            return sub + mid + noise
        }
    }

    private static func diceRoll(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.12) { t in
            let env = exp(-t * 60)
            let click = Double.random(in: -1...1) * 0.55 * env
            let body = sine(450.0, t) * 0.25 * exp(-t * 35)
            return click + body
        }
    }

    private static func lucky(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.55) { t in
            let n1 = noteEnv(t: t, start: 0.00, attack: 0.004, decay: 0.20)
            let n2 = noteEnv(t: t, start: 0.13, attack: 0.004, decay: 0.40)
            return sine(1568.0, t) * 0.28 * n1 + sine(2349.0, t) * 0.30 * n2
        }
    }

    private static func unlucky(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.55) { t in
            let env = exp(-t * 4)
            let freq = 392.0 - 130.0 * min(t / 0.4, 1.0)
            let body = sine(freq, t) * 0.30 * env
            let noise = Double.random(in: -1...1) * 0.05 * env
            return body + noise
        }
    }

    private static func victory(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 1.4) { t in
            let n1 = noteEnv(t: t, start: 0.00, attack: 0.01, decay: 0.50)
            let n2 = noteEnv(t: t, start: 0.18, attack: 0.01, decay: 0.55)
            let n3 = noteEnv(t: t, start: 0.36, attack: 0.01, decay: 0.60)
            let n4 = noteEnv(t: t, start: 0.55, attack: 0.01, decay: 0.85)
            let s1 = sine(523.25, t) * 0.28 * n1
            let s2 = sine(659.25, t) * 0.28 * n2
            let s3 = sine(783.99, t) * 0.28 * n3
            let s4 = (sine(1046.5, t) + sine(2093.0, t) * 0.4) * 0.28 * n4
            return s1 + s2 + s3 + s4
        }
    }

    private static func enemyDie(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.7) { t in
            let env = exp(-t * 3.5)
            let freq = 220.0 - 80.0 * min(t / 0.5, 1.0)
            let body = sine(freq, t) * 0.45 * env
            let noise = Double.random(in: -1...1) * 0.10 * env
            return body + noise
        }
    }

    private static func pageTurn(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.35) { t in
            let env = exp(-t * 6) * (1 - exp(-t * 60))
            let noise = Double.random(in: -1...1)
            return noise * 0.28 * env
        }
    }

    private static func buttonTap(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 0.13) { t in
            let env = exp(-t * 20)
            let click = Double.random(in: -1...1) * 0.06 * env
            let tone  = sine(350.0, t) * 0.18 * env
            let sub   = sine(175.0, t) * 0.12 * env
            return click + tone + sub
        }
    }

    private static func death(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 2.0) { t in
            let env = exp(-t * 1.4)
            let fundamental = sine(110.0, t) * 0.45 * env
            let octave      = sine(220.0, t) * 0.15 * env
            let sub         = sine(55.0,  t) * 0.30 * env
            let noise       = Double.random(in: -1...1) * 0.04 * env
            return fundamental + octave + sub + noise
        }
    }

    private static func chapterStinger(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 2.2) { t in
            let n1 = noteEnv(t: t, start: 0.00, attack: 0.05, decay: 1.40)
            let n2 = noteEnv(t: t, start: 0.30, attack: 0.05, decay: 1.30)
            let n3 = noteEnv(t: t, start: 0.62, attack: 0.05, decay: 1.50)
            let s1 = (sine(146.83, t) + sine(293.66, t) * 0.35) * 0.22 * n1
            let s2 = (sine(174.61, t) + sine(349.23, t) * 0.30) * 0.20 * n2
            let s3 = (sine(220.00, t) + sine(440.00, t) * 0.40
                     + sine(880.00, t) * 0.15) * 0.22 * n3
            let air = Double.random(in: -1...1) * 0.015 * exp(-abs(t - 0.6) * 1.2)
            return s1 + s2 + s3 + air
        }
    }

    private static func epitaph(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        return synth(format: format, durationS: 3.2) { t in
            let env = exp(-t * 0.9)
            let strike = exp(-t * 30) * 0.8
            let fundamental = sine(98.0, t) * 0.40 * env
            let third       = sine(123.47, t) * 0.20 * env
            let fifth       = sine(146.83, t) * 0.25 * env
            let octave      = sine(196.0, t) * 0.10 * env
            let sub         = sine(49.0, t) * 0.35 * env
            let noise       = Double.random(in: -1...1) * 0.04 * env
            return (fundamental + third + fifth + octave + sub) * (1 + strike) + noise
        }
    }

    // MARK: - Helpers

    private static func noteEnv(t: Double, start: Double,
                                 attack: Double, decay: Double) -> Double {
        let local = t - start
        guard local >= 0 else { return 0 }
        let attackPart = min(local / max(attack, 0.001), 1.0)
        let releaseT = max(0, local - attack)
        let releasePart = exp(-releaseT / max(decay, 0.001))
        return attackPart * releasePart
    }

    private static func sine(_ f: Double, _ t: Double) -> Double {
        sin(2.0 * .pi * f * t)
    }

    private static func synth(format: AVAudioFormat,
                               durationS: Double,
                               generator: (Double) -> Double) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = Int(sampleRate * durationS)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else { return nil }

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let sample = tanh(generator(t) * 0.9)
            left[i] = Float(sample)
            right[i] = Float(sample)
        }
        return buffer
    }
}
