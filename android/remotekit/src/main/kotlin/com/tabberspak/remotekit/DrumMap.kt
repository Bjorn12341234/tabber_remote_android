package com.tabberspak.remotekit

/**
 * Tabber Studio's Drum Map (ui/fretboard_widget.py DrumGuideCanvas): the common kit sounds,
 * GM 35 to 59, each with its number and General MIDI name, as core/drum_kit.py names them, as
 * apple/RemoteKit/DrumMap.swift. On drum tab (tab.drum/1) a note's fret is such a number, and
 * the Drum Map is what the phone writes with.
 */
object DrumMap {
    /** The numbers the Drum Map lists, in its order. */
    val numbers: List<Int> = (35..59).toList()

    /** The GM percussion names Tabber Studio knows (GM Level 1, 35 to 81). */
    val names: Map<Int, String> = mapOf(
        35 to "Acoustic Bass Drum", 36 to "Bass Drum 1", 37 to "Side Stick", 38 to "Acoustic Snare", 39 to "Hand Clap",
        40 to "Electric Snare", 41 to "Low Floor Tom", 42 to "Closed Hi-Hat", 43 to "High Floor Tom", 44 to "Pedal Hi-Hat",
        45 to "Low Tom", 46 to "Open Hi-Hat", 47 to "Low-Mid Tom", 48 to "Hi-Mid Tom", 49 to "Crash Cymbal 1",
        50 to "High Tom", 51 to "Ride Cymbal 1", 52 to "Chinese Cymbal", 53 to "Ride Bell", 54 to "Tambourine",
        55 to "Splash Cymbal", 56 to "Cowbell", 57 to "Crash Cymbal 2", 58 to "Vibraslap", 59 to "Ride Cymbal 2",
        60 to "Hi Bongo", 61 to "Low Bongo", 62 to "Mute Hi Conga", 63 to "Open Hi Conga", 64 to "Low Conga",
        65 to "High Timbale", 66 to "Low Timbale", 67 to "High Agogo", 68 to "Low Agogo", 69 to "Cabasa",
        70 to "Maracas", 71 to "Short Whistle", 72 to "Long Whistle", 73 to "Short Guiro", 74 to "Long Guiro",
        75 to "Claves", 76 to "Hi Wood Block", 77 to "Low Wood Block", 78 to "Mute Cuica", 79 to "Open Cuica",
        80 to "Mute Triangle", 81 to "Open Triangle",
    )

    /** A number's name; one outside GM's list is "Percussion 12", as Tabber Studio calls it. */
    fun name(number: Int): String = names[number] ?: "Percussion $number"
}
