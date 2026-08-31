// AYG: "View Deleted" / "Clear Deleted" — the two AntiDelete entries of the
// AyuGram submenu in a peer's "More" menu.
//
// Android's `com.radolyn.ayugram.ui.AyuMessageHistory` opened with a dialog id
// (`loadDeleted`) is a full `ChatActivity` clone: real bubbles, avatars, date
// separators, selection, forwarding. `AYGMessageHistoryController` already made
// the call not to reproduce that, and this screen is the same trade — the stored
// deletions drawn as chat bubbles on the chat wallpaper, oldest first, on top of
// the bubble renderer the Customization preview already uses.
//
// Deliberately not ported:
//   * media. `AttachmentArchive` keeps the file, but `AYGChatPreviewItem` renders
//     text bubbles only, so a photo shows as its `mediaDescription` line;
//   * per-message actions (restore, forward, jump to the message in the chat);
//   * `AYGChatPreviewItem`'s deleted treatment — its translucency and its deleted
//     mark are wired to a *single* `deletedNodeIndex`, so on a screen where every
//     bubble is a deletion it would mark exactly one of them. Every bubble here is
//     drawn plain; the screen's title is what says these are deletions.

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

// AYG: `ViewDeletedMenuText`, `ClearDeletedMenuText`, `ClearDeletedMessagesTitle`,
// `ClearDeletedMessagesText` and `ClearDeletedMessagesActionText` from the Android
// strings, verbatim.
public var aygViewDeletedMenuText: String { aygString("ViewDeletedMenuText") }
public var aygClearDeletedMenuText: String { aygString("ClearDeletedMenuText") }
public var aygClearDeletedMessagesTitle: String { aygString("ClearDeletedMessagesTitle") }
public var aygClearDeletedMessagesText: String { aygString("ClearDeletedMessagesText") }
public var aygClearDeletedMessagesActionText: String { aygString("ClearDeletedMessagesActionText") }

/// No Android string covers the screen's own title — `AyuMessageHistory` reuses the
/// chat's action bar for it — so this one is ours.
public var aygDeletedMessagesTitle: String { aygString("AYGDeletedMessagesTitle") }

/// `AYGChatPreviewItem` builds one real message node per entry, synchronously, inside
/// a single list item — fine for the handful the Customization preview and Edits
/// History show it, not fine for a group with a thousand archived deletions. The
/// newest this many are drawn and the rest are counted in the footer.
private let aygDeletedMessagesDisplayLimit = 100

/// Height the wallpaper block is stretched to, so the bubbles sit at the bottom of the
/// screen the way they do in a real chat — the same treatment Edits History gets.
private func aygDeletedMessagesFillHeight() -> CGFloat {
    return max(0.0, UIScreen.main.bounds.height - 140.0)
}

private var aygDeletedMessagesEmptyText: String { aygString("AYGDeletedMessagesEmpty") }
private var aygDeletedMessagesClearedText: String { aygString("AYGDeletedMessagesCleared") }
private var aygDeletedMessagesNothingToClearText: String { aygString("AYGDeletedMessagesNothingToClear") }

/// Placeholder for a deletion that carried neither text nor a media description —
/// a service message, or a media type `aygAntiDeleteMediaDescription` has no name for.
private var aygDeletedMessagesUnknownContent: String { aygString("AYGDeletedMessagesUnknownContent") }

/// Drop every archived deletion belonging to one chat.
///
/// Returns how many entries went, so the caller can tell "cleared" from "there was
/// nothing to clear" in its bulletin.
///
/// Clears the archive **and** takes the kept bubbles out of the chat, which is what
/// Android's `clearDeletedFromDialog` does. The bubbles are ordinary postbox messages
/// held alive by anti-delete, so the hold has to be released first — `_internal_deleteMessages`
/// refuses anything still carrying it, and without this the archive emptied while the
/// messages stayed on screen.
///
/// The files `AttachmentArchive` copied out for these messages are left behind too:
/// it exposes `clear()` for the whole folder and nothing per-entry. They are only
/// reachable through the archive record that just went, so what is left is dead
/// weight in the media folder until the user clears it from the Spy screen.
@discardableResult
public func aygClearDeletedMessages(context: AccountContext, peerId: EnginePeer.Id) -> Int {
    let archived = AntiDeleteManager.shared.getArchivedMessages(forPeerId: peerId.toInt64())
    guard !archived.isEmpty else {
        return 0
    }

    // Release the hold before asking for the delete, or the anti-delete guard in
    // `_internal_deleteMessages` throws the ids straight back out.
    var messageIds: [EngineMessage.Id] = []
    for message in archived {
        AntiDeleteManager.shared.forgetKeptMessage(peerId: message.peerId, messageId: message.messageId)
        messageIds.append(EngineMessage.Id(peerId: peerId, namespace: Namespaces.Message.Cloud, id: message.messageId))
    }
    let _ = context.engine.messages.deleteMessagesInteractively(messageIds: messageIds, type: .forLocalPeer).startStandalone()

    for message in archived {
        AntiDeleteManager.shared.removeFromArchive(globalId: message.globalId)
    }
    // `removeFromArchive` debounces its own write but posts nothing, so the open
    // screens are told here.
    NotificationCenter.default.post(name: AntiDeleteManager.settingsChangedNotification, object: nil)
    return archived.count
}

