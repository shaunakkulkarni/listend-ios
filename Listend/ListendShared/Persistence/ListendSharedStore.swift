//
//  ListendSharedStore.swift
//  Listend
//

import Foundation
import SwiftData

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

        try? ListendSharedStoreMigrator.copyDefaultStoreIfNeeded(
            defaultStoreURL: defaultURL,
            sharedStoreURL: sharedURL,
            fileManager: fileManager
        )

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
              !fileManager.fileExists(atPath: sharedStoreURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: sharedStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        for (source, destination) in storeFiles(defaultStoreURL: defaultStoreURL, sharedStoreURL: sharedStoreURL)
            where fileManager.fileExists(atPath: source.path) && !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: source, to: destination)
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
