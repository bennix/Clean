import SwiftUI
import Combine
import AppKit
import Darwin

private enum Planet: String, CaseIterable {
    case overview = "概览", clean = "清理", uninstall = "卸载", optimize = "优化", analyze = "分析", status = "状态"
    var icon: String { switch self { case .overview: "house"; case .clean: "externaldrive"; case .uninstall: "a.square"; case .optimize: "bolt"; case .analyze: "chart.pie"; case .status: "waveform.path.ecg" } }
    var color: Color { switch self { case .overview: .white; case .clean: .green; case .uninstall: .orange; case .optimize: .purple; case .analyze: .blue; case .status: .pink } }
}

struct ContentView: View {
    @ObservedObject private var diskAccess = DiskAccessManager.shared
    @State private var showDiskAccessGuide = false
    @State private var diskAccessGuideWasAutomatic = false
    @AppStorage("appearance") private var appearance = "dark"
    @State private var page: Planet = .overview
    @State private var entries: [DiskEntry] = []
    @State private var selected: Set<String> = []
    @State private var busy = false
    @State private var scanTask: Task<Void, Never>?
    @State private var scanID = UUID()
    @State private var scanCompleted = 0
    @State private var scanTotal = 0
    @State private var scanCancelled = false
    @State private var scanned = false
    @State private var skipped = 0
    @State private var scanIssues: [ScanIssue] = []
    @State private var message = ""
    @State private var confirm = false
    @State private var uninstallPlan: UninstallPlan?
    @State private var selectedRelated: Set<String> = []
    @State private var reviewTask: Task<Void, Never>?
    @State private var reviewID = UUID()
    @State private var allowSystemAuthorization = false
    @State private var removeDockEntries = true
    @State private var quitCleanupApplications = false
    @State private var folder = DiskService.home
    @State private var search = ""
    @State private var used: Int64 = 0
    @State private var capacity: Int64 = 0
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    private var background: Color { dark ? Color(red: 0.075, green: 0.09, blue: 0.115) : Color(red: 0.95, green: 0.96, blue: 0.98) }
    private var surface: Color { dark ? Color.white.opacity(0.045) : .white }
    private var visible: [DiskEntry] { entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search) } }
    private var total: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    private var selectionMode: ScanSelection.Mode { page == .analyze ? .analyze : page == .uninstall ? .uninstall : .clean }
    private var selectableVisibleIDs: Set<String> { ScanSelection.eligibleIDs(visible, mode: selectionMode) }
    private var chosen: [DiskEntry] { entries.filter { $0.isComplete && selected.contains($0.id) } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(.primary.opacity(0.06)).frame(width: 1)
            VStack(alignment: .leading, spacing: 24) {
                header
                if page == .overview { overview }
                else if page == .optimize { optimization }
                else if page == .status { status }
                else { filePage }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").foregroundStyle(.green)
                    Text("本机处理").foregroundStyle(.primary)
                    Text("·  先看清，再动手。所有删除均需确认。")
                    Spacer()
                    Button { diskAccess.automaticPromptRequested = false; diskAccessGuideWasAutomatic = false; showDiskAccessGuide = true } label: {
                        Label(diskAccess.state.title, systemImage: diskAccess.state == .limited ? "exclamationmark.shield" : "lock.shield")
                            .foregroundStyle(diskAccess.state == .limited ? Color.orange : Color.secondary)
                    }.buttonStyle(.plain).help("查看磁盘权限及授权步骤")
                    Text("Clean  1.1.2")
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(background)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .task { refreshDisk(); diskAccess.refresh(); presentDiskAccessIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in diskAccess.refresh() }
        .onChange(of: diskAccess.state) { _, state in
            if state == .accessible && diskAccessGuideWasAutomatic { showDiskAccessGuide = false; diskAccessGuideWasAutomatic = false }
        }
        .onChange(of: diskAccess.automaticPromptRequested) { _, _ in presentDiskAccessIfNeeded() }
        .onChange(of: scanIssues.contains { $0.kind == .permission }) { _, restricted in
            if restricted { diskAccess.reportDenied(scanIssues.filter { $0.kind == .permission }.map(\.url)) }
        }
        .onChange(of: uninstallPlan?.files.contains { $0.needsDiskAccess } ?? false) { _, restricted in
            if restricted { diskAccess.reportDenied(uninstallPlan?.files.filter { $0.needsDiskAccess }.map(\.url) ?? []) }
        }
        .sheet(isPresented: $showDiskAccessGuide) { DiskAccessGuide(access: diskAccess) }
        .sheet(isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } }), onDismiss: presentDiskAccessIfNeeded) {
            VStack(alignment: .leading, spacing: 18) {
                Text("操作结果").font(.title2.bold())
                ScrollView { Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 300)
                HStack { Button("复制结果") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message, forType: .string) }; Spacer(); Button("好") { message = "" }.keyboardShortcut(.defaultAction) }
            }.padding(26).frame(width: 650)
        }
        .sheet(isPresented: $confirm, onDismiss: { cancelReview(); presentDiskAccessIfNeeded() }) { confirmation }

    }

    private func presentDiskAccessIfNeeded() {
        guard diskAccess.automaticPromptRequested, diskAccess.state == .limited, !confirm, message.isEmpty, !showDiskAccessGuide else { return }
        diskAccess.automaticPromptRequested = false
        diskAccessGuideWasAutomatic = true
        showDiskAccessGuide = true
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Clean").font(.system(size: 34, weight: .semibold, design: .serif))
                Text(".").font(.system(size: 38, weight: .bold)).foregroundStyle(.orange)
            }.padding(.top, 22)
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.indigo, .orange.opacity(0.8), .blue], startPoint: .topTrailing, endPoint: .bottomLeading))
                    Image(systemName: "mountain.2.fill").font(.system(size: 29)).foregroundStyle(.white.opacity(0.8))
                }.frame(width: 60, height: 60)
                Text("Macintosh HD").font(.system(size: 13, weight: .medium))
                Text("\(formattedBytes(used)) / \(formattedBytes(capacity))").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
            VStack(spacing: 7) {
                ForEach(Planet.allCases, id: \.self) { item in
                    Button { cancelScan(); page = item; entries = []; selected = []; scanned = false; scanCancelled = false; scanIssues = []; skipped = 0; search = ""; if item == .status { NotificationCenter.default.post(name: .cleanShowStatus, object: nil) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).font(.system(size: 19)).foregroundStyle(item == .overview && !dark ? .primary : item.color).frame(width: 23)
                            Text(item.rawValue).font(.system(size: 13, weight: page == item ? .semibold : .regular))
                            Spacer()
                            if page == item { Image(systemName: "chevron.right").font(.system(size: 9)) }
                        }.padding(.horizontal, 12).padding(.vertical, 12)
                        .background(page == item ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(busy && scanTask == nil)
                }
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach([("light", "sun.max"), ("dark", "moon"), ("system", "desktopcomputer")], id: \.0) { value, icon in
                    Button { appearance = value } label: { Image(systemName: icon).frame(width: 32, height: 28).background(appearance == value ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain).help(value == "light" ? "浅色" : value == "dark" ? "深色" : "跟随系统")
                }
            }.padding(4).background(surface, in: RoundedRectangle(cornerRadius: 9))
            Text("五颗星球，各循其轨").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 18).padding(.bottom, 20).frame(width: 186).background(dark ? Color.black.opacity(0.15) : Color.white.opacity(0.5))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text(page == .overview ? "Storage Overview" : page.rawValue).font(.system(size: 28, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if scanTask != nil {
                ProgressView().controlSize(.small)
                Text("已统计 \(scanCompleted) / \(scanTotal) 项").font(.caption).foregroundStyle(.secondary)
                Button("取消扫描") { cancelScan() }
            } else if busy { ProgressView().controlSize(.small); Text("正在处理…").font(.caption).foregroundStyle(.secondary) }
            else if page != .status && page != .optimize {
                Button { if page == .overview { page = .analyze }; scan() } label: { Label(page == .overview ? "分析磁盘" : "重新扫描", systemImage: "waveform.path.ecg").padding(.horizontal, 10).padding(.vertical, 6) }.buttonStyle(.plain).background(dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(dark ? Color.black : Color.white)
            }
        }
    }
    private var subtitle: String {
        switch page {
        case .overview: "\(formattedBytes(used)) 已使用，共 \(formattedBytes(capacity)) · 你的 Mac，井然有序。"
        case .clean: "雨洗旧土，尘随潮去。扫描可识别的用户缓存与系统数据来源。"
        case .uninstall: "红尘覆旧，轻装再行。审查应用，移入系统废纸篓。"
        case .optimize: "近轨疾行，小修有声。明确每一步，再运行。"
        case .analyze: "远目成图，微处可见。选择文件夹，查看真实磁盘占用。"
        case .status: "光华不寐，心跳长明。每秒更新，保留最近 60 秒。"
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .leading, endPoint: .trailing)).frame(width: max(0, geo.size.width * Double(used) / Double(max(capacity, 1))))
                    Rectangle().fill(.primary.opacity(0.12))
                }.clipShape(RoundedRectangle(cornerRadius: 7))
            }.frame(height: 23)
            HStack {
                Label("已使用 \(formattedBytes(used))", systemImage: "circle.fill").foregroundStyle(.orange)
                Spacer()
                Text("可用 \(formattedBytes(max(0, capacity - used)))").foregroundStyle(.secondary)
            }.font(.system(size: 11))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                storageCard("Applications", "应用程序", "App 与关联文件", "a.square.fill", .orange, .uninstall)
                storageCard("Downloads", "下载文件", "查看下载文件夹", "arrow.down.square.fill", .blue, .analyze, "Downloads")
                storageCard("Large Files", "大型文件", "逐层查看磁盘占用", "doc.fill", .yellow, .analyze)
                storageCard("Caches", "缓存", "扫描后显示可清理大小", "externaldrive.fill", .green, .clean)
                storageCard("System Data", "系统数据", "缓存、日志、开发文件与备份", "gearshape.fill", .purple, .clean)
                storageCard("Live Status", "运行状态", "网速、温度、内存与系统心跳", "waveform.path.ecg", .gray, .status)
            }
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 25)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 7) {
                    Text("先看清，再动手").font(.system(size: 14, weight: .semibold))
                    Text("系统数据包含多种文件，不能整体删除。Clean 仅处理明确识别的位置，系统目录和未知路径会被拦下。扫描数据不会上传。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 10))
        }
    }
    private func storageCard(_ title: String, _ name: String, _ detail: String, _ icon: String, _ color: Color, _ destination: Planet, _ path: String? = nil) -> some View {
        Button {
            cancelScan(); page = destination; entries = []; scanned = false; scanCancelled = false; scanIssues = []; skipped = 0
            if let path { folder = DiskService.home.appendingPathComponent(path) }
            if destination == .status { NotificationCenter.default.post(name: .cleanShowStatus, object: nil) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [color.opacity(0.86), color.opacity(0.32), color.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)).background(Color(red: 0.08, green: 0.09, blue: 0.12), in: RoundedRectangle(cornerRadius: 10))
                Wave().stroke(color.opacity(0.8), lineWidth: 2).frame(width: 155, height: 43).padding(.bottom, 5)
                Wave(filled: true).fill(LinearGradient(colors: [color.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)).frame(width: 155, height: 43)
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.system(size: 28, weight: .medium)).frame(width: 58, height: 61).background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                        Text(name).font(.system(size: 23, weight: .medium))
                        Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }.padding(17)
            }.frame(height: 126).foregroundStyle(.white).contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(busy && scanTask == nil)
    }

    private var filePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if page == .analyze {
                HStack {
                    Button("选择文件夹…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK, let url = panel.url { folder = url; scan() } }
                    Button { folder.deleteLastPathComponent(); scan() } label: { Image(systemName: "arrow.up") }
                    Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }.disabled(busy && scanTask == nil)
            }
            if scanTask != nil {
                ProgressView(value: Double(scanCompleted), total: Double(max(1, scanTotal))).tint(page.color)
                Text("后台并行扫描，结果持续更新。目录大小需遍历文件；最多同时统计 4 项。").font(.caption).foregroundStyle(.secondary)
            } else if scanCancelled {
                Text("扫描已取消，以下仅为已完成部分；可点击重新扫描。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(scanned ? "\(entries.count) 项 · \(formattedBytes(total))\(scanTask != nil || scanCancelled ? "（已统计）" : "")" : (scanTask != nil ? "正在列出项目…" : "等待扫描")).font(.system(size: 17, weight: .medium))
                Spacer()
                TextField("搜索名称或类别", text: $search).textFieldStyle(.roundedBorder).frame(width: 210)
            }
            if !scanned && !busy {
                VStack(spacing: 18) {
                    Image(systemName: page.icon).font(.system(size: 56, weight: .ultraLight)).foregroundStyle(page.color)
                    Text(page == .clean ? "给 Mac 腾出一点空间" : page == .uninstall ? "与不再使用的应用告别" : "让每一层大小清晰可见").font(.title2)
                    Text("扫描只读取文件信息，不会删除任何文件。").foregroundStyle(.secondary)
                    Button("开始扫描") { scan() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(45)
            } else {
                if page == .analyze && !entries.isEmpty {
                    DiskTreemap(entries: entries, action: enter)
                        .frame(height: 185)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { entry in
                            let disabledReason = ScanSelection.disabledReason(entry, mode: selectionMode)
                            HStack(spacing: 12) {
                                Toggle("选择 " + entry.name, isOn: Binding(get: { selected.contains(entry.id) }, set: { if $0 { selected.insert(entry.id) } else { selected.remove(entry.id) } })).labelsHidden().disabled(busy || disabledReason != nil).help(busy ? "扫描或处理进行中，请稍候" : disabledReason ?? "选择此项目进行审查")
                                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(entry.category + (entry.sensitive ? " · 个人数据，请仔细确认" : "") + " · " + entry.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    if page == .analyze, let disabledReason {
                                        Text(disabledReason).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                if page == .uninstall { AppUsageColumns(url: entry.url) }
                                Text(entry.isComplete ? formattedBytes(entry.bytes) + (entry.isPartial ? "（不完整）" : "") : "等待统计…").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                if page == .analyze { Button { enter(entry) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain) }
                            }.padding(12).background(surface.opacity(0.7))
                            .contextMenu {
                                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                                if page == .analyze {
                                    Button("打开") { enter(entry) }
                                    Button("审查并移入废纸篓…", role: .destructive) { selected = [entry.id]; confirm = true }.disabled(busy || disabledReason != nil)
                                }
                            }
                            Divider().opacity(0.35)
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 9))
                if entries.isEmpty && !busy { Text("没有找到可访问的项目。可在系统设置中检查文件访问权限。").foregroundStyle(.secondary) }
                if !scanIssues.isEmpty { scanIssueDetails }
                HStack {
                    Text(skipped == 0 ? "未发现读取错误" : "\(skipped) 项已跳过 · 详情见上方").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(search.isEmpty ? "全选" : "全选搜索结果") { selected.formUnion(selectableVisibleIDs) }
                        .disabled(busy || selectableVisibleIDs.isEmpty || selectableVisibleIDs.isSubset(of: selected))
                    Button("取消全选") { selected = [] }.disabled(busy || selected.isEmpty)
                    Button("审查 \(chosen.count) 项 · \(formattedBytes(chosen.reduce(0) { $0 + $1.bytes }))") {
                        if page == .uninstall { reviewUninstall() }
                        else { confirm = true }
                    }.buttonStyle(.borderedProminent).disabled(chosen.isEmpty || busy)
                }
            }
        }.frame(maxHeight: .infinity)
    }
    private var scanIssueDetails: some View {
        DisclosureGroup("查看扫描详情（\(skipped) 项）") {
            VStack(alignment: .leading, spacing: 8) {
                Text("不存在的目录通常表示未安装对应软件；权限不足会导致统计大小偏低。扫描会继续处理其余目录。").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(Dictionary(scanIssues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values).sorted { $0.id < $1.id }) { issue in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(issue.kind.rawValue + " · " + issue.url.path).font(.caption).textSelection(.enabled)
                                Text(issue.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxHeight: 110)
                if scanIssues.contains(where: { $0.kind == .permission }) {
                    Button("打开完全磁盘访问权限设置…") {
                        diskAccess.openSettings()
                    }
                    Text("将当前 Clean.app 添加到列表并开启权限，然后退出、重新打开 Clean 再扫描。部分系统保护位置仍不可访问。").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.top, 8)
        }.font(.caption)
    }
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(page == .uninstall ? "审查应用与关联文件" : "最后确认一下").font(.title2.bold())
            Text(page == .uninstall ? "所选应用与勾选的关联文件将移入废纸篓。含个人数据的目录默认不勾选；仍被其他应用使用的共享容器和系统服务会保留。" : page == .analyze ? "所选文件或文件夹将移入系统废纸篓，可从废纸篓恢复。请仔细核对路径和大小；受保护位置、未完成或无法完整统计的项目不会加入全选。" : "普通缓存和日志将永久删除；标记个人数据或共享容器的项目将移入废纸篓。请先退出相关应用。缓存会重新生成，大小不等于实际释放空间。")
                .font(.callout)
            if page == .analyze {
                Text("虚拟机、模型、备份及开发文件可能包含重要数据。请先停止相关应用或虚拟机；移除数据可能导致容器、镜像、卷或离线模型不可用。清空废纸篓后才会释放空间。")
                    .font(.callout).foregroundStyle(.orange)
            }
            if page == .uninstall && reviewTask != nil {
                HStack { ProgressView().controlSize(.small); Text("并行统计关联文件：\(uninstallPlan?.completed ?? 0) / \(uninstallPlan?.files.count ?? 0)").font(.caption) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(chosen) { entry in
                        Label { Text(entry.url.path + " · " + formattedBytes(entry.bytes)).textSelection(.enabled) } icon: { Image(systemName: "app.fill") }.font(.caption)
                    }
                    if page == .uninstall, let plan = uninstallPlan {
                        ForEach(plan.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                        Divider()
                        ForEach(plan.files) { file in
                            HStack(alignment: .top) {
                                Toggle("", isOn: Binding(get: { selectedRelated.contains(file.id) }, set: { if $0 { selectedRelated.insert(file.id) } else { selectedRelated.remove(file.id) } })).labelsHidden().disabled(!file.allowed)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.category + " · " + file.url.path).font(.caption).textSelection(.enabled)
                                    Text(file.note + (file.containsData ? " · 含个人数据，默认保留" : "")).font(.caption2).foregroundStyle(.secondary)
                                    if let issue = file.issue { Text(issue).font(.caption2).foregroundStyle(.orange) }
                                }
                                Spacer()
                                Text(file.isComplete ? formattedBytes(file.bytes) : "统计中…").font(.caption)
                            }
                        }
                        if plan.files.isEmpty { Text("未找到明确关联的文件；不会猜测或删除未知目录。").font(.caption).foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 300)
            if page == .uninstall {
                if !(uninstallPlan?.dockApps.isEmpty ?? true) {
                    Toggle("移除所选应用的 Dock 图标（会刷新 Dock）", isOn: $removeDockEntries).font(.caption)
                }
                Toggle("权限不足时请求 Finder 系统授权", isOn: $allowSystemAuthorization).font(.caption)
                Text("可能弹出“允许 Clean 控制 Finder”或管理员验证。隐私目录仍需完全磁盘访问权限；拒绝授权的项目会列出失败原因。密码由 macOS 处理。").font(.caption2).foregroundStyle(.secondary)
                Button("打开完全磁盘访问权限设置…") {
                    diskAccess.openSettings()
                }.font(.caption)
            }
            if page == .clean {
                Picker("遇到运行中的应用", selection: $quitCleanupApplications) {
                    Text("跳过运行中项目").tag(false)
                    Text("退出相关应用后清理").tag(true)
                }
                Text("仅正常退出相关第三方桌面应用与 Safari，最多等待 8 秒；请先保存工作。其他系统应用、后台服务、命令行任务以及未退出的应用会跳过，不会强制结束进程。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button("取消") { cancelReview(); confirm = false }
                Spacer()
                Button("确认处理 \(chosen.count + (page == .uninstall ? selectedRelated.count : 0)) 项", role: .destructive) { performDelete() }
                    .buttonStyle(.borderedProminent).tint(.red).disabled(reviewTask != nil)
            }
        }.padding(28).frame(width: 760)
    }
    private func cancelReview() {
        reviewTask?.cancel(); reviewTask = nil; reviewID = UUID()
    }
    private func reviewUninstall() {
        cancelReview(); uninstallPlan = nil; selectedRelated = []; allowSystemAuthorization = false
        let token = UUID(); reviewID = token
        let apps = chosen
        confirm = true
        reviewTask = Task {
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                await UninstallService.prepare(apps) { plan in
                    await MainActor.run {
                        guard reviewID == token else { return }
                        if uninstallPlan == nil { selectedRelated = Set(plan.files.filter { $0.allowed && !$0.containsData && $0.issue == nil }.map(\.id)) }
                        uninstallPlan = plan
                    }
                }
            }
            let plan = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, reviewID == token else { return }
            uninstallPlan = plan; reviewTask = nil
        }
    }
    private func cancelScan() {
        guard scanTask != nil else { return }
        scanTask?.cancel()
        scanID = UUID()
        scanTask = nil
        busy = false
        scanCancelled = true
    }
    private func scan() {
        cancelScan()
        busy = true; selected = []; entries = []; skipped = 0; scanIssues = []
        scanned = false; scanCancelled = false; scanCompleted = 0; scanTotal = 0
        let token = UUID(); scanID = token
        let target = page; let location = folder
        scanTask = Task {
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                let discovery = target == .clean ? CleanupCatalog.discover() : nil
                let roots = discovery?.rules.map(\.scanRoot) ?? (target == .uninstall ? DiskService.applicationRoots : [ScanRoot(url: location, category: "文件")])
                return await DiskService.scanConcurrently(roots, initialIssues: discovery?.issues ?? []) { progress in
                    await MainActor.run {
                        guard scanID == token else { return }
                        entries = progress.result.entries; skipped = progress.result.skipped; scanIssues = progress.result.issues
                        scanCompleted = progress.completed; scanTotal = progress.total; scanned = true
                    }
                }
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, scanID == token else { return }
            entries = result.entries; skipped = result.skipped; scanIssues = result.issues
            scanned = true; busy = false; scanTask = nil
        }
    }
    private func enter(_ entry: DiskEntry) {
        if (try? entry.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { folder = entry.url; scan() }
        else { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
    }
    private func performDelete() {
        let targets = chosen; let plan = uninstallPlan; let ids = selectedRelated
        let quitApps = quitCleanupApplications
        let authorization = allowSystemAuthorization; let dock = removeDockEntries; let uninstall = page == .uninstall; let analysis = page == .analyze
        confirm = false; busy = true
        Task {
            message = await Task.detached {
                if analysis { return DiskService.trashAnalyzed(targets) }
                if !uninstall { return await DiskService.remove(targets, quitApplications: quitApps) }
                guard let plan else { return "未生成卸载审查列表，请重新扫描。" }
                return await UninstallService.execute(plan, selected: ids, systemAuthorization: authorization, removeDockEntries: dock) { url in
                    await MainActor.run { FinderAuthorization.trash(url) }
                }
            }.value
            busy = false; scan(); refreshDisk()
        }
    }
    private func refreshDisk() {
        if let values = try? FileManager.default.attributesOfFileSystem(forPath: "/") { capacity = (values[.systemSize] as? NSNumber)?.int64Value ?? 0; used = capacity - ((values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0) }
    }
    private var optimization: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("系统维护").font(.title2)
            Text("管理员维护由 macOS 弹出授权。不会保存密码。索引重建可能暂时增加 CPU 使用率。").font(.callout).foregroundStyle(.secondary)
            ForEach([("dns", "刷新 DNS", "清除 DNS 缓存，并通知系统重新加载。", "network"), ("index", "重建 Spotlight 索引", "重新索引启动磁盘，完成时间由系统决定。", "magnifyingglass"), ("snapshots", "查看本地快照", "只列出 Time Machine 快照，不删除备份。", "clock.arrow.circlepath")], id: \.0) { id, title, detail, icon in
                HStack(spacing: 16) {
                    Image(systemName: icon).font(.title2).foregroundStyle(.purple).frame(width: 34)
                    VStack(alignment: .leading, spacing: 7) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("运行") { maintenance(id) }.disabled(busy)
                }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("仅提供已实现且可核实的维护任务。系统缓存、交换文件和受保护系统目录不会直接删除。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func maintenance(_ id: String) {
        busy = true
        Task {
            message = await Task.detached {
                let command = id == "dns" ? "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder" : id == "index" ? "/usr/bin/mdutil -E /" : "/usr/bin/tmutil listlocalsnapshots /"
                let script = NSAppleScript(source: "do shell script \"\(command)\"" + (id == "snapshots" ? "" : " with administrator privileges"))
                var error: NSDictionary?
                let output = script?.executeAndReturnError(&error).stringValue ?? ""
                if let error { return "操作未完成：\(error)" }
                return output.isEmpty ? "任务已提交给 macOS。" : output
            }.value
            busy = false
        }
    }
    private var status: some View {
        StatusDashboard(monitor: .shared)
    }

}

private struct Wave: Shape {
    var filled = false
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: 0, y: r.height))
        p.addCurve(to: CGPoint(x: r.width * 0.58, y: r.height * 0.35), control1: CGPoint(x: r.width * 0.25, y: r.height), control2: CGPoint(x: r.width * 0.37, y: -r.height * 0.1))
        p.addCurve(to: CGPoint(x: r.width, y: r.height * 0.1), control1: CGPoint(x: r.width * 0.8, y: r.height * 0.8), control2: CGPoint(x: r.width * 0.88, y: 0))
        if filled { p.addLine(to: CGPoint(x: r.width, y: r.height)); p.closeSubpath() }; return p
    }
}

private struct DiskTreemap: View {
    let entries: [DiskEntry]
    let action: (DiskEntry) -> Void
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles(entries.filter { $0.bytes > 0 }, in: CGRect(origin: .zero, size: geo.size)).enumerated()), id: \.element.0.id) { index, tile in
                    Button { action(tile.0) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if tile.1.width >= 70 && tile.1.height >= 45 {
                                Text(tile.0.name).font(.system(size: 11, weight: .medium)).lineLimit(2)
                                if tile.1.height >= 65 { Text(formattedBytes(tile.0.bytes)).font(.system(size: 10)).opacity(0.8) }
                            }
                            Spacer(minLength: 0)
                        }.padding(8).frame(width: max(0, tile.1.width - 3), height: max(0, tile.1.height - 3), alignment: .topLeading)
                            .background([Color.blue, .teal, .purple, .orange, .indigo][index % 5].gradient)
                            .clipped().foregroundStyle(.white)
                    }.buttonStyle(.plain).offset(x: tile.1.minX, y: tile.1.minY).help(tile.0.url.path + " · " + formattedBytes(tile.0.bytes))
                }
            }.frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
    private func tiles(_ items: [DiskEntry], in rect: CGRect) -> [(DiskEntry, CGRect)] {
        guard !items.isEmpty else { return [] }
        guard items.count > 1 else { return [(items[0], rect)] }
        let total = items.reduce(Int64(0)) { $0 + $1.bytes }
        var prefix: Int64 = 0
        var split = 1
        for index in 0..<(items.count - 1) {
            prefix += items[index].bytes; split = index + 1
            if prefix >= total / 2 { break }
        }
        let fraction = Double(prefix) / Double(max(1, total))
        let first: CGRect; let second: CGRect
        if rect.width > rect.height {
            let width = rect.width * fraction
            first = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            second = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            let height = rect.height * fraction
            first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
            second = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
        return tiles(Array(items.prefix(split)), in: first) + tiles(Array(items.dropFirst(split)), in: second)
    }
}
