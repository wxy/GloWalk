@preconcurrency import AVFoundation
import CoreMotion
import UIKit

@MainActor
final class SensorManager: ObservableObject {
    @Published var ambientLightLevel: Double = 0.5
    @Published var devicePitch: Double = 45.0
    @Published var deviceRoll: Double = 0.0
    @Published var stepCount: Int = 0
    @Published var isOccluded: Bool = false
    /// Debounced "bright daylight" state from the front-camera exposure — stable
    /// against the auto-exposure convergence at startup and scene changes.
    @Published var isDaylight: Bool = false

    // Daylight-detector state (warm-up + debounce):
    private var warmupSamples = 8            // ~4s at 2Hz — let auto-exposure converge
    private var brightStreak = 0
    private var darkStreak = 0
    private let brightSustain = 3            // samples of "bright" to enter daylight
    private let darkSustain = 3              // samples of "not bright" to exit daylight
    /// Schmitt-trigger hysteresis for the "bright scene" decision on the
    /// exposure-based ambient level (0–1, saturating map of 1/(t·ISO)). A
    /// genuinely bright indoor room reads ~0.9, a dim room ~0.45, a dark room
    /// <0.1 — so 0.7 enter / 0.55 exit cleanly separates "bright enough that
    /// the flashlight is pointless" from everything else without toggling at
    /// the boundary.
    private let brightEnterThreshold = 0.7
    private let brightExitThreshold = 0.55
    private var brightLatched = false

    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    /// Serial queue for AVCaptureSession start/stop — AVCaptureSession is not
    /// thread-safe and startRunning() blocks, so every session transition is
    /// serialized here to avoid concurrent start/stop races.
    private let sessionQueue = DispatchQueue(label: "glowalk.camera", qos: .userInitiated)
    private var captureSession: AVCaptureSession?
    private var captureDevice: AVCaptureDevice?
    private var captureDelegate: AmbientLightDelegate?
    private var backDelegate: BackLuminanceDelegate?
    private let backQueue = DispatchQueue(label: "glowalk.backlight", qos: .utility)
    /// Back-camera readings (multi-cam only, exposure locked while measuring):
    /// full-frame average and the ground ROI average, both 2Hz.
    @Published var backFullFrameLuminance: Double?
    @Published var backGroundLuminance: Double?
    private(set) var backExposureLocked = false
    private var exposureRefreshTimer: Timer?
    /// Monotonic generation counter for the capture session. Bumped on every
    /// start/stop so in-flight frames or restore callbacks from an older session
    /// (stop→start within a throttle window) can't mutate the detector state of
    /// the current one.
    private var sessionEpoch = 0

    // MARK: - Start / Stop

    func start() {
        startAmbientLightSampling()
        startMotionUpdates()
        startPedometer()
        startProximityMonitoring()
    }

    func stop() {
        turnOffTorch()
        exposureRefreshTimer?.invalidate()
        exposureRefreshTimer = nil
        backDelegate = nil
        backFullFrameLuminance = nil
        backGroundLuminance = nil
        backExposureLocked = false
        stopProximityMonitoring()
        // Invalidate any in-flight samples/restores from this capture session so
        // they can't mutate detector state after teardown.
        sessionEpoch += 1
        captureDelegate = nil
        if let session = captureSession {
            NotificationCenter.default.removeObserver(self,
                name: .AVCaptureSessionRuntimeError, object: session)
            NotificationCenter.default.removeObserver(self,
                name: .AVCaptureSessionWasInterrupted, object: session)
        }
        // Serialize with any in-flight startRunning() on sessionQueue.
        nonisolated(unsafe) let session = captureSession
        sessionQueue.async {
            if let session {
                session.stopRunning()
            }
        }
        captureSession = nil
        captureDevice = nil
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    // MARK: - Torch Control

    func setTorchLevel(_ level: Double) {
        let clamped = min(max(level, 0.0), 1.0)
        _setTorchDirect(clamped)
    }

    /// The back camera's torch device — independent of the front ambient camera,
    /// which has no torch.
    private var torchDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// Set torch directly on device (works even when session is interrupted).
    /// In background, iOS may still kill the torch — this is a best-effort approach.
    private func _setTorchDirect(_ level: Double) {
        guard let device = torchDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            if level < 0.01 {
                device.torchMode = .off
            } else {
                try device.setTorchModeOn(level: Float(level))
            }
            device.unlockForConfiguration()
        } catch {
            print("Torch error: \(error)")
        }
    }

