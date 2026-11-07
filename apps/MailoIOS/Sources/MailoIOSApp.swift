import DesignKit
import SwiftUI

@main
struct MailoIOSApp: App {
    @StateObject private var model = MailoAppModel.bootstrapDemo()

    var body: some Scene {
        WindowGroup {
            MailoShell(model: model)
        }
    }
}
