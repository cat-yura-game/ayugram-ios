// AYG: logging in from a session code, on the screen where there is no account yet.
//
// The export half lives in Debug Settings; the encoding and the import itself are in
// `TelegramCore/Sources/AYGSessionTransfer/AYGSessionTransfer.swift`, which explains
// why the feature exists at all. This file is only the way in.
//
// A plain `UIAlertController` with a text field, deliberately: `promptController` —
// the app's own styled prompt — takes an `AccountContext`, and on this screen there is
// no account to take one from. A system alert also needs no explaining to a reviewer
// following three lines of instructions.

import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

/// The label on the login screen's secondary button.
public var aygSessionImportButtonTitle: String { aygString("AYGSessionImportButton") }

private var aygSessionImportPrompt: String { aygString("AYGSessionImportPrompt") }

/// Prompts for a code and, if it parses, signs in with it.
///
/// `isTestingEnvironment` follows the screen the user is on, so a code exported from a
/// test-DC account lands back on the test DC rather than being pointed at production
/// where its key means nothing.
func aygPresentSessionImport(
    from controller: ViewController,
    sharedContext: SharedAccountContext,
    isTestingEnvironment: Bool,
    presentationData: PresentationData
) {
    let alert = UIAlertController(title: aygSessionImportButtonTitle, message: aygSessionImportPrompt, preferredStyle: .alert)
    alert.addTextField { textField in
        textField.placeholder = "AYGSESSION1:…"
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        // The code is one long opaque token; the keyboard should not try to help.
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.spellCheckingType = .no
    }
    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Done, style: .default, handler: { [weak controller] _ in
        guard let text = alert.textFields?.first?.text else {
            return
        }
        guard let backupData = aygDecodeSessionCode(text) else {
            guard let controller else {
                return
            }
            let failure = UIAlertController(title: nil, message: aygString("AYGSessionImportInvalid"), preferredStyle: .alert)
            failure.addAction(UIAlertAction(title: presentationData.strings.Common_OK, style: .default, handler: nil))
            controller.view.window?.rootViewController?.present(failure, animated: true)
            return
        }
        let _ = aygImportSession(
            accountManager: sharedContext.accountManager,
            backupData: backupData,
            isTestingEnvironment: isTestingEnvironment
        ).start()
    }))
    controller.view.window?.rootViewController?.present(alert, animated: true)
}