    private func turnOffTorch() {
        // Torch control is independent of the ambient camera — always the back device.
        guard let device = torchDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            print("Torch off error: \(error)")
        }
    }

    // MARK: - Ambient Light (camera frame sampling)

    /// True when this device supports concurrent front + back capture
    /// (AVCaptureMultiCamSession, iOS 13+). Falls back to single-session
    /// front-camera capture otherwise, preserving current behaviour.
    private var isMultiCam: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    private func makeSession() -> AVCaptureSession {
        if isMultiCam {
            let s = AVCaptureMultiCamSession()
            // AVCaptureMultiCamSession's preset is ALWAYS .inputPriority —
            // setting .low/.medium/… throws NSInvalidArgumentException on
            // device. Formats are chosen per camera (setSmallFormat).
            s.sessionPreset = .inputPriority
            return s
        }
        let s = AVCaptureSession()
        s.sessionPreset = .low
        return s
    }

    /// With .inputPriority the session won't pick formats for us. Choose a
    /// multi-cam-capable format: AVCaptureMultiCamSession only accepts the
    /// subset of formats where AVCaptureDevice.Format.isMultiCamSupported is
    /// true — picking any other format fails startRunning with
    /// AVErrorUnsupportedDeviceActiveFormat (-11873). Prefer a mid-resolution
    /// format (480–1280 wide) that supports 30fps, then pin 30fps so a
    /// high-frame-rate-capable format can't blow the hardware cost budget.
    private func setMultiCamFormat(on device: AVCaptureDevice) {
        let multiCam = device.formats.filter { $0.isMultiCamSupported }
        let supports30 = { (fmt: AVCaptureDevice.Format) in
            fmt.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
        }
        let preferred = multiCam.filter { fmt in
            let d = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            return d.width >= 480 && d.width <= 1280 &&
                   d.height >= 360 && d.height <= 720 && supports30(fmt)
        }
        let pool = preferred.isEmpty ? multiCam.filter(supports30) : preferred
        print("[Sensor] setMultiCamFormat: \(device.position == .back ? "back" : "front") preferred=\(preferred.count)/\(multiCam.count)/\(device.formats.count) multiCamSupported=\(multiCam.count)")
        guard let fmt = pool.min(by: {
            let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return a.width * a.height < b.width * b.height
        }) else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        print("[Sensor] setMultiCamFormat: chosen \(dims.width)x\(dims.height)@30 multiCam=\(fmt.isMultiCamSupported)")
        do {
            try device.lockForConfiguration()
            device.activeFormat = fmt
            // Pin the device to 30fps (SDK: connection-level frame-duration
            // APIs are unavailable; set the device's active durations instead).
            let dur = CMTime(value: 1, timescale: 30)
            device.activeVideoMinFrameDuration = dur
            device.activeVideoMaxFrameDuration = dur
            device.unlockForConfiguration()
        } catch {
            print("[Sensor] Set multi-cam format failed: \(error)")
        }
    }

    /// Add the back camera (multi-cam only) and lock its exposure, so its
    /// pixel readings reflect the scene — including the torch's reflection off
    /// the ground — instead of being normalised away by auto-exposure.
    private func addBackCamera(to session: AVCaptureSession) {
        guard isMultiCam,
              let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: back) else { return }
        guard session.canAddInput(input) else {
            print("[Sensor] addBackCamera: canAddInput == false")
            return
        }
        // Multi-cam wiring is always explicit: add inputs/outputs without
        // connections and form connections manually (WWDC19 session 249).
        session.addInputWithNoConnections(input)
        print("[Sensor] addBackCamera: input added")
        setMultiCamFormat(on: back)

        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let epoch = sessionEpoch
        let delegate = BackLuminanceDelegate { [weak self] sample in
            Task { @MainActor in
                self?.applyBackSample(sample, epoch: epoch)
            }
        }
        backDelegate = delegate
        out.setSampleBufferDelegate(delegate, queue: backQueue)
        guard session.canAddOutput(out) else {
            print("[Sensor] addBackCamera: canAddOutput == false")
            return
        }
        session.addOutputWithNoConnections(out)
        print("[Sensor] addBackCamera: output added")
        if let port = input.ports.first(where: { $0.mediaType == .video }) {
            let conn = AVCaptureConnection(inputPorts: [port], output: out)
            if session.canAddConnection(conn) {
                session.addConnection(conn)
                print("[Sensor] addBackCamera: connection added")
            } else {
                print("[Sensor] addBackCamera: canAddConnection == false")
            }
        }
        lockBackExposure()
    }

    /// Fixed dark-scene exposure (1/60s, minimum ISO) so the back camera
    /// measures luminance monotonically. Calibrated on device during the
    /// measurement campaign if needed.
    private func lockBackExposure() {
        guard let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        do {
            try back.lockForConfiguration()
            let fmt = back.activeFormat
            let duration = CMTime(value: 1, timescale: 60)
            back.setExposureModeCustom(duration: duration,
                                       iso: Float(fmt.minISO),
                                       completionHandler: nil)
            back.unlockForConfiguration()
            backExposureLocked = true
        } catch {
            print("[Sensor] Back exposure lock error: \(error)")
        }
    }

    private func applyBackSample(_ sample: BackLuminanceSample, epoch: Int) {
        guard epoch == sessionEpoch else { return }
        if backGroundLuminance == nil {
            print("[Sensor] back first sample roi=\(sample.roi) full=\(sample.fullFrame)")
        }
        backFullFrameLuminance = sample.fullFrame
        backGroundLuminance = sample.roi
    }

    private func startAmbientLightSampling() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return
        }

        let session = makeSession()

        // Front camera for ambient sensing — it faces away from the back torch,
        // so its reading isn't inflated by the flashlight's own reflection. That
        // gives a reliable day/night signal (used to turn the torch off in
        // bright daylight and to brighten the UI).
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        captureDevice = device
        setMultiCamFormat(on: device)
        // Continuous auto-exposure so the camera naturally tracks the scene
        // light between the periodic re-triggers.
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("[Sensor] Set continuous exposure failed: \(error)")
        }
        let output = AVCaptureVideoDataOutput()
        // Request BGRA explicitly — without this, iOS delivers the device-native
        // format (NV12 on iPhones) and AmbientLightDelegate drops every frame.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // Bump the epoch so any in-flight frames from a previous session are
        // ignored by the detector, and reset the detector to a fresh warm-up —
        // otherwise stale isDaylight/bright-latch from the last walk could carry
        // into this one.
        sessionEpoch += 1
        let epoch = sessionEpoch
        warmupSamples = 8
        brightStreak = 0
        darkStreak = 0
        brightLatched = false
        isDaylight = false
        let delegate = AmbientLightDelegate(device: device) { [weak self] sample in
            Task { @MainActor in
                self?.applyAmbientSample(sample, epoch: epoch)
            }
        }
        captureDelegate = delegate
        output.setSampleBufferDelegate(delegate,
            queue: DispatchQueue(label: "glowalk.ambient", qos: .utility))
        if isMultiCam {
            // Multi-cam wiring is always explicit: add inputs/outputs without
            // connections and form connections manually (WWDC19 session 249).
            session.addInputWithNoConnections(input)
            session.addOutputWithNoConnections(output)
            if let port = input.ports.first(where: { $0.mediaType == .video }) {
                let conn = AVCaptureConnection(inputPorts: [port], output: output)
                if session.canAddConnection(conn) {
                    session.addConnection(conn)
                    print("[Sensor] front connection added")
                } else {
                    print("[Sensor] front canAddConnection == false")
                }
            }
        } else {
            session.addInput(input)
            session.addOutput(output)
        }
        print("[Sensor] start: multiCam=\(isMultiCam) front output added")
        if isMultiCam {
            addBackCamera(to: session)
        }
        captureSession = session
        if let multiCam = session as? AVCaptureMultiCamSession {
            print("[Sensor] multiCam hardwareCost=\(multiCam.hardwareCost)")
        }
        nonisolated(unsafe) let s = session
        sessionQueue.async {
            s.startRunning()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task { @MainActor in
                    print("[Sensor] session isRunning=\(s.isRunning) multiCam=\(self.isMultiCam)")
                }
            }
        }
        NotificationCenter.default.addObserver(self,
            selector: #selector(captureRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session)
        NotificationCenter.default.addObserver(self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session)
        // Legacy (non-spike) path: periodically re-trigger auto-exposure so the
        // old pixel-average daylight detector doesn't stay stuck on a stale
        // exposure. The closed-loop spike deliberately disables this: each
        // perturb shorts the exposure and the proxy spikes high while
        // auto-exposure re-converges — every 4s that re-feeds the bright latch
        // and keeps the torch off in a dark area for the whole walk.
        if !FeatureFlags.torchClosedLoop {
            exposureRefreshTimer?.invalidate()
            exposureRefreshTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAutoExposure()
                }
            }
        }
    }

    @objc private func captureRuntimeError(_ note: Notification) {
        if let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            print("[Sensor] capture runtime error: domain=\(error.domain) code=\(error.code) \(error.localizedDescription)")
        } else {
            print("[Sensor] capture runtime error: (no error payload)")
        }
    }

    @objc private func sessionWasInterrupted(_ note: Notification) {
        var reasonDesc = "unknown"
        if let reason = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int {
            switch reason {
            case AVCaptureSession.InterruptionReason.videoDeviceInUseByAnotherClient.rawValue:
                reasonDesc = "videoDeviceInUseByAnotherClient"
            case AVCaptureSession.InterruptionReason.videoDeviceNotAvailableDueToSystemPressure.rawValue:
                reasonDesc = "videoDeviceNotAvailableDueToSystemPressure"
            case AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue:
                reasonDesc = "audioDeviceInUseByAnotherClient"
            default:
                reasonDesc = "raw=\(reason)"
            }
        }
        print("[Sensor] capture session interrupted: \(reasonDesc)")
    }

    /// Force the auto-exposure to re-converge to the current scene. Setting
    /// .autoExpose when already converged can be ignored by iOS, so perturb the
    /// exposure first (a shorter custom exposure) and then restore auto.
    ///
    /// The perturb uses ¼ of the current exposure — NOT a fixed 1ms black frame.
    /// A 1ms frame reads as spuriously "bright" via the light proxy (1/iso·t) for
    /// several samples while auto-exposure climbs back up, which the debounce
    /// can't distinguish from real daylight. A ¼-exposure frame re-converges in a
    /// frame or two, and the delegate skips non-auto frames anyway (see
    /// AmbientLightDelegate.captureOutput).
    private func refreshAutoExposure() {
        // Only re-trigger exposure while the capture session is actually running.
        // On a stopped/idle device device.iso can read 0.0 (the crash we hit), and
        // a forced exposure on a non-running camera is pointless anyway.
        guard let device = captureDevice, captureSession?.isRunning == true else { return }
        let epoch = sessionEpoch
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.custom) {
                // setExposureModeCustom raises an ObjC NSException (NOT catchable
                // by Swift's do/catch) for out-of-range parameters. device.iso can
                // transiently read 0.0 (e.g. mid-reconfiguration or right after a
                // session restart), which crashed here — so clamp both ISO and
                // duration to the active format's supported range before calling.
                let fmt = device.activeFormat
                let iso = Double(device.iso)
                let minISO = Double(fmt.minISO)
                let maxISO = Double(fmt.maxISO)
                let safeISO = iso.isFinite ? min(max(iso, minISO), maxISO) : minISO
                let current = device.exposureDuration
                guard current.seconds.isFinite, current.seconds > 0 else {
                    device.unlockForConfiguration()
                    return
                }
                var short = CMTimeMultiplyByFloat64(current, multiplier: 0.25)
                if CMTimeCompare(short, fmt.minExposureDuration) < 0 {
                    short = fmt.minExposureDuration
                }
                if CMTimeCompare(short, fmt.maxExposureDuration) > 0 {
                    short = fmt.maxExposureDuration
                }
                device.setExposureModeCustom(duration: short, iso: Float(safeISO), completionHandler: nil)
            }
            device.unlockForConfiguration()
        } catch {
            print("[Sensor] Exposure refresh error: \(error)")
        }
        // Restore continuous auto-exposure after the brief custom window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            Task { @MainActor in
                self?.restoreAutoExposure(epoch: epoch)
            }
        }
    }

    private func restoreAutoExposure(epoch: Int) {
        // Ignore if the session was stopped/restarted while the delay was pending.
        guard epoch == sessionEpoch, let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("[Sensor] Exposure restore error: \(error)")
        }
    }

    /// Restarts the capture session if iOS stopped it (e.g. the app was
    /// backgrounded). Called from HUDViewModel.didBecomeActive.
    func resumeSessionIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return
        }
        guard let session = captureSession, !session.isRunning else {
            return
        }
        nonisolated(unsafe) let s = session
        sessionQueue.async {
            if !s.isRunning {
                s.startRunning()
            }
        }
    }

    // MARK: - Ambient Sample Processing (daylight debounce)

    /// Handle one ambient sample from the camera delegate: warm up until the
    /// auto-exposure converges, then debounce the daylight state (sustain runs
    /// of consistent samples) so a transient scene change doesn't flip the torch.
    /// While daylight is confirmed, boost the ambient reading so the LightEngine
    /// gate and the HUD follow reliably.
    private func applyAmbientSample(_ sample: AmbientSample, epoch: Int) {
        // Ignore frames from an older capture session (e.g. a quick stop→start).
        guard epoch == sessionEpoch else { return }

        // If the proximity sensor reports an object over the camera (hand,
        // pocket), the reading is of that object — not the ambient. Don't meter.
        if isOccluded { return }

        // Warm-up: ignore daylight decisions until auto-exposure settles.
        if warmupSamples > 0 {
            warmupSamples -= 1
            ambientLightLevel = sample.level
            return
        }

        // Brightness with hysteresis on the exposure-based level (the pixel
        // average is useless — auto-exposure holds it near 0.5 everywhere).
        // Latch on once above the enter threshold, drop out only below the
        // exit threshold.
        let isBright = brightLatched
            ? sample.level > brightExitThreshold
            : sample.level > brightEnterThreshold
        brightLatched = isBright

        // Bright scenes confirm at any hour — a well-lit indoor room at night
        // should turn the flashlight off just like daylight. The debounce
        // (sustain + hysteresis) is what stops a passing street lamp or car
        // headlight from killing the torch.
        if isBright {
            brightStreak += 1
            darkStreak = 0
            if brightStreak >= brightSustain { isDaylight = true }
        } else {
            darkStreak += 1
            brightStreak = 0
            if isDaylight && darkStreak >= darkSustain { isDaylight = false }
        }

        // Boost only after daylight is debounce-confirmed so the torch-off and
        // the "bright light" notice happen together.
        let rawLevel = isDaylight ? max(sample.level, 0.85) : sample.level
        // EMA smoothing: the exposure proxy jitters as auto-exposure hunts, and
        // the raw level would flicker the label and the 1-ambient torch
        // fallback between ticks. Time constant ≈ 1.4s at 2Hz.
        ambientLightLevel = ambientLightLevel * 0.7 + rawLevel * 0.3
    }

    // MARK: - Motion

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            let pitch = motion.attitude.pitch * 180 / .pi
            let roll  = motion.attitude.roll  * 180 / .pi
            // The callback is a Sendable concurrent context even though it fires
            // on the main run loop — writing the MainActor-isolated properties
            // directly trips the runtime "unsafeForcedSync called from Swift
            // Concurrent context" log. Hop to MainActor like the other callbacks.
            Task { @MainActor in
                self?.devicePitch = abs(pitch)
                self?.deviceRoll  = abs(roll)
            }
        }
    }

    // MARK: - Pedometer

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data = data else { return }
            Task { @MainActor in
                self?.stepCount = data.numberOfSteps.intValue
            }
        }
    }

    // MARK: - Proximity Detection (occlusion)

    private func startProximityMonitoring() {
        UIDevice.current.isProximityMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proximityChanged),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
        isOccluded = UIDevice.current.proximityState
    }

    @objc private func proximityChanged() {
        Task { @MainActor in
            let newState = UIDevice.current.proximityState
            guard newState != self.isOccluded else { return }
            // Reset the daylight debounce across the occlusion gap: streak counts
            // from before the cover are stale, and isDaylight frozen during
            // occlusion would otherwise drive the wrong torch/screen state when
            // the phone comes back out (torch briefly ON in daylight, or screen
            // forced to 1.0 at night). Re-derive from fresh samples.
            self.brightStreak = 0
            self.darkStreak = 0
            self.brightLatched = false
            self.isOccluded = newState
            if !newState {
                self.isDaylight = false
            }
        }
    }

    private func stopProximityMonitoring() {
        UIDevice.current.isProximityMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self,
            name: UIDevice.proximityStateDidChangeNotification, object: nil)
    }
}

