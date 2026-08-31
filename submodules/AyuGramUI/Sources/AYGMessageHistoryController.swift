// AYG: "Edits History" — the screen behind the message context menu's "History"
// entry, showing every stored pre-edit version of one message.
//
// Android's `com.radolyn.ayugram.ui.AyuMessageHistory` is a 5.8k-line clone of
// `ChatActivity`: a real chat fragment with its own action bar, avatar header,
// date separators, text selection, forwarding and a second mode for browsing a
// dialog's deleted messages. None of that is reproducible here at a sane cost, and
// most of it is chrome. What the screen *is* — the stored revisions drawn as chat
// bubbles, oldest first, each carrying the timestamp of the edit that replaced it —
// is what this reproduces, on top of the same bubble renderer the Customization
// preview already uses.
//
// Deliberately not ported:
//   * the deleted-messages mode (`loadDeleted`), reached from elsewhere in Android;
//   * paging — `getRevisions(..., 25)` pages, `EditHistoryManager` keeps a bounded
//     list per message and hands it over whole;
//   * media revisions. `saveOriginalText` archives text only, so a revision that
//     only changed a caption's media has nothing to show.

import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

// AYG: `EditsHistoryTitle` and `EditsHistoryMenuText` from the Android strings.
public var aygEditsHistoryTitle: String { aygString("EditsHistoryTitle") }
public var aygEditsHistoryMenuText: String { aygString("EditsHistoryMenuText") }

private var aygEditsHistoryEmptyText: String { aygString("AYGEditsHistoryEmpty") }

/// Height the wallpaper block is stretched to, so the bubbles sit at the bottom of
/// the screen instead of the top of a hugging block.
///
/// A flat allowance for the navigation bar, status bar and home indicator rather than
/// a measured one: the item is laid out before any of that is known, and the block
/// scrolls, so being a few points out costs nothing either way.
private func aygMessageHistoryFillHeight() -> CGFloat {
    return max(0.0, UIScreen.main.bounds.height - 140.0)
}

private enum AYGMessageHistorySection: Int32 {
    case history
}

private enum AYGMessageHistoryEntry: ItemListNodeEntry {
    case revisions(TelegramWallpaper, PresentationFontSize, PresentationChatBubbleCorners, [AYGChatPreviewMessageItem])
    case empty(String)

    var section: ItemListSectionId {
        return AYGMessageHistorySection.history.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .revisions: return 0
        case .empty: return 1
        }
    }

    static func <(lhs: AYGMessageHistoryEntry, rhs: AYGMessageHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        guard let context = arguments as? AccountContext else {
            preconditionFailure()
        }
        switch self {
        case let .revisions(wallpaper, chatFontSize, chatBubbleCorners, messageItems):
            return AYGChatPreviewItem(
                context: context,
                systemStyle: .glass,
                theme: presentationData.theme,
                componentTheme: presentationData.theme,
                strings: presentationData.strings,
                sectionId: self.section,
                fontSize: chatFontSize,
                chatBubbleCorners: chatBubbleCorners,
                wallpaper: wallpaper,
                dateTimeFormat: presentationData.dateTimeFormat,
                nameDisplayOrder: presentationData.nameDisplayOrder,
                messageItems: messageItems,
                // This screen shows past versions, not deletions: no dimming, no mark.
                translucentDeleted: false,
                deletedMark: nil,
                deletedMarkColor: .clear,
                deletedMarkOffsetX: 0.0,
                // AyuGram's screen is a real chat fragment: the wallpaper covers the
                // screen and the revisions rest on the bottom edge. Sourced from the
                // screen rather than the container, so on iPad multitasking this
                // overshoots and simply leaves the block scrollable.
                minimumContentHeight: aygMessageHistoryFillHeight()
            )
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func aygMessageHistoryEntries(presentationData: PresentationData, records: [EditHistoryManager.EditRecord], isOutgoing: Bool) -> [AYGMessageHistoryEntry] {
    guard !records.isEmpty else {
        return [.empty(aygEditsHistoryEmptyText)]
    }
    // `saveOriginalText` appends, so the array is already oldest-first — which is
    // the order Android reads them back in.
    let messageItems = records.map { record in
        AYGChatPreviewMessageItem(outgoing: isOutgoing, text: record.text, timestamp: record.editDate, deleted: false)
    }
    return [.revisions(presentationData.chatWallpaper, presentationData.chatFontSize, presentationData.chatBubbleCorners, messageItems)]
}

/// The screen the "History" context-menu entry pushes.
///
/// `isOutgoing` decides which side the bubbles sit on; it comes from the message
/// the menu was opened on, since the archived revisions carry no direction of
/// their own.
public func aygMessageHistoryController(context: AccountContext, peerId: EnginePeer.Id, messageId: Int32, isOutgoing: Bool) -> ViewController {
    // AyuGram opens this over the chat's own action bar, so it carries the chat's
    // header rather than a plain screen title.
    let navigationBar = AYGChatStyleNavigationBar(context: context, peerId: peerId)
    let statePromise = Promise<[EditHistoryManager.EditRecord]>()
    let reload: () -> Void = {
        statePromise.set(.single(EditHistoryManager.shared.getEditHistory(peerId: peerId.toInt64(), messageId: messageId)))
    }
    reload()

    // The archive can be cleared from the Spy screen while this is open.
    let observer = NotificationCenter.default.addObserver(forName: EditHistoryManager.historyChangedNotification, object: nil, queue: .main) { _ in
        reload()
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get(),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    )
    |> map { presentationData, records, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .customView(navigationBar.titleView),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .node(navigationBar.avatarNode), style: .regular, enabled: true, action: {}),
            // No override: the back button then shows whatever the chat behind it set,
            // unread count and all, which is what makes the bar indistinguishable.
            backNavigationButton: nil
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: aygMessageHistoryEntries(presentationData: presentationData, records: records, isOutgoing: isOutgoing),
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, context))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    return ItemListController(context: context, state: signal)
}
