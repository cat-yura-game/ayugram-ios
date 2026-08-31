import Foundation
import Postbox
import SwiftSignalKit

// AYG: moving an authorised session between installs, without an SMS code.
//
// The reason this exists is App Review. Telegram delivers the login code either into
// an existing session — which means the reviewer would need the official client, and
// Apple rejects "install another app to log in" — or by SMS, which a reviewer cannot
// receive. So the account has to arrive already authorised.
//
// Nothing here is new protocol work: Telegram already carries an account's credentials
// as `AccountBackupData` (master DC, auth key, peer id, the notification key and any
// additional DC keys), `accountBackupData(postbox:)` already extracts it, and
// `accountWithId(…, backupData:)` already restores an account from it. This only adds
// the two ends: a transport encoding, and the import that creates the account record.
//
// **The code is a full credential.** Anyone holding it is signed in as that account —
// it is not a password that can be scoped or rate-limited. It goes to App Review out
// of band, never inside the binary, and the session is terminated afterwards. That is
// also why the *export* lives in Debug Settings while only the *import* is on the
// login screen: producing one should be deliberate, using one has to be reachable by
// someone who cannot log in yet.

private let aygSessionCodePrefix = "AYGSESSION1:"

/// Packs an account's credentials into the single line that goes into Review Notes.
public func aygEncodeSessionCode(_ backupData: AccountBackupData) -> String? {
    guard let json = try? JSONEncoder().encode(backupData) else {
        return nil
    }
    return aygSessionCodePrefix + json.base64EncodedString()
}

/// The inverse. Tolerates the whitespace and line breaks that survive a copy-paste out
/// of App Store Connect.
public func aygDecodeSessionCode(_ code: String) -> AccountBackupData? {
    var trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    trimmed = trimmed.components(separatedBy: .whitespacesAndNewlines).joined()
    guard trimmed.hasPrefix(aygSessionCodePrefix) else {
        return nil
    }
    let payload = String(trimmed.dropFirst(aygSessionCodePrefix.count))
    guard let data = Data(base64Encoded: payload) else {
        return nil
    }
    return try? JSONDecoder().decode(AccountBackupData.self, from: data)
}

/// The code for the account behind `postbox`, or `nil` when it has none to give — an
/// account that is not authorised has no key to export.
public func aygSessionCode(postbox: Postbox) -> Signal<String?, NoError> {
    return accountBackupData(postbox: postbox)
    |> map { backupData -> String? in
        guard let backupData else {
            return nil
        }
        return aygEncodeSessionCode(backupData)
    }
}

/// Creates an account record restored from `backupData` and returns its id.
///
/// The record is created **authorised** — `createRecord`, not `createAuth` — because
/// the credentials are already in hand; there is no login sequence to run. The rest is
/// upstream's: `SharedAccountContext` sees the `.backupData` attribute on the record
/// and hands it to `accountWithId`, which brings the session up.
public func aygImportSession(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    backupData: AccountBackupData,
    isTestingEnvironment: Bool
) -> Signal<AccountRecordId, NoError> {
    return accountManager.transaction { transaction -> AccountRecordId in
        // Sort last, so importing does not reshuffle accounts the user already has.
        var maximumSortOrder: Int32 = 0
        for record in transaction.getRecords() {
            for attribute in record.attributes {
                if case let .sortOrder(sortOrder) = attribute {
                    maximumSortOrder = max(maximumSortOrder, sortOrder.order)
                }
            }
        }

        let id = transaction.createRecord([
            .sortOrder(AccountSortOrderAttribute(order: maximumSortOrder + 1)),
            .environment(AccountEnvironmentAttribute(environment: isTestingEnvironment ? .test : .production)),
            .backupData(AccountBackupDataAttribute(data: backupData))
        ])
        transaction.setCurrentId(id)
        // An import is a completed login: whatever half-finished authorisation was on
        // screen has to go, or the app comes back to the phone-number field.
        transaction.removeAuth()
        return id
    }
}
