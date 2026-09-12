/// Strict `major.minor.patch` handling for release tags (`v0.2.1`) and `CFBundleShortVersionString`.
/// Pre-release suffixes and anything else that is not digits and dots do not parse, so they can never be "newer".
enum SemanticVersion {
    /// "v1.2" → (1, 2, 0). Nil for an empty string, more than three parts, an empty part, or a non-digit character.
    static func parse(_ string: String) -> (major: Int, minor: Int, patch: Int)? {
        var text = Substring(string)
        if text.hasPrefix("v") { text = text.dropFirst() }
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        return (numbers[0], numbers[1], numbers[2])
    }

    /// True only when both sides parse and `candidate` is strictly greater.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        return (a.major, a.minor, a.patch) > (b.major, b.minor, b.patch)
    }
}
