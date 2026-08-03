@preconcurrency import AVFoundation
import CoreMotion
import UIKit

@MainActor
final class SensorManager: ObservableObject {
    @Published var ambientLightLevel: Double = 0.5
    @Published var devicePitch: Double = 45.0
    @Published var deviceRoll: Double = 0.0
    @Published var isWalking: Bool = false
    @Published var stepCount: Int = 0
    @Published var isOccluded: Bool = false
    @Published var isManualMode: Bool = false

    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    /// Serial queue for AVCaptureSession start/stop — AVCaptureSession is not
    /// thread-safe and startRunning() blocks, so every session transition is
    /// serialized here to avoid concurrent start/stop races.
    private let sessionQueue = DispatchQueue(label: "glowalk.camera", qos: .userInitiated)
    private var captureSession: AVCaptureSession?
    private var captureDevice: AVCaptureDevice?
    private var captureDelegate: AmbientLightDelegate?

    // MARK: - Camera Permission

    static var cameraAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestCameraPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Start / Stop

    func start() {
        startAmbientLightSampling()
        startMotionUpdates()
        startPedometer()
        startProximityMonitoring()
    }

    func stop() {
        turnOffTorch()
        stopProximityMonitoring()
        // Serialize with any in-flight startRunning() on sessionQueue.
        nonisolated(unsafe) let session = captureSession
        sessionQueue.async {
            if let session {
                print("[Sensor] Camera stopRunning begin")
                session.stopRunning()
                print("[Sensor] Camera stopRunning done")
            }
        }
        captureSession = nil
        captureDevice = nil
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
        print("[Sensor] SensorManager stop() — torch off, camera stop queued, motion/pedometer stopped")
    }

    // MARK: - Torch Control

    func setTorchLevel(_ level: Double) {
        let clamped = min(max(level, 0.0), 1.0)
        _setTorchDirect(clamped)
    }

    /// Set torch directly on device (works even when session is interrupted).
    /// In background, iOS may still kill the torch — this is a best-effort approach.
    private func _setTorchDirect(_ level: Double) {
        guard let device = captureDevice ?? AVCaptureDevice.default(.builtInWideAngleCamera,
                                                                     for: .video, position: .back),
              device.hasTorch, device.isTorchAvailable else { return }
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
        guard let device = captureDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            print("Torch off error: \(error)")
        }
    }

    // MARK: - Ambient Light (camera frame sampling)

    private func startAmbientLightSampling() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            isManualMode = true
            print("[Sensor] Ambient sampling skipped — camera not authorized, manual mode")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .low

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            isManualMode = true
            print("[Sensor] Ambient sampling skipped — no back camera or input creation failed")
            return
        }

        captureDevice = device
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        // Request BGRA explicitly — without this, iOS delivers the device-native
        // format (NV12 on iPhones) and AmbientLightDelegate drops every frame.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let delegate = AmbientLightDelegate { [weak self] level in
            Task { @MainActor in
                self?.ambientLightLevel = level
            }
        }
        captureDelegate = delegate
        output.setSampleBufferDelegate(delegate,
            queue: DispatchQueue(label: "glowalk.ambient", qos: .utility))
        session.addOutput(output)
        captureSession = session
        print("[Sensor] Ambient camera configured (BGRA requested), starting capture")
        nonisolated(unsafe) let s = session
        sessionQueue.async {
            print("[Sensor] Camera startRunning begin")
            s.startRunning()
            print("[Sensor] Camera startRunning done — isRunning=\(s.isRunning)")
        }
    }

    /// Restarts the capture session if iOS stopped it (e.g. the app was
    /// backgrounded). Called from HUDViewModel.didBecomeActive.
    func resumeSessionIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            print("[Sensor] Resume skipped — camera not authorized")
            return
        }
        guard let session = captureSession, !session.isRunning else {
            print("[Sensor] Resume skipped — no session or already running (isRunning=\(captureSession?.isRunning ?? false))")
            return
        }
        print("[Sensor] Resume requested — camera not running after background, restarting")
        nonisolated(unsafe) let s = session
        sessionQueue.async {
            if !s.isRunning {
                s.startRunning()
                print("[Sensor] Camera resumed after background — isRunning=\(s.isRunning)")
            }
        }
    }

    // MARK: - Motion

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            let pitch = motion.attitude.pitch * 180 / .pi
            let roll  = motion.attitude.roll  * 180 / .pi
            self?.devicePitch = abs(pitch)
            self?.deviceRoll  = abs(roll)
        }
    }

    // MARK: - Pedometer

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data = data else { return }
            Task { @MainActor in
                self?.stepCount = data.numberOfSteps.intValue
                self?.isWalking = data.numberOfSteps.intValue > 0
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
            self.isOccluded = UIDevice.current.proximityState
        }
    }

    private func stopProximityMonitoring() {
        UIDevice.current.isProximityMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self,
            name: UIDevice.proximityStateDidChangeNotification, object: nil)
    }
}

// MARK: - Camera Frame Delegate

private final class AmbientLightDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onSample: (Double) -> Void
    private var lastEmitTime: Date = .distantPast
    private var bgraSampleCount: Int = 0
    private var droppedCount: Int = 0

    init(onSample: @escaping (Double) -> Void) {
        self.onSample = onSample
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Throttle to ~2 Hz to avoid flooding the main thread
        let now = Date()
        guard now.timeIntervalSince(lastEmitTime) > 0.5 else { return }
        lastEmitTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if bgraSampleCount == 0 {
            print("[Sensor] First ambient frame — format \(pixelFormat) (expect BGRA=\(kCVPixelFormatType_32BGRA))")
        }
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

        var total: Double = 0
        var count: Int = 0
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Double(baseAddress.load(fromByteOffset: offset,   as: UInt8.self))
                let g = Double(baseAddress.load(fromByteOffset: offset+1, as: UInt8.self))
                let b = Double(baseAddress.load(fromByteOffset: offset+2, as: UInt8.self))
                total += (r + g + b) / (3.0 * 255.0)
                count += 1
            }
        }

        guard count > 0 else { return }
        bgraSampleCount += 1
        let level = total / Double(count)
        // Log the first few samples, then one every 30 (≈ every 15s) — enough
        // to confirm the ambient light factor is live without flooding the log.
        if bgraSampleCount <= 3 || bgraSampleCount % 30 == 0 {
            print("[Sensor] Ambient sample #\(bgraSampleCount) = \(String(format: "%.3f", level))")
        }
        onSample(level)
    }
}
