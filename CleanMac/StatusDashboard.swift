import SwiftUI

struct StatusDashboard: View {
    @ObservedObject var monitor: SystemMonitor
    var compact = false
    @AppStorage("appearance") private var appearance = "dark"
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if compact {
                    HStack {
                        Image(systemName: "waveform.path.ecg").foregroundStyle(.green)
                        Text("Clean").font(.system(size: 20, weight: .semibold))
                        Spacer()
                        Label("实时状态", systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    chart("CPU", monitor.cpuAvailable ? percent(monitor.cpu.last) : "采样中…", detail: "\(ProcessInfo.processInfo.processorCount) 核心 · 系统总使用率", values: monitor.cpu, color: .blue, ceiling: 100)
                    chart("内存", monitor.memoryAvailable ? percent(monitor.memory.last) : "不可用", detail: "\(bytes(monitor.memoryUsed)) / \(bytes(monitor.memoryTotal))", values: monitor.memory, color: .green, ceiling: 100)
                    chart("下载速度 ↓", monitor.networkAvailable ? speed(monitor.download.last) : "采样中…", detail: monitor.networkInterfaces, values: monitor.download, color: .cyan)
                    chart("上传速度 ↑", monitor.networkAvailable ? speed(monitor.upload.last) : "采样中…", detail: "物理网卡合计 · 字节/秒", values: monitor.upload, color: .purple)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label("磁盘容量", systemImage: "internaldrive"); Spacer(); Text(monitor.diskAvailable ? "\(formattedBytes(monitor.diskTotal - monitor.diskFree)) 已用" : "不可用").foregroundStyle(.secondary) }.font(.caption)
                    ProgressView(value: Double(max(0, monitor.diskTotal - monitor.diskFree)), total: Double(max(1, monitor.diskTotal))).tint(.orange)
                    HStack { Text("可用 \(formattedBytes(monitor.diskFree))"); Spacer(); Text("总量 \(formattedBytes(monitor.diskTotal))") }.font(.caption2).foregroundStyle(.secondary)
                }.padding(14).background(tile, in: RoundedRectangle(cornerRadius: 10))
                VStack(spacing: 0) {
                    row("温度", monitor.temperature.map { String(format: "%.1f °C · 传感器最高值", $0) } ?? "当前接口未返回读数", "thermometer.medium")
                    if !monitor.temperatures.isEmpty {
                        DisclosureGroup("查看 \(monitor.temperatures.count) 个温度传感器") {
                            VStack(spacing: 0) {
                                ForEach(monitor.temperatures) { sensor in
                                    row(sensor.name, String(format: "%.1f °C", sensor.celsius), "thermometer")
                                }
                            }
                        }.font(.system(size: 11)).padding(.vertical, 6)
                    }
                    row("系统热状态", monitor.thermal, "flame")
                    row("GPU 使用率", monitor.gpu.map { String(format: "%.1f%%", $0) } ?? "当前接口未返回读数", "cpu")
                    row("电池", monitor.battery.map { String(format: "%.0f%% · ", $0) + monitor.power } ?? monitor.power, "battery.100")
                    row("压缩内存 / 交换", "\(bytes(monitor.compressed)) / \(bytes(monitor.swap))", "memorychip")
                    row("负载 1 / 5 / 15 分钟", monitor.load.map { String(format: "%.2f", $0) }.joined(separator: " / "), "chart.line.uptrend.xyaxis")
                    row("运行时间", Duration.seconds(monitor.uptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated)), "clock")
                }.padding(.horizontal, 14).background(tile, in: RoundedRectangle(cornerRadius: 10))
                Text("曲线保留最近 60 次采样，每秒更新；磁盘、电源和硬件传感器每 5 秒更新。温度为 IOHID / IOHWSensor 实测最高值，可展开查看芯片、电池、SSD 等传感器；各机型支持不同，读取失败不会显示估算数值。").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if compact {
                    Divider()
                    HStack {
                        Button("打开主窗口") { NotificationCenter.default.post(name: .cleanOpenWindow, object: nil) }.buttonStyle(.borderedProminent)
                        Spacer()
                        Button("退出 Clean") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                } else {
                    Button { NotificationCenter.default.post(name: .cleanShowStatus, object: nil) } label: { Label("收起到菜单栏", systemImage: "menubar.arrow.up.rectangle") }
                }
            }.padding(compact ? 18 : 2)
        }
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .task { monitor.start() }
    }
    private var tile: Color { scheme == .dark ? .white.opacity(0.055) : .black.opacity(0.035) }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory) }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "采样中…" }
    private func speed(_ value: Double?) -> String { value.map { formattedBytes(Int64(max(0, $0))) + "/s" } ?? "采样中…" }
    private func row(_ name: String, _ value: String, _ icon: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(name, systemImage: icon).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: 11)).padding(.vertical, 10)
    }
    private func chart(_ title: String, _ value: String, detail: String, values: [Double], color: Color, ceiling: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: compact ? 23 : 30, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            GeometryReader { geo in
                let maximum = ceiling ?? max(1, values.max() ?? 1)
                Path { path in
                    for (i, sample) in values.enumerated() {
                        let point = CGPoint(x: geo.size.width * Double(i) / 59, y: geo.size.height * (1 - min(1, max(0, sample / maximum))))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }.frame(height: compact ? 30 : 48).accessibilityHidden(true)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(tile, in: RoundedRectangle(cornerRadius: 10))
    }
}