// MARK: - Camera Frame Delegate

/// One ambient-light sample with the camera exposure data used to detect
/// sunlight (auto-exposure compresses the average pixel brightness).
private struct AmbientSample {
    let level: Double
    let lightProxy: Double
}

private final class AmbientLightDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onSample: (AmbientSample) -> Void
    private let device: AVCaptureDevice
    private var lastEmitTime: Date = .distantPast
    private var droppedCount: Int = 0

    init(device: AVCaptureDevice, onSample: @escaping (AmbientSample) -> Void) {
        self.device = device
        self.onSample = onSample
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Skip frames captured while the exposure perturb is active (custom
        // exposure). Their light proxy is meaningless, and the near-black frame
        // would be misread as "bright" — the opposite of what the debounce
        // expects. Only auto-exposure frames reflect the real scene. Checked
        // before the throttle so the first auto frame after the perturb emits
        // immediately instead of waiting out the 0.5s slot.
        guard device.exposureMode == .continuousAutoExposure else { return }

        // Throttle to ~2 Hz to avoid flooding the main thread
        let now = Date()
        guard now.timeIntervalSince(lastEmitTime) > 0.5 else { return }
        lastEmitTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            droppedCount += 1
            if droppedCount == 1 || droppedCount % 50 == 0 {
                print("[Sensor] Dropping ambient frame — format \(pixelFormat) != BGRA (total dropped \(droppedCount))")
            }
            return
        }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4
        let sampleStep = 8

        // Sample the peripheral band only — the frame centre is dominated by the
        // user's face (often in the phone's shadow), which doesn't track the
        // ambient light. The edges show the surroundings, so this is a truer
        // ambient reading that responds to daylight without needing the camera to
        // be re-triggered.
        let xInset = width / 4
        let yInset = height / 4
        var total: Double = 0
        var count: Int = 0
        for y in stride(from: 0, to: height, by: sampleStep) {
            let inCenterY = y >= yInset && y < height - yInset
            for x in stride(from: 0, to: width, by: sampleStep) {
                if inCenterY && x >= xInset && x < width - xInset { continue }
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Double(baseAddress.load(fromByteOffset: offset,   as: UInt8.self))
                let g = Double(baseAddress.load(fromByteOffset: offset+1, as: UInt8.self))
                let b = Double(baseAddress.load(fromByteOffset: offset+2, as: UInt8.self))
                total += (r + g + b) / (3.0 * 255.0)
                count += 1
            }
        }

        guard count > 0 else { return }
        // Auto-exposure compresses the average pixel brightness, so the raw
        // average stays ~0.5 in BOTH a dark room and bright sunlight — it is
        // not a usable ambient signal. The camera encodes the true scene
        // brightness in its exposure: bright scenes use a short duration and
        // low ISO. Light proxy = 1/(exposure × ISO); the higher, the brighter.
        let iso = Double(device.iso)
        let exposureSec = Double(device.exposureDuration.seconds)
        let lightProxy = 1.0 / max(exposureSec * iso, 1e-9)
        // Ambient level = saturating map of the exposure proxy. Calibration
        // (device campaign, 2026-08-08): a well-lit indoor room meters at
        // proxy ≈ 0.08–0.33 and a night scene at proxy ≈ 0.005–0.03, so the
        // knee is placed at proxy ≈ 0.07 — a well-lit room reads ~0.8–0.9
        // ("bright"), a dim room ~0.5–0.7, night ~0.05–0.1, instead of the
        // old pixel average which auto-exposure pinned near 0.5 everywhere.
        let level = min(max(1.0 - exp(-lightProxy / 0.07), 0.0), 1.0)
        onSample(AmbientSample(level: level, lightProxy: lightProxy))
    }
}

