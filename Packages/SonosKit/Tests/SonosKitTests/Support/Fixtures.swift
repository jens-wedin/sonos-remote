import Foundation

enum Fixtures {
    static func url(_ name: String) -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fixtures") else {
            fatalError("Missing fixture \(name)")
        }
        return url
    }

    static func data(_ name: String) -> Data {
        try! Data(contentsOf: url(name))
    }

    static func string(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }

    /// Non-empty lines of a .jsonl fixture, in file order.
    static func lines(_ name: String) -> [String] {
        string(name).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
