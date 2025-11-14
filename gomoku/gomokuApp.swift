//
//  gomokuApp.swift
//  gomoku
//
//  Created by Li Zheng on 11/11/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct GomokuApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Allow only portrait; include `.portraitUpsideDown` as needed.
        return .portrait
    }
}
#endif

#Preview {
    ContentView()
}
