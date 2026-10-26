import Foundation
import CallKit

class CallDirectoryHandler: CXCallDirectoryProvider {

    private let appGroupId = "group.com.mode.qara"
    private let directoryFileName = "contacts_directory.json"

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        if context.isIncremental {
            // Remove previous entries if doing full sync
            context.removeAllIdentificationEntries()
        }

        addAllIdentificationEntries(to: context)

        context.completeRequest()
    }

    private func addAllIdentificationEntries(to context: CXCallDirectoryExtensionContext) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            NSLog("[Qara] Failed to access App Group container for %@", appGroupId)
            return
        }

        let fileURL = containerURL.appendingPathComponent(directoryFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("[Qara] Directory file does not exist at %@", fileURL.path)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([DirectoryEntry].self, from: data)

            // Apple CallKit requires:
            // 1. Valid Int64 E.164 phone numbers (e.g. 233244123456)
            // 2. Strict ascending numerical order
            // 3. Zero duplicates
            let sortedEntries = entries.sorted { $0.phoneNumber < $1.phoneNumber }
            var lastPhoneNumber: Int64 = 0
            var addedCount = 0
            for entry in sortedEntries {
                if entry.phoneNumber > lastPhoneNumber {
                    lastPhoneNumber = entry.phoneNumber
                    context.addIdentificationEntry(
                        withNextSequentialPhoneNumber: entry.phoneNumber,
                        label: entry.label
                    )
                    addedCount += 1
                }
            }
            NSLog("[Qara] CallDirectoryExtension loaded %ld caller ID entries", addedCount)
        } catch {
            NSLog("[Qara] Error loading contacts directory: %@", error.localizedDescription)
        }
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        NSLog("[Qara] CallDirectoryExtension request failed: %@", error.localizedDescription)
    }
}

struct DirectoryEntry: Codable {
    let phoneNumber: Int64
    let label: String
}
