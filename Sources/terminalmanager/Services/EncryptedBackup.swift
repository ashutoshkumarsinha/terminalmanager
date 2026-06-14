import CryptoKit
import Foundation

enum EncryptedBackup {
    enum BackupError: Error, LocalizedError {
        case invalidPassphrase
        case invalidFormat
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .invalidPassphrase: "Passphrase must not be empty"
            case .invalidFormat: "Backup file format is invalid"
            case .decryptionFailed: "Decryption failed; wrong passphrase or corrupted file"
            }
        }
    }

    struct Payload: Codable {
        var version: Int
        var configToml: String
        var sessionsJSON: String
    }

    private static let formatVersion = 1
    private static let saltLength = 16
    private static let keyLength = 32
    private static let pbkdf2Iterations = 120_000

    static func exportEncrypted(
        settings: AppSettings,
        sessionTree: [SessionTreeItem],
        passphrase: String,
        to url: URL
    ) throws {
        guard !passphrase.isEmpty else { throw BackupError.invalidPassphrase }

        let configToml = try TomlConfigCodec.encode(settings)
        let sessionsData = try JSONEncoder().encode(SessionConfiguration(version: 1, sessionTree: sessionTree))
        guard let sessionsJSON = String(data: sessionsData, encoding: .utf8) else {
            throw BackupError.invalidFormat
        }

        let payload = Payload(version: formatVersion, configToml: configToml, sessionsJSON: sessionsJSON)
        let plaintext = try JSONEncoder().encode(payload)

        var salt = Data(count: saltLength)
        let saltStatus = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        guard saltStatus == errSecSuccess else {
            throw BackupError.invalidFormat
        }

        let key = deriveKey(from: passphrase, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw BackupError.invalidFormat
        }

        var fileData = Data()
        fileData.append(contentsOf: "TMBK".utf8)
        fileData.append(UInt8(formatVersion))
        fileData.append(salt)
        fileData.append(combined)

        try fileData.write(to: url, options: .atomic)
    }

    static func importEncrypted(from url: URL, passphrase: String) throws -> (settings: AppSettings, sessionTree: [SessionTreeItem]) {
        guard !passphrase.isEmpty else { throw BackupError.invalidPassphrase }

        let fileData = try Data(contentsOf: url)
        guard fileData.count > 4 + saltLength + 16,
              String(data: fileData.prefix(4), encoding: .utf8) == "TMBK",
              fileData[4] == UInt8(formatVersion) else {
            throw BackupError.invalidFormat
        }

        let salt = fileData.subdata(in: 5 ..< 5 + saltLength)
        let ciphertext = fileData.subdata(in: 5 + saltLength ..< fileData.count)

        let key = deriveKey(from: passphrase, salt: salt)
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        } catch {
            throw BackupError.decryptionFailed
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw BackupError.decryptionFailed
        }

        let payload = try JSONDecoder().decode(Payload.self, from: plaintext)
        let settings = try TomlConfigCodec.decode(fromString: payload.configToml)
        guard let sessionsData = payload.sessionsJSON.data(using: .utf8) else {
            throw BackupError.invalidFormat
        }
        let sessions = try JSONDecoder().decode(SessionConfiguration.self, from: sessionsData)
        return (settings, sessions.sessionTree)
    }

    private static func deriveKey(from passphrase: String, salt: Data) -> SymmetricKey {
        SymmetricKey(data: pbkdf2SHA256(
            password: passphrase,
            salt: salt,
            iterations: pbkdf2Iterations,
            keyLength: keyLength
        ))
    }

    private static func pbkdf2SHA256(password: String, salt: Data, iterations: Int, keyLength: Int) -> Data {
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt)
        let key = SymmetricKey(data: passwordBytes)
        var derived = [UInt8]()
        var blockIndex = 1

        while derived.count < keyLength {
            var blockCounter = UInt32(blockIndex).bigEndian
            let blockSalt = saltBytes + withUnsafeBytes(of: &blockCounter) { Array($0) }

            var u = Array(HMAC<SHA256>.authenticationCode(for: blockSalt, using: key))
            var block = u

            if iterations > 1 {
                for _ in 1 ..< iterations {
                    u = Array(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for index in block.indices {
                        block[index] ^= u[index]
                    }
                }
            }

            derived.append(contentsOf: block)
            blockIndex += 1
        }

        return Data(derived.prefix(keyLength))
    }
}