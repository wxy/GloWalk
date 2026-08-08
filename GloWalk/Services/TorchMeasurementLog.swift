import Foundation

enum TorchMeasurementLog {
    /// One CSV row: ts,torch,full,roi,pitch,active,ambient
    static func row(timestamp: Date, torchLevel: Double,
                    fullFrame: Double, roi: Double,
                    pitch: Double, active: Bool,
                    ambient: Double) -> String {
        let ts = String(format: "%.3f", timestamp.timeIntervalSinceReferenceDate)
        return [ts,
                String(format: "%.3f", torchLevel),
                String(format: "%.4f", fullFrame),
                String(format: "%.4f", roi),
                String(format: "%.1f", pitch),
                active ? "1" : "0",
                String(format: "%.4f", ambient)].joined(separator: ",")
    }
}