/// The bulletin text for a clear that removed `count` entries.
public func aygClearDeletedMessagesResultText(count: Int) -> String {
    return count > 0 ? aygDeletedMessagesClearedText : aygDeletedMessagesNothingToClearText
}

private enum AYGDeletedMessagesSection: Int32 {
    case messages
}

private enum AYGDeletedMessagesEntry: ItemListNodeEntry {
    case messages(TelegramWallpaper, PresentationFontSize, PresentationChatBubbleCorners, [AYGChatPreviewMessageItem])
    case empty(String)
    case truncated(String)

    var section: ItemListSectionId {
        return AYGDeletedMessagesSection.messages.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .messages: return 0
        case .empty: return 1
        case .truncated: return 2
        }
    }

    static func <(lhs: AYGDeletedMessagesEntry, rhs: AYGDeletedMessagesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        guard let context = arguments as? AccountContext else {
            preconditionFailure()
        }
        switch self {
        case let .messages(wallpaper, chatFontSize, chatBubbleCorners, messageItems):
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
                translucentDeleted: false,
                deletedMark: nil,
                deletedMarkColor: .clear,
                deletedMarkOffsetX: 0.0,
                minimumContentHeight: aygDeletedMessagesFillHeight()
            )
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .truncated(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// The bubble text for one archived deletion.
///
/// `showAuthor` is on for anything but a one-to-one chat: the preview renderer
/// builds its own throwaway peers, so it can draw no author line of its own, and in
/// a group "who wrote it" is most of the information.
private func aygDeletedMessageText(_ message: AntiDeleteManager.ArchivedMessage, showAuthor: Bool) -> String {
    var body = message.text
    if body.isEmpty {
        body = message.mediaDescription ?? aygDeletedMessagesUnknownContent
    }
    guard showAuthor, let authorName = message.authorName, !authorName.isEmpty else {
        return body
    }
    return "\(authorName)\n\(body)"
}

private func aygDeletedMessagesEntries(
    presentationData: PresentationData,
    messages: [AntiDeleteManager.ArchivedMessage],
    accountPeerId: EnginePeer.Id,
    showAuthors: Bool
) -> [AYGDeletedMessagesEntry] {
    guard !messages.isEmpty else {
        return [.empty(aygDeletedMessagesEmptyText)]
    }

    // `AYGChatPreviewItem` reverses what it is handed and lays the result out top
    // down, so newest-first in means oldest at the top — chat order.
    let ownId = accountPeerId.toInt64()
    let ordered = messages.sorted { $0.timestamp > $1.timestamp }
    let shown = Array(ordered.prefix(aygDeletedMessagesDisplayLimit))
    let messageItems = shown.map { message in
        AYGChatPreviewMessageItem(
            outgoing: message.authorId == ownId,
            text: aygDeletedMessageText(message, showAuthor: showAuthors),
            timestamp: message.timestamp,
            deleted: false
        )
    }

    var entries: [AYGDeletedMessagesEntry] = [
        .messages(presentationData.chatWallpaper, presentationData.chatFontSize, presentationData.chatBubbleCorners, messageItems)
    ]
    if ordered.count > shown.count {
        entries.append(.truncated(aygString("AYGDeletedMessagesTruncated", shown.count, ordered.count)))
    }
    return entries
}

/// The screen the AyuGram submenu's "View Deleted" entry pushes.
///
/// `peerId` is the *chat's* peer id, which is what `AntiDeleteManager` keys the
/// archive on (`message.id.peerId.toInt64()`) — for a secret chat that is the secret
/// chat, not the user behind it.
public func aygDeletedMessagesController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    // AyuGram opens this over the chat's own action bar, so it carries the chat's
    // header rather than a plain screen title.
    let navigationBar = AYGChatStyleNavigationBar(context: context, peerId: peerId)
    let statePromise = Promise<[AntiDeleteManager.ArchivedMessage]>()
    let reload: () -> Void = {
        statePromise.set(.single(AntiDeleteManager.shared.getArchivedMessages(forPeerId: peerId.toInt64())))
    }
    reload()

    // The archive can be cleared from the Spy screen, or by the auto-clear timer,
    // while this is open.
    let observer = NotificationCenter.default.addObserver(forName: AntiDeleteManager.settingsChangedNotification, object: nil, queue: .main) { _ in
        reload()
    }

    let accountPeerId = context.account.peerId

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)),
        statePromise.get()
    )
    |> map { presentationData, peer, messages -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var showAuthors = false
        if let peer {
            switch peer {
            case .legacyGroup, .channel:
                showAuthors = true
            default:
                showAuthors = false
            }
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .customView(navigationBar.titleView),
            leftNavigationButton: nil,
            rightNavigationButton: ItemListNavigationButton(content: .node(navigationBar.avatarNode), style: .regular, enabled: true, action: {}),
            backNavigationButton: nil
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: aygDeletedMessagesEntries(presentationData: presentationData, messages: messages, accountPeerId: accountPeerId, showAuthors: showAuthors),
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
