import AVFoundation
import CoreAudio

/// An input device the user can record from.
///
/// Identified by UID, not by CoreAudio's numeric device id: those are reassigned when
/// hardware is replugged, so a saved id can come back pointing at a different device.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let uid: String
    let name: String

    var id: String { uid }

    init(_ device: AVCaptureDevice) {
        uid = device.uniqueID
        name = device.localizedName
    }
}

/// Lists the microphones available for live dictation.
///
/// `AVAudioEngine` records from the system default input unless told otherwise, which is
/// the wrong guess on a machine with an audio interface, a USB mic and a virtual device
/// all connected.
enum AudioInputCatalog {

    /// Every audio input on the machine. Works before microphone access is granted —
    /// the picker has to be usable on first launch.
    static func devices() -> [AudioInputDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                         mediaType: .audio,
                                         position: .unspecified)
            .devices.map(AudioInputDevice.init)
    }

    /// The device the system would pick on its own.
    static func systemDefault() -> AudioInputDevice? {
        AVCaptureDevice.default(for: .audio).map(AudioInputDevice.init)
    }

    /// Resolves a remembered UID back to a device that's currently attached.
    static func device(uid: String) -> AudioInputDevice? {
        guard !uid.isEmpty else { return nil }
        return devices().first { $0.uid == uid }
    }

    /// CoreAudio's id for a UID — the one thing AVFoundation can't give us, and what
    /// `kAudioOutputUnitProperty_CurrentDevice` needs to point the engine at a device.
    static func deviceID(uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = withUnsafeMutablePointer(to: &cfUID) { input in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                       &address,
                                       UInt32(MemoryLayout<CFString>.size),
                                       input,
                                       &size,
                                       &deviceID)
        }
        return status == noErr && deviceID != 0 ? deviceID : nil
    }
}
