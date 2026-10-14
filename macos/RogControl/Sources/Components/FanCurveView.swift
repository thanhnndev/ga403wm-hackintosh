// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Charts
import SwiftUI

/// The firmware fan curve for CPU or GPU. A reference, not live RPM.
struct FanCurveView: View {
    let laptop: LaptopModel
    @State private var fan = 0
    @State private var hovered: Int?

    private var bytes: [UInt8]? { fan == 0 ? laptop.cpuCurve : laptop.gpuCurve }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(laptop.curveBase.title) firmware curve")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Fan", selection: $fan) {
                    Text("CPU").tag(0)
                    Text("GPU").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }
            if let bytes {
                chart(FanCurveData(bytes))
            } else {
                ContentUnavailableView("Fan curve unavailable", systemImage: "fan.slash",
                                       description: Text("The firmware did not return a curve."))
            }
        }
    }

    @ViewBuilder
    private func chart(_ data: FanCurveData) -> some View {
        if data.points.isEmpty {
            ContentUnavailableView("No valid fan curve data", systemImage: "chart.line.downtrend.xyaxis")
        } else {
            let selected = data.points.first { $0.id == hovered }
            Text(selected.map { "\($0.temperature)°C at \($0.duty)% fan duty" } ?? "Hover a point to read it")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Chart(data.points) { point in
                LineMark(x: .value("Temperature", point.temperature), y: .value("Fan duty", point.duty),
                         series: .value("Segment", point.segment))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .foregroundStyle(Theme.accent)
                PointMark(x: .value("Temperature", point.temperature), y: .value("Fan duty", point.duty))
                    .symbolSize(point.id == hovered ? 110 : 40)
                    .foregroundStyle(Theme.accent)
            }
            .chartXScale(domain: 20...105)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [20, 40, 60, 80, 100]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)°") } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(.rect)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let frame = proxy.plotFrame else { return }
                                let origin = geometry[frame].origin
                                let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                                hovered = data.points.min { distance($0, to: local, proxy) < distance($1, to: local, proxy) }?.id
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }
            .frame(height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fan duty by temperature")
            .accessibilityValue(data.points.map { "\($0.temperature) degrees Celsius, \($0.duty) percent" }.joined(separator: "; "))
            if data.omitted > 0 {
                Text("\(data.omitted) firmware point(s) outside the valid range or order are not plotted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func distance(_ point: FanCurvePoint, to position: CGPoint, _ proxy: ChartProxy) -> CGFloat {
        guard let x = proxy.position(forX: point.temperature), let y = proxy.position(forY: point.duty) else { return .infinity }
        return (x - position.x) * (x - position.x) + (y - position.y) * (y - position.y)
    }
}
