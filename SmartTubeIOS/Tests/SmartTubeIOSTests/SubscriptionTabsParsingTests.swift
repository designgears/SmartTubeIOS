import Foundation
import Testing

@testable import SmartTubeIOSCore

/// The Channels page reads the TV Subscriptions page's side list: every subscribed channel.
@Suite("Subscribed channels — TV Subscriptions side list")
struct SubscriptionTabsParsingTests {
    /// base64 of a protobuf wrapping "UCtestChannel0000000000A", URL-escaped as YouTube sends it.
    private let params = "igMaChhVQ3Rlc3RDaGFubmVsMDAwMDAwMDAwMEE%3D"

    private func page(tabs: [[String: Any]]) -> [String: Any] {
        [
            "responseContext": [:] as [String: Any],
            "contents": [
                "tvBrowseRenderer": [
                    "content": [
                        "tvSecondaryNavRenderer": [
                            "sections": [["tvSecondaryNavSectionRenderer": ["tabs": tabs]]]
                        ]
                    ]
                ]
            ],
        ]
    }

    private func tab(title: String, params: String?, avatar: String? = nil) -> [String: Any] {
        var browse: [String: Any] = ["browseId": "FEsubscriptions"]
        browse["params"] = params
        var renderer: [String: Any] = ["title": title, "endpoint": ["browseEndpoint": browse]]
        if let avatar { renderer["thumbnail"] = ["thumbnails": [["url": "//small"], ["url": avatar]]] }
        return ["tabRenderer": renderer]
    }

    @Test func readsTheChannelIdFromTabParams() {
        #expect(InnerTubeAPI.channelId(inTabParams: params) == "UCtestChannel0000000000A")
        #expect(InnerTubeAPI.channelId(inTabParams: "not base64!") == nil)
    }

    @Test func listsEveryChannelTabButAll() {
        let channels = InnerTubeAPI.parseSubscriptionTabs(
            from: page(tabs: [
                tab(title: "All", params: nil),
                tab(title: "Test Channel", params: params, avatar: "//yt3.example/avatar=s176"),
                tab(title: "Test Channel again", params: params),
            ]))
        #expect(channels.map(\.id) == ["UCtestChannel0000000000A"])
        #expect(channels.first?.title == "Test Channel")
        #expect(channels.first?.thumbnailURL?.absoluteString == "https://yt3.example/avatar=s176")
    }

    @Test func noSideListMeansNoChannels() {
        #expect(InnerTubeAPI.parseSubscriptionTabs(from: ["contents": [:] as [String: Any]]).isEmpty)
    }
}
