//
//  AppSettings.swift
//  App-wide settings and preferences
//

import Foundation
import SwiftUI

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("skipCodeFiles") var skipCodeFiles: Bool = true
    @AppStorage("skipImages") var skipImages: Bool = false

    // File size limit in bytes (default: 10 MB)
    @AppStorage("maxFileSizeBytes") var maxFileSizeBytes: Int = 10_485_760

    // Maximum total database size in bytes (default: 1 GB)
    @AppStorage("maxDatabaseSizeBytes") var maxDatabaseSizeBytes: Int = 1_073_741_824

    private init() {}
}