// MARK: - Back Camera Luminance Delegate

/// One back-camera luminance sample: full-frame average and the ground ROI
/// average (lower third, central 60% width — the path ahead in walking
/// posture).
private struct BackLuminanceSample {
    let fullFrame: Double
    let roi: Double
}

private final class BackLuminanceDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onSample: (BackLuminanceSample) -> Void
    private var lastEmitTime: Date = .distantPast
    private var emittedCount = 0

    init(onSample: @escaping (BackLuminanceSample) -> Void) {
        self.onSample = onSample
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Throttle to ~2 Hz to avoid flooding the main thread.
        let now = Date()
        guard now.timeIntervalSince(lastEmitTime) > 0.5 else { return }
        lastEmitTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        emittedCount += 1
        if emittedCount == 1 {
            print("[Sensor] back frame: \(width)x\(height) format=\(CVPixelBufferGetPixelFormatType(pixelBuffer))")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4
        let step = 8

        var fullTotal = 0.0
        var fullCount = 0
        var roiTotal = 0.0
        var roiCount = 0
        let yStart = height * 2 / 3
        let xInset = width / 5

        for y in stride(from: 0, to: height, by: step) {
            let inROI = y >= yStart
            for x in stride(from: 0, to: width, by: step) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Double(baseAddress.load(fromByteOffset: offset, as: UInt8.self))
                let g = Double(baseAddress.load(fromByteOffset: offset + 1, as: UInt8.self))
                let b = Double(baseAddress.load(fromByteOffset: offset + 2, as: UInt8.self))
                let lum = (r + g + b) / (3.0 * 255.0)
                fullTotal += lum
                fullCount += 1
                if inROI, x >= xInset, x < width - xInset {
                    roiTotal += lum
                    roiCount += 1
                }
            }
        }
        guard fullCount > 0 else { return }
        onSample(BackLuminanceSample(
            fullFrame: fullTotal / Double(fullCount),
            roi: roiCount > 0 ? roiTotal / Double(roiCount) : fullTotal / Double(fullCount)))
    }
}
