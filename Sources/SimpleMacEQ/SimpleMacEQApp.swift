import SwiftUI

@main
struct SimpleMacEQApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            EQView(model: model)
        } label: {
            Image(systemName: model.isProcessing ? "slider.vertical.3" : "slider.horizontal.3")
        }
        .menuBarExtraStyle(.window)
    }
}
