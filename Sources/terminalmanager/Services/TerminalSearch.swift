#if os(macOS)
import Foundation
import SwiftTerm

extension LoggedLocalProcessTerminalView {
    @discardableResult
    func findNextOccurrence(_ query: String, searchFromEnd: Bool = false) -> Bool {
        guard !query.isEmpty else { return false }
        if searchFromEnd {
            clearSearch()
        }
        return findNext(query)
    }

    @discardableResult
    func findPreviousOccurrence(_ query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return findPrevious(query)
    }
}
#endif
