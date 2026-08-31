import Foundation

/// A dotted release version such as `1.2.3`, tolerant of a leading `v`.
///
/// Comparison is numeric per component, so `1.10` correctly sorts above `1.9`, which a
/// plain string comparison gets wrong. Missing components count as zero, so `1.2` and
/// `1.2.0` are equal.
public struct Version: Comparable, Sendable {
    public let components: [Int]

    /// Returns `nil` when the string holds no leading numeric component, so junk such
    /// as a branch name is rejected rather than silently treated as `0`.
    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix =
            trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed

        // Stop at the first non-numeric component: "1.2.3-beta.1" reads as 1.2.3.
        var parsed: [Int] = []
        for piece in withoutPrefix.split(separator: ".") {
            let digits = piece.prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else { break }
            parsed.append(value)
            if digits.count != piece.count { break }
        }

        guard !parsed.isEmpty else { return nil }
        components = parsed
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
