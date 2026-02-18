import SwiftUI

struct QuarterHourDatePicker: UIViewRepresentable {
    @Binding var selection: Date
    let range: ClosedRange<Date>

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 15
        picker.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        picker.locale = Locale(identifier: "en_DK")
        picker.minimumDate = range.lowerBound
        picker.maximumDate = range.upperBound
        picker.addTarget(context.coordinator, action: #selector(Coordinator.onChange(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        uiView.minimumDate = range.lowerBound
        uiView.maximumDate = range.upperBound
        let rounded = clampedToRange(selection)
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
            selection = sender.date
        }
    }

    private func clampedToRange(_ date: Date) -> Date {
        let rounded = date.roundedDownToQuarterHour()
        if rounded < range.lowerBound { return range.lowerBound.roundedDownToQuarterHour() }
        if rounded > range.upperBound { return range.upperBound.roundedDownToQuarterHour() }
        return rounded
    }
}
