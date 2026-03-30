import Foundation

/// Pure system note parsing logic. No SwiftData, no async, no side effects.
enum SystemNoteParser {

    // NOTE: Matches English GitLab system note wording.
    // GitLab writes "requested changes on this merge request" (or similar) when a reviewer
    // requests changes. This string is stable but could change on major GitLab versions.
    // Update this constant if the system note copy changes.
    static let changesRequestedPattern = "requested changes"

    /// Returns the author names of system notes that indicate a reviewer requested changes,
    /// filtered to only notes newer than `lastNoteID` (if provided).
    static func changesRequestedAuthors(
        in notes: [RESTNote],
        after lastNoteID: Int?
    ) -> [String] {
        notes
            .filter { note in
                guard note.system else { return false }
                if let lastID = lastNoteID, note.id <= lastID { return false }
                return note.body.lowercased().contains(changesRequestedPattern)
            }
            .map(\.author.name)
    }
}
