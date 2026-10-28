import Foundation

public nonisolated extension Calendar {
    /// Monday-first weekday index, 0…6.
    func mondayIndex(of date: Date) -> Int {
        (component(.weekday, from: date) + 5) % 7
    }
}
