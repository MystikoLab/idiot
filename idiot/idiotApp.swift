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
    let container = AppModelContainer.shared
    #if os(macOS)
        @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    #endif

    init() {
        let context = ModelContext(container)
        DefaultCategories.seedIfNeeded(context: context)
        DefaultCategories.addMissingDefaults(context: context)
        DefaultCategories.reconcileDuplicates(context: context)
        RecurringEngine.materialize(context: context)
        QuickLogDrainer.drain(context: context)
        QuickLogDrainer.startObserving()
        CloudSyncMonitor.shared.start()
        OpeningBalance.start()
        NotificationManager.shared.configure(container: container)
        #if os(macOS)
            MCPServerController.shared.configure(container: container)
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
            #if os(macOS)
                .frame(minWidth: 880, idealWidth: 1120, minHeight: 620, idealHeight: 720)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AnalyticsCommands()
            ImportFromDevicesCommands()
        }
        #endif
        .modelContainer(container)

        #if os(macOS)
            analyticsWindow
            menuBarExtra
        #endif
    }

    #if os(macOS)
        private var menuBarExtra: some Scene {
            MenuBarExtra("Idiot", systemImage: "dollarsign.circle", isInserted: $showMenuBarExtra) {
                MenuBarView()
                    .modelContainer(container)
            }
            .menuBarExtraStyle(.window)
        }

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
