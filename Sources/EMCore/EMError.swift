import Foundation

/// Root error type for all easy-markdown errors per [A-035].
/// Every case includes a user-facing message and recovery options.
public enum EMError: LocalizedError {

    case file(FileError)
    case ai(AIError)
    case parse(ParseError)
    case unexpected(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .file(let error): return error.errorDescription
        case .ai(let error): return error.errorDescription
        case .parse(let error): return error.errorDescription
        case .unexpected: return "Something unexpected happened. Your work is safe."
        }
    }

    // MARK: - File Errors

    public enum FileError: LocalizedError {
        case notUTF8(url: URL)
        case accessDenied(url: URL)
        case notFound(url: URL)
        case saveFailed(url: URL, underlying: Error)
        case tooLarge(url: URL, sizeBytes: Int)
        case externallyDeleted(url: URL)
        case bookmarkStale(url: URL)

        public var errorDescription: String? {
            switch self {
            case .notUTF8: return "This file isn't valid UTF-8 text."
            case .accessDenied: return "Permission denied. Try opening the file again."
            case .notFound: return "This file has been moved or deleted."
            case .saveFailed: return "Couldn't save. Your changes are still in memory — try again."
            case .tooLarge: return "This file is too large to open."
            case .externallyDeleted: return "This file was deleted while you were editing."
            case .bookmarkStale: return "Can't reopen this file. Try opening it from the file picker."
            }
        }
    }

    // MARK: - AI Errors

    public enum AIError: LocalizedError {
        case modelNotDownloaded
        case modelDownloadFailed(underlying: Error)
        case inferenceTimeout
        case inferenceFailed(underlying: Error)
        case deviceNotSupported
        case cloudUnavailable
        case subscriptionRequired
        case subscriptionExpired

        public var errorDescription: String? {
            switch self {
            case .modelNotDownloaded: return "AI model hasn't been downloaded yet."
            case .modelDownloadFailed: return "AI model download failed. Check your connection."
            case .inferenceTimeout: return "AI took too long. Try again or use a shorter selection."
            case .inferenceFailed: return "AI couldn't process that. Try again."
            case .deviceNotSupported: return "AI features require a newer device."
            case .cloudUnavailable: return "Can't reach cloud AI. Check your connection."
            case .subscriptionRequired: return "This feature requires Pro AI."
            case .subscriptionExpired: return "Your Pro AI subscription has expired."
            }
        }
    }

    // MARK: - Parse Errors

    public enum ParseError: LocalizedError {
        case timeout(lineCount: Int)

        public var errorDescription: String? {
            switch self {
            case .timeout(let lines):
                return "Document (\(lines) lines) took too long to parse."
            }
        }
    }
}
