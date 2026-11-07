import DesignKit
import SwiftUI

@main
struct MailoMacApp: App {
    @StateObject private var model = MailoAppModel.createLive()

    var body: some Scene {
        WindowGroup {
            MailoShell(model: model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
    }
}
