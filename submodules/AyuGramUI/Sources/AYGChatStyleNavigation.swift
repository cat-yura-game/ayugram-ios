// AYG: the chat's own navigation bar, on a screen that is not a chat.
//
// Edits History and Deleted Messages both stand in for the conversation they came
// from — AyuGram opens them over the chat's own action bar — so they carry the same
// header Telegram gives a chat: the peer's name with its status underneath, and the
// peer's avatar as the right-hand button. `ItemListController` draws a plain centred
// title instead, which is what made them look foreign.
//
// This uses Telegram's own `ChatTitleView` and `ChatAvatarNavigationNode` rather than
// a lookalike, so the pill backgrounds, glass styling, presence line and its live
// updates all come for free and stay right when upstream restyles the bar.

import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramPresentationData
import AccountContext
import ChatTitleView
import ChatAvatarNavigationNode

/// The chat's header, ready to be handed to an `ItemListControllerState`.
///
/// Both halves must be **one stable instance** for the life of the screen:
/// `ItemListControllerTitle.customView` compares by identity, and
/// `ItemListNavigationButtonContent.node` does too, so a fresh view per state
/// emission would rebuild the bar on every update.
public final class AYGChatStyleNavigationBar {
    public let titleView: ChatTitleView
    public let avatarNode: ChatAvatarNavigationNode
    private let disposable = MetaDisposable()

    public init(context: AccountContext, peerId: EnginePeer.Id) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }

        self.titleView = ChatTitleView(
            context: context,
            theme: presentationData.theme,
            strings: presentationData.strings,
            dateTimeFormat: presentationData.dateTimeFormat,
            nameDisplayOrder: presentationData.nameDisplayOrder,
            animationCache: context.animationCache,
            animationRenderer: context.animationRenderer
        )
        // Decorative: the chat's own avatar button opens the profile, but this screen
        // is reached *from* the profile as often as from the chat, so it carries no
        // action of its own.
        self.avatarNode = ChatAvatarNavigationNode()

        // `PeerData(peerView:)` wants the raw peer view — the same thing the chat feeds
        // it — because the status line is built out of presences and cached data, not
        // just the peer.
        self.disposable.set((context.account.postbox.peerView(id: peerId)
        |> deliverOnMainQueue).start(next: { [weak self] peerView in
            guard let self else {
                return
            }
            self.titleView.titleContent = .peer(
                peerView: ChatTitleContent.PeerData(peerView: peerView),
                customTitle: nil,
                customSubtitle: nil,
                onlineMemberCount: (nil, nil),
                isScheduledMessages: false,
                isMuted: nil,
                customMessageCount: nil,
                hidePeerStatus: false,
                isEnabled: false
            )
            if let peer = peerViewMainPeer(peerView) {
                self.avatarNode.setPeer(
                    context: context,
                    theme: presentationData.theme,
                    peer: EnginePeer(peer),
                    overrideImage: peer.id == context.account.peerId ? .savedMessagesIcon : nil
                )
            }
        }))
    }

    deinit {
        self.disposable.dispose()
    }
}
