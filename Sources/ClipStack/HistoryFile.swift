import CryptoKit
import Foundation
import Security

/// Reads and writes the clip history, encrypted with AES-GCM under a key kept in the login keychain.
///
/// Loading never leads to data loss: a file that can't be read is set aside before anything new is
/// written, and if the keychain refuses access the session runs without saving at all.
enum HistoryFile {
    enum LoadResult {
        /// Loaded (possibly empty). Saving is safe.
        case loaded([ClipItem])
        /// The key couldn't be read (for example, keychain access was denied). Don't save this session.
        case locked
    }

    private static let magic = Data("CLS1".utf8)
    private static let keychainService = "ClipStack"
    // Tests point these elsewhere so they never touch the real history or key.
    private static let keychainAccount = ProcessInfo.processInfo.environment["CLIPSTACK_KEY_ACCOUNT"] ?? "history-key"

    private static var directory: URL {
        let url = ProcessInfo.processInfo.environment["CLIPSTACK_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ClipStack", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var encryptedURL: URL { directory.appendingPathComponent("history.dat") }
    /// Plain-text history written by versions before 1.1; migrated and then deleted.
    private static var legacyURL: URL { directory.appendingPathComponent("history.json") }

    // The key is read once and reused; saving happens off the main thread.
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?
    private static let keyLock = NSLock()

    static func load() -> LoadResult {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: encryptedURL.path) {
            let key: SymmetricKey
            switch readKey() {
            case .found(let found):
                key = found
            case .missing:
                // The file can't be decrypted without its key. Keep it aside and start fresh.
                setAside(encryptedURL)
                return .loaded(loadLegacy())
            case .denied:
                return .locked
            }
            guard let data = try? Data(contentsOf: encryptedURL),
                  data.starts(with: magic),
                  let box = try? AES.GCM.SealedBox(combined: data.dropFirst(magic.count)),
                  let plain = try? AES.GCM.open(box, using: key),
                  let items = decode(plain) else {
                setAside(encryptedURL)
                return .loaded(loadLegacy())
            }
            return .loaded(items)
        }
        return .loaded(loadLegacy())
    }

    /// True while an old plain-text history is still on disk and should be re-saved encrypted.
    static var hasPlainTextHistory: Bool {
        FileManager.default.fileExists(atPath: legacyURL.path)
    }

    static func save(_ items: [ClipItem]) throws {
        let plain = try JSONEncoder().encode(items)
        guard let key = try keyForWriting() else { return }
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { return }
        try (magic + combined).write(to: encryptedURL, options: [.atomic, .completeFileProtection])
        // The encrypted copy is written, so the old plain-text file can go.
        try? FileManager.default.removeItem(at: legacyURL)
    }

    // MARK: - Decoding

    /// Decodes clip by clip, so one unreadable entry doesn't sink the whole history.
    private static func decode(_ data: Data) -> [ClipItem]? {
        struct Lossy: Decodable {
            let item: ClipItem?
            init(from decoder: Decoder) throws { item = try? ClipItem(from: decoder) }
        }
        return (try? JSONDecoder().decode([Lossy].self, from: data))?.compactMap(\.item)
    }

    private static func loadLegacy() -> [ClipItem] {
        guard let data = try? Data(contentsOf: legacyURL) else { return [] }
        guard let items = decode(data) else {
            setAside(legacyURL)
            return []
        }
        return items
    }

    /// Renames an unreadable file instead of letting the next save overwrite it.
    private static func setAside(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = url.deletingPathExtension().lastPathComponent + "-unreadable-\(stamp)." + url.pathExtension
        try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name))
    }

    // MARK: - Keychain

    private enum KeyLookup {
        case found(SymmetricKey)
        case missing
        case denied
    }

    private static func readKey() -> KeyLookup {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKey { return .found(cachedKey) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { return .missing }
            let key = SymmetricKey(data: data)
            cachedKey = key
            return .found(key)
        case errSecItemNotFound:
            return .missing
        default:
            return .denied
        }
    }

    /// The existing key, or a new one if none exists. Nil when the keychain refuses access.
    private static func keyForWriting() throws -> SymmetricKey? {
        switch readKey() {
        case .found(let key):
            return key
        case .denied:
            return nil
        case .missing:
            keyLock.lock()
            defer { keyLock.unlock() }
            let key = SymmetricKey(size: .bits256)
            let data = key.withUnsafeBytes { Data($0) }
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecAttrLabel as String: "ClipStack history key",
                kSecValueData as String: data,
            ]
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            cachedKey = key
            return key
        }
    }
}
