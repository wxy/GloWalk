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
        captureSession?.stopRunning()
        captureSession = nil
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
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
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .low

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            isManualMode = true
            return
        }

        captureDevice = device
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
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
        nonisolated(unsafe) let s = session
        DispatchQueue.global(qos: .userInitiated).async {
            s.startRunning()
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
    private var callCount: Int = 0
    private var lastEmitTime: Date = .distantPast

    init(onSample: @escaping (Double) -> Void) {
        self.onSample = onSample
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        callCount += 1
        // Throttle to ~2 Hz to avoid flooding the main thread
        let now = Date()
        guard now.timeIntervalSince(lastEmitTime) > 0.5 else { return }
        lastEmitTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4
        let sampleStep = 8 // every 8th pixel

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
        onSample(total / Double(count))
    }
}
