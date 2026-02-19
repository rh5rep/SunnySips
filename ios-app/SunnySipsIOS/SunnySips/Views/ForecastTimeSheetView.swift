import SwiftUI

struct ForecastTimeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SunnySipsViewModel

    @State private var draftTime: Date

    init(viewModel: SunnySipsViewModel) {
        self.viewModel = viewModel
        let base = viewModel.filters.useNow ? Date() : viewModel.filters.selectedTime
        _draftTime = State(initialValue: base)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    QuarterHourDatePicker(
                        selection: $draftTime,
                        range: viewModel.predictionRange
                    )
                    .frame(width: 320, height: 200, alignment: .center)
                    .clipped()
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .timePillStyle(.muted)
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.setForecastTime(draftTime)
                        dismiss()
                    } label: {
                        Text("Apply")
                            .timePillStyle(.primary)
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .navigationTitle("Select Forecast Time")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: viewModel.predictionRange) { _, newRange in
                draftTime = clamp(draftTime, to: newRange)
            }
        }
    }

    private func clamp(_ date: Date, to range: ClosedRange<Date>) -> Date {
        if date < range.lowerBound { return range.lowerBound }
        if date > range.upperBound { return range.upperBound }
        return date
    }
}
