import Testing
import Foundation
@testable import EMCore

@Suite("EMError")
struct EMErrorTests {

    @Test("File errors have user-facing descriptions")
    func fileErrorDescriptions() {
        let url = URL(fileURLWithPath: "/test.md")

        let cases: [(EMError, Bool)] = [
            (.file(.notUTF8(url: url)), true),
            (.file(.accessDenied(url: url)), true),
            (.file(.notFound(url: url)), true),
            (.file(.saveFailed(url: url, underlying: NSError(domain: "", code: 0))), true),
            (.file(.tooLarge(url: url, sizeBytes: 100_000_000)), true),
            (.file(.externallyDeleted(url: url)), true),
            (.file(.bookmarkStale(url: url)), true),
        ]

        for (error, _) in cases {
            #expect(error.errorDescription != nil, "Missing description for \(error)")
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("AI errors have user-facing descriptions")
    func aiErrorDescriptions() {
        let cases: [EMError] = [
            .ai(.modelNotDownloaded),
            .ai(.inferenceTimeout),
            .ai(.deviceNotSupported),
            .ai(.cloudUnavailable),
            .ai(.subscriptionRequired),
            .ai(.subscriptionExpired),
        ]

        for error in cases {
            #expect(error.errorDescription != nil, "Missing description for \(error)")
        }
    }

    @Test("Parse timeout includes line count")
    func parseTimeoutDescription() {
        let error = EMError.parse(.timeout(lineCount: 10_000))
        #expect(error.errorDescription?.contains("10000") == true)
    }

    @Test("Unexpected error has safe message")
    func unexpectedError() {
        let error = EMError.unexpected(underlying: NSError(domain: "test", code: 42))
        #expect(error.errorDescription?.contains("safe") == true)
    }
}
