//
//  ProofKit_iOS_exampleApp.swift
//  ProofKit-iOS-example
//
//  Created by Georgi Popov on 18.05.26.
//

import SwiftUI
import CoreData

@main
struct ProofKit_iOS_exampleApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
