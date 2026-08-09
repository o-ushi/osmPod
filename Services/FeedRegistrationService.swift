import Foundation

struct FeedRegistrationService {
    func makeShow(from feedURLText: String, titleInput: String, artworkURLText: String?) throws -> Show {
        let trimmedFeed = feedURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let feedURL = URL(string: trimmedFeed), feedURL.scheme != nil else {
            throw FeedRegistrationError.invalidFeedURL
        }

        let trimmedTitle = titleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if trimmedTitle.isEmpty {
            title = feedURL.host() ?? LocalizedStrings.current.untitledShow
        } else {
            title = trimmedTitle
        }

        let artworkURL: String?
        if let artworkURLText, !artworkURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artworkURL = artworkURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            artworkURL = nil
        }

        return Show(
            title: title,
            feedURL: feedURL.absoluteString,
            artworkURL: artworkURL
        )
    }
}

enum FeedRegistrationError: LocalizedError {
    case invalidFeedURL

    var errorDescription: String? {
        LocalizedStrings.current.invalidURLError
    }
}
