import SwiftUI

struct QuarterHourDatePicker: UIViewRepresentable {
    @Binding var selection: Date
    let range: ClosedRange<Date>

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 15
        picker.minimumDate = range.lowerBound
        picker.maximumDate = range.upperBound
        picker.addTarget(context.coordinator, action: #selector(Coordinator.onChange(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        uiView.minimumDate = range.lowerBound
        uiView.maximumDate = range.upperBound
        let rounded = selection.clampedToToday().roundedToQuarterHour()
        if abs(uiView.date.timeIntervalSince(rounded)) > 1 {
            uiView.setDate(rounded, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        @Binding var selection: Date

        init(selection: Binding<Date>) {
            _selection = selection
        }

        @objc func onChange(_ sender: UIDatePicker) {
            selection = sender.date.clampedToToday().roundedToQuarterHour()
        }
    }
}
