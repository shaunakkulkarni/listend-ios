//
//  ListendSharedStore.swift
//  Listend
//

import Foundation
import SwiftData
import OSLog

enum ListendAppGroup {
    #if SANDBOX
    static let identifier = "group.com.shaunakkulkarni.Listend.Sandbox"
    #else
    static let identifier = "group.com.shaunakkulkarni.Listend"
    #endif
}

enum ListendSharedStore {
    static let storeFileName = "Listend.store"

    static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "default.store")
    }

    static func sharedStoreURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: ListendAppGroup.identifier)?
            .appending(path: storeFileName)
    }

    static func productionConfiguration(fileManager: FileManager = .default) -> ModelConfiguration {
        let defaultURL = defaultStoreURL(fileManager: fileManager)

        guard let sharedURL = sharedStoreURL(fileManager: fileManager) else {
            return ModelConfiguration(schema: ListendModelSchema.schema, url: defaultURL)
        }

        do {
            try ListendSharedStoreMigrator.copyDefaultStoreIfNeeded(
                defaultStoreURL: defaultURL,
                sharedStoreURL: sharedURL,
                fileManager: fileManager
            )
        } catch {
            // Keep the original journal usable and retry migration on the next
            // launch. Never create an empty shared journal after a failed copy.
            Logger(subsystem: "com.shaunakkulkarni.Listend", category: "Storage")
                .error("Shared-store migration failed; retaining the original store: \(error.localizedDescription, privacy: .public)")
            return ModelConfiguration(schema: ListendModelSchema.schema, url: defaultURL)
        }

        return ModelConfiguration(schema: ListendModelSchema.schema, url: sharedURL)
    }
}

enum ListendSharedStoreMigrator {
    static func copyDefaultStoreIfNeeded(
        defaultStoreURL: URL,
        sharedStoreURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: defaultStoreURL.path),
              !fileManager.fileExists(atPath: sharedStoreURL.path) else { return }
        try fileManager.createDirectory(at: sharedStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var migrationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: sharedStoreURL, options: .forReplacing, error: &coordinationError) { destination in
            do {
                try copyCoordinatedStoreIfNeeded(defaultStoreURL: defaultStoreURL, sharedStoreURL: destination, fileManager: fileManager)
            } catch {
                migrationError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let migrationError { throw migrationError }
    }

    private static func copyCoordinatedStoreIfNeeded(
        defaultStoreURL: URL,
        sharedStoreURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: defaultStoreURL.path),
              !fileManager.fileExists(atPath: sharedStoreURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: sharedStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Stage every file before publishing any of them. Publish the main store
        // last: its existence is the completion marker used on later launches.
        let stagingDirectory = sharedStoreURL.deletingLastPathComponent()
            .appending(path: ".ListendMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let files = storeFiles(defaultStoreURL: defaultStoreURL, sharedStoreURL: sharedStoreURL)
            .filter { fileManager.fileExists(atPath: $0.0.path) }
        for (source, destination) in files {
            try fileManager.copyItem(at: source, to: stagingDirectory.appending(path: destination.lastPathComponent))
        }

        var publishedFiles: [URL] = []
        do {
            // Clear every orphaned destination sidecar, including one that is
            // no longer present in the source after SQLite checkpointed it.
            for (_, destination) in storeFiles(defaultStoreURL: defaultStoreURL, sharedStoreURL: sharedStoreURL).dropFirst()
                where fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            for (_, destination) in files.dropFirst() + files.prefix(1) {
                try fileManager.moveItem(
                    at: stagingDirectory.appending(path: destination.lastPathComponent),
                    to: destination
                )
                publishedFiles.append(destination)
            }
        } catch {
            for destination in publishedFiles {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    private static func storeFiles(defaultStoreURL: URL, sharedStoreURL: URL) -> [(URL, URL)] {
        [
            (defaultStoreURL, sharedStoreURL),
            (defaultStoreURL.appendingPathExtension("wal"), sharedStoreURL.appendingPathExtension("wal")),
            (defaultStoreURL.appendingPathExtension("shm"), sharedStoreURL.appendingPathExtension("shm")),
            (
                defaultStoreURL.deletingLastPathComponent().appending(path: "\(defaultStoreURL.lastPathComponent)-wal"),
                sharedStoreURL.deletingLastPathComponent().appending(path: "\(sharedStoreURL.lastPathComponent)-wal")
            ),
            (
                defaultStoreURL.deletingLastPathComponent().appending(path: "\(defaultStoreURL.lastPathComponent)-shm"),
                sharedStoreURL.deletingLastPathComponent().appending(path: "\(sharedStoreURL.lastPathComponent)-shm")
            )
        ]
    }
}
