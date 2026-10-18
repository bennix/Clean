import SwiftUI
import Combine
import Sparkle

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    private let controller: SPUStandardUpdaterController
    private var observation: AnyCancellable?
    @Published private(set) var canCheck = false
    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }
    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).sink { [weak self] in self?.canCheck = $0 }
    }
    func check() { controller.checkForUpdates(nil) }
}

struct UpdateControls: View {
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"
    @ObservedObject private var updates = UpdateService.shared
    var body: some View {
        let _ = language
        VStack(alignment: .leading, spacing: 8) {
            Button { updates.check() } label: { Label(L("检查更新…"), systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(.plain).disabled(!updates.canCheck)
            Toggle(L("自动检查更新"), isOn: Binding(get: { updates.automaticChecks }, set: { updates.automaticChecks = $0 }))
                .toggleStyle(.checkbox)
        }.font(.system(size: 10)).frame(maxWidth: .infinity, alignment: .leading)
    }
}
