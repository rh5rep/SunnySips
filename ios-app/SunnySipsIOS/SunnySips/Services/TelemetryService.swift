import Foundation

enum TelemetryService {
    static func track(_ event: String, properties: [String: String] = [:]) {
#if DEBUG
        if properties.isEmpty {
            print("Telemetry event=\(event)")
        } else {
            print("Telemetry event=\(event) properties=\(properties)")
        }
#endif
    }
}

