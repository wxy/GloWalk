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
    private var occlusionTimer: Timer?
    private var lastAmbientUpdate: Date = .distantPast

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
        startOcclusionDetection()
    }

    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
        occlusionTimer?.invalidate()
        occlusionTimer = nil
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

        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(
            AmbientLightDelegate { [weak self] level in
                Task { @MainActor in
                    self?.ambientLightLevel = level
                    self?.lastAmbientUpdate = Date()
                }
            },
            queue: DispatchQueue(label: "glowalk.ambient", qos: .utility)
        )
        session.addOutput(output)
        captureSession = session
        let sessionToStart = session
        DispatchQueue.global(qos: .userInitiated).async {
            sessionToStart.startRunning()
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

    // MARK: - Occlusion Detection

    private func startOcclusionDetection() {
        occlusionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkOcclusion() }
        }
    }

    private func checkOcclusion() {
        // If ambient light is extremely high (flash reflecting off a near surface)
        // and hasn't changed significantly in ~10 seconds, likely occluded
        let level = ambientLightLevel
        let timeSinceUpdate = Date().timeIntervalSince(lastAmbientUpdate)

        if isManualMode {
            isOccluded = false
        } else if level > 0.85 && timeSinceUpdate < 3.0 {
            isOccluded = true
        } else if level < 0.05 && timeSinceUpdate < 3.0 {
            // Extremely dark — probably pointing at empty sky or space
            // This is a valid scenario, not occlusion
            isOccluded = false
        } else {
            isOccluded = false
        }
    }
}

// MARK: - Camera Frame Delegate

private final class AmbientLightDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onSample: (Double) -> Void
    private var lastEmitTime: Date = .distantPast

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
        let avg = total / Double(count)
        onSample(avg)
    }
}
