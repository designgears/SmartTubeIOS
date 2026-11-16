#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - Info panels

struct TVUpNextPanel: View {
    let vm: PlaybackViewModel
    let onSelect: (Video) -> Void

    var body: some View {
        let videos = vm.relatedVideos.uniquedByID()
        if videos.isEmpty {
            Text("No related videos yet")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(videos) { video in
                        Button {
                            onSelect(video)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                TVVideoThumbnail(video: video, pointWidth: 340)
                                    .frame(width: 340, height: 191)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .hoverEffect(.highlight)
                                TVVideoCaption(video: video, titleFont: .caption.weight(.semibold))
                                    .frame(width: 340, height: 96, alignment: .topLeading)
                            }
                        }
                        .buttonStyle(.borderless)
                        .onAppear {
                            if let index = videos.firstIndex(where: { $0.id == video.id }),
                                TVLoadMoreTrigger.isNearEnd(index, of: videos.count)
                            {
                                vm.loadMoreRelated()
                            }
                        }
                    }
                    // Up Next pages on as far as YouTube's suggestions go.
                    TVLoadMoreTrigger(pageKey: vm.relatedPagesLoaded) { vm.loadMoreRelated() }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }
}

struct TVChaptersPanel: View {
    let vm: PlaybackViewModel
    let onSelect: (TimeInterval) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 32) {
                ForEach(vm.chapters) { chapter in
                    Button {
                        onSelect(chapter.startTime)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(TVNativePlayer.Coordinator.timeLabel(chapter.startTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(chapter.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(2)
                        }
                        .frame(width: 320, height: 120, alignment: .topLeading)
                        .padding(20)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 30)
        }
        .scrollClipDisabled()
    }
}
#endif
