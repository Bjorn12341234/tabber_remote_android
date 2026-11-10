import Foundation

/// Tabber Studio's Drum Map (ui/fretboard_widget.py DrumGuideCanvas): the
/// common kit sounds, GM 35 to 59, each with its number and General MIDI
/// name, as core/drum_kit.py names them. On drum tab (tab.drum/1) a note's
/// fret is such a number, and the Drum Map is what the phone writes with.
public enum DrumMap {
    /// The numbers the Drum Map lists, in its order.
    public static let numbers = Array(35...59)

    /// The GM percussion names Tabber Studio knows (GM Level 1, 35 to 81).
    public static let names: [Int: String] = [
        35: "Acoustic Bass Drum", 36: "Bass Drum 1", 37: "Side Stick", 38: "Acoustic Snare", 39: "Hand Clap",
        40: "Electric Snare", 41: "Low Floor Tom", 42: "Closed Hi-Hat", 43: "High Floor Tom", 44: "Pedal Hi-Hat",
        45: "Low Tom", 46: "Open Hi-Hat", 47: "Low-Mid Tom", 48: "Hi-Mid Tom", 49: "Crash Cymbal 1",
        50: "High Tom", 51: "Ride Cymbal 1", 52: "Chinese Cymbal", 53: "Ride Bell", 54: "Tambourine",
        55: "Splash Cymbal", 56: "Cowbell", 57: "Crash Cymbal 2", 58: "Vibraslap", 59: "Ride Cymbal 2",
        60: "Hi Bongo", 61: "Low Bongo", 62: "Mute Hi Conga", 63: "Open Hi Conga", 64: "Low Conga",
        65: "High Timbale", 66: "Low Timbale", 67: "High Agogo", 68: "Low Agogo", 69: "Cabasa",
        70: "Maracas", 71: "Short Whistle", 72: "Long Whistle", 73: "Short Guiro", 74: "Long Guiro",
        75: "Claves", 76: "Hi Wood Block", 77: "Low Wood Block", 78: "Mute Cuica", 79: "Open Cuica",
        80: "Mute Triangle", 81: "Open Triangle",
    ]

    /// A number's name; one outside GM's list is "Percussion 12", as Tabber Studio calls it.
    public static func name(_ number: Int) -> String { names[number] ?? "Percussion \(number)" }
}
