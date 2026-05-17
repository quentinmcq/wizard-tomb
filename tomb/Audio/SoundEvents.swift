//
//  SoundEvents.swift
//  Sons d'événement courts générés procéduralement (sinus + bruit + ADSR),
//  joués en plus du drone d'ambiance. Aucun fichier audio requis.
//

import AVFoundation
import Foundation

enum SoundEvent: CaseIterable {
    case gainItem      // obtention d'un objet : carillon cristallin
    case heal          // soin, bénédiction : 2 notes ascendantes douces
    case hitDealt      // tu portes un coup : claquement métallique aigu
    case takeHit       // tu en encaisses un : choc grave dans la chair
    case enemyDie      // l'ennemi s'effondre : râle final
    case diceRoll      // lancement de dés : "tac" rapide
    case lucky         // jet de chance réussi : 2-note carillon
    case unlucky       // jet de chance raté : note descendante grave
    case victory       // fin d'aventure victorieuse : arpège ascendant
    case death         // fin d'aventure mort : note grave qui s'évanouit
    case pageTurn      // bruissement de page tournée (entre passages)
    case buttonTap     // clic UI sec sur un bouton (hors choix d'histoire)
}

enum SoundSynth {

    /// Construit le buffer pour un événement. La forme/durée/timbre sont
    /// tunées par cas.
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
        }
    }

    // MARK: - Implémentations par événement

    private static func gainItem(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Deux notes brillantes (E6, A6), decay rapide → "ding-ding" cristallin.
        return synth(format: format, durationS: 0.45) { t in
            let n1 = noteEnv(t: t, start: 0.00, attack: 0.005, decay: 0.25)
            let n2 = noteEnv(t: t, start: 0.10, attack: 0.005, decay: 0.30)
            let s1 = sine(1318.0, t) * 0.30 * n1
            let s2 = sine(1760.0, t) * 0.32 * n2
            // Harmoniques discrètes pour donner du grain.
            let h  = sine(2637.0, t) * 0.08 * n2
            return (s1 + s2 + h)
        }
    }

    private static func heal(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Deux notes ascendantes douces (G5, C6), attack plus lent.
        return synth(format: format, durationS: 0.55) { t in
            let n1 = noteEnv(t: t, start: 0.00, attack: 0.05, decay: 0.40)
            let n2 = noteEnv(t: t, start: 0.18, attack: 0.05, decay: 0.40)
            let s1 = sine(784.0,  t) * 0.32 * n1
            let s2 = sine(1046.5, t) * 0.32 * n2
            return s1 + s2
        }
    }

    private static func hitDealt(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Claquement de lame aigu et court : tu portes le coup.
        return synth(format: format, durationS: 0.20) { t in
            let env = exp(-t * 24)
            let metal  = sine(1100.0, t) * 0.32 * env
            let bright = sine(2200.0, t) * 0.18 * env
            let click  = Double.random(in: -1...1) * 0.22 * exp(-t * 80)
            return metal + bright + click
        }
    }

    private static func takeHit(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Sub-bass percussif + bruit blanc rapide → "choc cuir/métal" grave.
        // Joué quand le joueur encaisse un coup.
        return synth(format: format, durationS: 0.32) { t in
            let env = exp(-t * 14)
            let sub  = sine(70.0,  t) * 0.55 * env
            let mid  = sine(160.0, t) * 0.22 * env
            let noise = Double.random(in: -1...1) * 0.32 * env
            return sub + mid + noise
        }
    }

    private static func diceRoll(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Très court : impulse de bruit filtré "tac" de bois.
        // On simule un passe-bande grossier en additionnant deux passes-bas.
        return synth(format: format, durationS: 0.12) { t in
            let env = exp(-t * 60)
            let click = Double.random(in: -1...1) * 0.55 * env
            // touche grave courte
            let body = sine(450.0, t) * 0.25 * exp(-t * 35)
            return click + body
        }
    }

    private static func lucky(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Deux notes brèves ascendantes, ton cristal léger.
        return synth(format: format, durationS: 0.55) { t in
            let n1 = noteEnv(t: t, start: 0.00, attack: 0.004, decay: 0.20)
            let n2 = noteEnv(t: t, start: 0.13, attack: 0.004, decay: 0.40)
            return sine(1568.0, t) * 0.28 * n1 + sine(2349.0, t) * 0.30 * n2
        }
    }

    private static func unlucky(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Note descendante avec léger bruit, ambiance "déception".
        return synth(format: format, durationS: 0.55) { t in
            let env = exp(-t * 4)
            // glissement de 392 Hz (G4) à ~262 Hz (C4)
            let freq = 392.0 - 130.0 * min(t / 0.4, 1.0)
            let body = sine(freq, t) * 0.30 * env
            let noise = Double.random(in: -1...1) * 0.05 * env
            return body + noise
        }
    }

    private static func victory(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Arpège C-E-G-C, ton triomphal court.
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
        // Fallback synth : note grave courte qui s'effondre — esquisse du
        // "râle final" d'une créature qui meurt. Le fichier audio
        // creature_die_01.m4a remplace ce buffer en pratique.
        return synth(format: format, durationS: 0.7) { t in
            let env = exp(-t * 3.5)
            let freq = 220.0 - 80.0 * min(t / 0.5, 1.0)
            let body = sine(freq, t) * 0.45 * env
            let noise = Double.random(in: -1...1) * 0.10 * env
            return body + noise
        }
    }

    private static func pageTurn(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Fallback synthétique : courte bouffée de bruit filtré qui ressemble
        // vaguement à un froissement de papier. En pratique le fichier
        // page_turn.m4a remplace ce buffer.
        return synth(format: format, durationS: 0.35) { t in
            let env = exp(-t * 6) * (1 - exp(-t * 60))
            let noise = Double.random(in: -1...1)
            return noise * 0.28 * env
        }
    }

    private static func buttonTap(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Très court "tic" sec, mid-haut, façon plume qui se pose sur la page.
        // Decay agressif pour ne pas se traîner et rester discret par-dessus
        // les autres sons (musique, dés…).
        return synth(format: format, durationS: 0.07) { t in
            let env = exp(-t * 90)
            let click = Double.random(in: -1...1) * 0.35 * env
            let tone = sine(1900.0, t) * 0.14 * env
            return click + tone
        }
    }

    private static func death(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Note grave longue qui s'évanouit, type cloche éteinte.
        return synth(format: format, durationS: 2.0) { t in
            let env = exp(-t * 1.4)
            let fundamental = sine(110.0, t) * 0.45 * env
            let octave      = sine(220.0, t) * 0.15 * env
            let sub         = sine(55.0,  t) * 0.30 * env
            let noise       = Double.random(in: -1...1) * 0.04 * env
            return fundamental + octave + sub + noise
        }
    }

    // MARK: - Helpers

    /// Enveloppe ADR très simple : ramp up `attack`s, decay exponentiel sur
    /// `decay`s. Renvoie 0 avant `start`, et tend vers 0 après.
    private static func noteEnv(t: Double, start: Double,
                                 attack: Double, decay: Double) -> Double {
        let local = t - start
        guard local >= 0 else { return 0 }
        let attackPart = min(local / max(attack, 0.001), 1.0)
        let releaseT = max(0, local - attack)
        let releasePart = exp(-releaseT / max(decay, 0.001))
        return attackPart * releasePart
    }

    /// Sinusoïde à fréquence `f` à l'instant `t`.
    private static func sine(_ f: Double, _ t: Double) -> Double {
        sin(2.0 * .pi * f * t)
    }

    /// Construit un buffer stéréo en appliquant `generator(t)` pour chaque
    /// sample, avec soft-clip tanh.
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
