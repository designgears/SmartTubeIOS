import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Video details — watch page, dislikes, compact counts")
struct VideoDetailsTests {
    /// Trimmed from a real WEB `/next` response.
    private let next: [String: Any] = [
        "contents": [
            "twoColumnWatchNextResults": [
                "results": [
                    "results": [
                        "contents": [
                            [
                                "videoPrimaryInfoRenderer": [
                                    "dateText": ["simpleText": "Nov 15, 2026"],
                                    "relativeDateText": ["simpleText": "9 hours ago"],
                                    "viewCount": [
                                        "videoViewCountRenderer": [
                                            "viewCount": ["simpleText": "1,585,288 views"],
                                            "originalViewCount": "1585288",
                                        ]
                                    ],
                                    "videoActions": [
                                        "menuRenderer": [
                                            "topLevelButtons": [
                                                [
                                                    "segmentedLikeDislikeButtonViewModel": [
                                                        "likeButtonViewModel": [
                                                            "likeButtonViewModel": [
                                                                "toggleButtonViewModel": [
                                                                    "defaultButtonViewModel": [
                                                                        "buttonViewModel": [
                                                                            "title": "18K",
                                                                            "accessibilityText":
                                                                                "like this video along with 18,134 other people",
                                                                        ]
                                                                    ]
                                                                ]
                                                            ]
                                                        ]
                                                    ]
                                                ]
                                            ]
                                        ]
                                    ],
                                ]
                            ],
                            [
                                "videoSecondaryInfoRenderer": [
                                    "owner": [
                                        "videoOwnerRenderer": [
                                            "subscriberCountText": ["simpleText": "16.9M subscribers"],
                                            "thumbnail": [
                                                "thumbnails": [
                                                    ["url": "https://yt3.ggpht.com/a=s48"],
                                                    ["url": "https://yt3.ggpht.com/a=s176"],
                                                ]
                                            ],
                                        ]
                                    ]
                                ]
                            ],
                        ]
                    ]
                ]
            ]
        ]
    ]

    @Test func readsTheWatchPage() throws {
        let details = try #require(VideoDetails.parse(next: next))
        #expect(details.dateText == "Nov 15, 2026")
        #expect(details.relativeDateText == "9 hours ago")
        #expect(details.viewCount == 1_585_288)
        #expect(details.likeCount == 18_134)
        #expect(details.subscriberCountText == "16.9M subscribers")
        #expect(details.channelAvatarURL == URL(string: "https://yt3.ggpht.com/a=s176"))
    }

    @Test func noWatchPageRenderersMeansNoDetails() {
        #expect(VideoDetails.parse(next: ["contents": [:]]) == nil)
    }

    @Test func readsReturnYouTubeDislike() {
        let body = Data(#"{"id":"x","likes":18068,"dislikes":392,"rating":4.9,"viewCount":1573349}"#.utf8)
        #expect(VideoVotes.parse(body) == VideoVotes(likes: 18_068, dislikes: 392))
        #expect(VideoVotes.parse(Data("{}".utf8)) == nil)
    }

    @Test(arguments: [
        (950, "950"), (1_500, "1.5K"), (18_134, "18K"), (1_000_000, "1M"), (1_585_288, "1.5M"),
        (125_300_000, "125M"), (1_400_000_000, "1.4B"),
    ])
    func compactCounts(value: Int, expected: String) {
        #expect(compactCount(value) == expected)
    }
}

@Suite("Up Next paging — related continuation")
struct RelatedContinuationTests {
    private func continuationItem(_ token: String) -> [String: Any] {
        ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token]]]]
    }

    @Test func firstPageTokenComesFromSecondaryResults() async {
        let api = InnerTubeAPI()
        let next: [String: Any] = [
            "contents": [
                "twoColumnWatchNextResults": [
                    "secondaryResults": ["secondaryResults": ["results": [continuationItem("related_p2")]]]
                ]
            ],
            // Comments carry their own continuation; it must not be mistaken for Up Next's.
            "engagementPanels": [continuationItem("comments_token")],
        ]
        #expect(await api.relatedContinuation(in: next) == "related_p2")
    }

    @Test func laterPagesTokenComesFromAppendedItems() async {
        let api = InnerTubeAPI()
        let page: [String: Any] = [
            "onResponseReceivedEndpoints": [
                ["appendContinuationItemsAction": ["continuationItems": [continuationItem("related_p3")]]]
            ]
        ]
        #expect(await api.relatedContinuation(in: page) == "related_p3")
        #expect(await api.relatedContinuation(in: [:]) == nil)
    }
}
