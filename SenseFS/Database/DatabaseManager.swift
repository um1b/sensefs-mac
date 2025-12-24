//
//  DatabaseManager.swift
//  SQLite3 database manager using native C API
//

import Foundation
import SQLite3

/// Manages SQLite database connection and schema
actor DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let dbPath: String
    private let currentSchemaVersion = 2 // Increment when schema changes

    private init() {
        // Store in Application Support directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dbDirectory = appSupport.appendingPathComponent("com.sensefs.app")

        // Create directory if needed
        try? fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)

        dbPath = dbDirectory.appendingPathComponent("vector_database.sqlite").path

        print("📦 Database path: \(dbPath)")

        Task {
            await openDatabase()
            await createSchema()
        }
    }

    // MARK: - Database Lifecycle

    private func openDatabase() async {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("✅ Database opened successfully")
            // Performance pragmas are set in schema.sql during createSchema()
        } else {
            print("❌ Failed to open database")
        }
    }

    private func createSchema() async {
        // Load schema from .sql file
        var schemaSQL: String?

        // Try multiple possible bundle locations
        if let schemaURL = Bundle.main.url(forResource: "schema", withExtension: "sql"),
           let sql = try? String(contentsOf: schemaURL, encoding: .utf8) {
            schemaSQL = sql
            print("✅ Loaded schema from schema.sql")
        } else if let schemaURL = Bundle.main.url(forResource: "schema", withExtension: "sql", subdirectory: "Database"),
                  let sql = try? String(contentsOf: schemaURL, encoding: .utf8) {
            schemaSQL = sql
            print("✅ Loaded schema from Database/schema.sql")
        }

        guard let sql = schemaSQL else {
            print("❌ Failed to load schema.sql - database initialization failed")
            print("   Make sure schema.sql is added to the Xcode project target")
            return
        }

        // Split SQL statements by semicolon and execute each
        let statements = sql.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }

        for statement in statements {
            let trimmedStatement = statement.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmedStatement.isEmpty else { continue }

            var error: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, trimmedStatement, nil, nil, &error) != SQLITE_OK {
                if let error = error {
                    let errorMessage = String(cString: error)
                    print("⚠️ Schema execution warning: \(errorMessage)")
                    sqlite3_free(error)
                }
            }
        }

        print("✅ Database schema ready")

        // Migrate existing data: add columns if they don't exist
        await migrateSchema()
    }

    private func migrateSchema() async {
        let version = getSchemaVersion()
        print("📊 Current schema version: \(version)")

        // Migration v1 → v2: Add modified_at and file_size columns
        if version < 2 {
            print("🔄 Migrating schema from v\(version) to v2...")

            var error: UnsafeMutablePointer<CChar>?

            // Add modified_at column
            let addModifiedAtSQL = "ALTER TABLE documents ADD COLUMN modified_at REAL DEFAULT 0;"
            if sqlite3_exec(db, addModifiedAtSQL, nil, nil, &error) != SQLITE_OK {
                // Column might already exist, check error message
                if let error = error {
                    let errorMessage = String(cString: error)
                    if !errorMessage.contains("duplicate column") {
                        print("⚠️ Migration warning (modified_at): \(errorMessage)")
                    }
                    sqlite3_free(error)
                }
            }

            // Add file_size column
            let addFileSizeSQL = "ALTER TABLE documents ADD COLUMN file_size INTEGER DEFAULT 0;"
            if sqlite3_exec(db, addFileSizeSQL, nil, nil, &error) != SQLITE_OK {
                // Column might already exist, check error message
                if let error = error {
                    let errorMessage = String(cString: error)
                    if !errorMessage.contains("duplicate column") {
                        print("⚠️ Migration warning (file_size): \(errorMessage)")
                    }
                    sqlite3_free(error)
                }
            }

            setSchemaVersion(2)
            print("✅ Migration to v2 complete")
        }

        // Future migrations go here:
        // if version < 3 {
        //     // Migration v2 → v3
        // }
    }

    private func getSchemaVersion() -> Int {
        var version = 0
        let sql = "PRAGMA user_version;"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                version = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)
        }

        return version
    }

    private func setSchemaVersion(_ version: Int) {
        let sql = "PRAGMA user_version = \(version);"
        var error: UnsafeMutablePointer<CChar>?

        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            if let error = error {
                print("❌ Failed to set schema version: \(String(cString: error))")
                sqlite3_free(error)
            }
        } else {
            print("✅ Schema version set to \(version)")
        }
    }

    // Note: Actors don't support deinit with nonisolated access
    // Database will be closed when app terminates
    // For explicit cleanup, call closeDatabase() method if needed

    // MARK: - CRUD Operations

    /// Insert a document chunk
    func insertDocument(
        id: String,
        filePath: String,
        fileName: String,
        content: String,
        chunkIndex: Int,
        language: String,
        embedding: [Float],
        modifiedAt: Date,
        fileSize: Int
    ) async -> Bool {
        let insertSQL = """
        INSERT OR REPLACE INTO documents
        (id, file_path, file_name, content, chunk_index, language, embedding, created_at, modified_at, file_size)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Failed to prepare insert statement")
            return false
        }

        defer { sqlite3_finalize(statement) }

        // Bind parameters
        sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (filePath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (fileName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(chunkIndex))
        sqlite3_bind_text(statement, 6, (language as NSString).utf8String, -1, nil)

        // Convert embedding to binary data
        let embeddingData = embedding.withUnsafeBytes { Data($0) }
        _ = embeddingData.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 7, bytes.baseAddress, Int32(embeddingData.count), nil)
        }

        sqlite3_bind_double(statement, 8, Date().timeIntervalSince1970)
        sqlite3_bind_double(statement, 9, modifiedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 10, Int32(fileSize))

        // Execute
        if sqlite3_step(statement) == SQLITE_DONE {
            return true
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Insert failed: \(errorMessage)")
            return false
        }
    }

    /// Get file metadata (modification time and size) for a file path
    func getFileMetadata(filePath: String) async -> (modifiedAt: Date, fileSize: Int)? {
        let querySQL = "SELECT modified_at, file_size FROM documents WHERE file_path = ? LIMIT 1;"

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK,
              statement != nil else {
            print("⚠️ Failed to prepare getFileMetadata statement")
            return nil
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (filePath as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW {
            let modifiedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            let fileSize = Int(sqlite3_column_int(statement, 1))
            return (modifiedAt, fileSize)
        }

        return nil
    }

    /// Fetch all documents with optional file name exclusion patterns
    func fetchAllDocuments(excludeExtensions: [String] = []) async -> [(id: String, filePath: String, fileName: String, content: String, chunkIndex: Int, language: String, embedding: [Float])] {
        let querySQL = "SELECT id, file_path, file_name, content, chunk_index, language, embedding FROM documents;"

        var statement: OpaquePointer?
        var results: [(String, String, String, String, Int, String, [Float])] = []

        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK,
              statement != nil else {
            print("❌ Failed to prepare fetch statement")
            return []
        }

        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let filePath = String(cString: sqlite3_column_text(statement, 1))
            let fileName = String(cString: sqlite3_column_text(statement, 2))
            let content = String(cString: sqlite3_column_text(statement, 3))
            let chunkIndex = Int(sqlite3_column_int(statement, 4))
            let language = String(cString: sqlite3_column_text(statement, 5))

            // Extract embedding from BLOB
            let embeddingBlob = sqlite3_column_blob(statement, 6)
            let embeddingSize = Int(sqlite3_column_bytes(statement, 6))

            var embedding: [Float] = []
            if let blob = embeddingBlob {
                let data = Data(bytes: blob, count: embeddingSize)
                embedding = data.withUnsafeBytes { buffer in
                    Array(buffer.bindMemory(to: Float.self))
                }
            }

            // Filter by extension if exclusions are specified
            if !excludeExtensions.isEmpty {
                let ext = (fileName as NSString).pathExtension.lowercased()
                if excludeExtensions.contains(ext) {
                    continue // Skip this file
                }
            }

            // Always skip common doc files (README, CHANGELOG, LICENSE, etc.)
            if isCommonDocFile(fileName) {
                continue // Skip
            }

            // Always skip files from common directories (node_modules, etc.)
            if pathContainsSkipDirectory(filePath) {
                continue // Skip
            }

            results.append((id, filePath, fileName, content, chunkIndex, language, embedding))
        }

        return results
    }

    // MARK: - Helper Methods

    /// Check if this is a common documentation file
    private func isCommonDocFile(_ fileName: String) -> Bool {
        let lowerName = fileName.lowercased()
        let baseName = (fileName as NSString).deletingPathExtension.lowercased()

        let docPrefixes = ["readme", "changelog", "license", "contributing", "authors"]

        return docPrefixes.contains { prefix in
            baseName == prefix || lowerName.hasPrefix(prefix + ".")
        }
    }

    /// Check if path contains a directory that should be skipped
    private func pathContainsSkipDirectory(_ path: String) -> Bool {
        let pathComponents = path.components(separatedBy: "/")

        let skipDirs = [
            "node_modules", ".git", ".svn", ".hg", "vendor",
            "venv", ".venv", "env", "__pycache__", ".pytest_cache",
            ".idea", ".vscode", "build", "dist", "target",
            ".next", ".nuxt", "coverage", ".nyc_output"
        ]

        return pathComponents.contains { skipDirs.contains($0.lowercased()) }
    }

    /// Get database statistics
    func getStats() async -> (count: Int, totalSize: Int) {
        let statsSQL = "SELECT COUNT(*), SUM(LENGTH(content)) FROM documents;"

        var statement: OpaquePointer?
        var count = 0
        var totalSize = 0

        guard sqlite3_prepare_v2(db, statsSQL, -1, &statement, nil) == SQLITE_OK,
              statement != nil else {
            print("⚠️ Failed to prepare getStats statement")
            return (0, 0)
        }

        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
            totalSize = Int(sqlite3_column_int(statement, 1))
        }

        return (count, totalSize)
    }

    /// Get indexed files summary (grouped by file)
    func getIndexedFilesSummary() async -> [(id: String, filePath: String, fileName: String, language: String, chunkCount: Int, fileSize: Int)] {
        let summarySQL = """
        SELECT
            MIN(id) as id,
            file_path,
            file_name,
            language,
            COUNT(*) as chunk_count,
            SUM(LENGTH(content)) as file_size
        FROM documents
        GROUP BY file_path
        ORDER BY file_name;
        """

        var statement: OpaquePointer?
        var results: [(String, String, String, String, Int, Int)] = []

        guard sqlite3_prepare_v2(db, summarySQL, -1, &statement, nil) == SQLITE_OK,
              statement != nil else {
            print("⚠️ Failed to prepare getIndexedFilesSummary statement")
            return []
        }

        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let filePath = String(cString: sqlite3_column_text(statement, 1))
            let fileName = String(cString: sqlite3_column_text(statement, 2))
            let language = String(cString: sqlite3_column_text(statement, 3))
            let chunkCount = Int(sqlite3_column_int(statement, 4))
            let fileSize = Int(sqlite3_column_int(statement, 5))

            results.append((id, filePath, fileName, language, chunkCount, fileSize))
        }

        return results
    }

    /// Clear all documents
    func clearAll() async -> Bool {
        let deleteSQL = "DELETE FROM documents;"

        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, deleteSQL, nil, nil, &error) == SQLITE_OK {
            print("🗑️ Database cleared")
            return true
        } else {
            if let error = error {
                let errorMessage = String(cString: error)
                print("❌ Clear failed: \(errorMessage)")
                sqlite3_free(error)
            }
            return false
        }
    }

    /// Delete documents by file path
    func deleteDocumentsByPath(_ filePath: String) async -> Bool {
        let deleteSQL = "DELETE FROM documents WHERE file_path = ?;"

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK,
              statement != nil else {
            print("⚠️ Failed to prepare deleteDocumentsByPath statement")
            return false
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (filePath as NSString).utf8String, -1, nil)

        return sqlite3_step(statement) == SQLITE_DONE
    }
}
