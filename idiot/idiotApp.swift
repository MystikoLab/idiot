//
//  idiotApp.swift
//  idiot
//
//  Created by Umang on 26/7/26.
//

import SwiftData
import SwiftUI

@main
struct idiotApp: App {
    let container: ModelContainer

    init() {
        do {
            let configuration = ModelConfiguration(cloudKitDatabase: .private("iCloud.com.umangsurana.idiot"))
            container = try ModelContainer(for: Category.self, Transaction.self, RecurringRule.self, configurations: configuration)
            let context = ModelContext(container)
            DefaultCategories.seedIfNeeded(context: context)
            DefaultCategories.addMissingDefaults(context: context)
            DefaultCategories.reconcileDuplicates(context: context)
            RecurringEngine.materialize(context: context)
            CloudSyncMonitor.shared.start()
            #if os(macOS)
                MCPServerController.shared.configure(container: container)
            #endif
        } catch {
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
            #if os(macOS)
                .frame(minWidth: 880, idealWidth: 1120, minHeight: 620, idealHeight: 720)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AnalyticsCommands()
        }
        #endif
        .modelContainer(container)

        #if os(macOS)
            analyticsWindow
        #endif
    }

    #if os(macOS)
        private var analyticsWindow: some Scene {
            Window("Analytics", id: "analytics") {
                AnalyticsView()
            }
            .defaultSize(width: 880, height: 700)
            .modelContainer(container)
        }
    #endif
}

#if os(macOS)
    struct AnalyticsCommands: Commands {
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            CommandMenu("View") {
                Button("Analytics") {
                    openWindow(id: "analytics")
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
    }
#endif
