import DesignKit
import SwiftUI

@main
struct MailoIOSApp: App {
    @StateObject private var model = MailoAppModel.createLive()

    var body: some Scene {
        WindowGroup {
            MailoShell(model: model)
        }
    }
}
