import Foundation
import SmartTubeIOSCore

// MARK: - Watch-page details and votes

extension PlaybackViewModel {
    /// Takes the watch page's details (date, exact views/likes, channel) and, when enabled,
    /// fetches likes/dislikes from Return YouTube Dislike — dropped if the video changed meanwhile.
    func applyWatchPageDetails(_ details: VideoDetails?, for video: Video) {
        videoDetails = details
        guard settings.showDislikes else { return }
        let videoId = video.id
        Task { [weak self] in
            let votes = await ReturnYouTubeDislike.shared.votes(for: videoId)
            guard let self, self.currentVideo?.id == videoId else { return }
            self.votes = votes
        }
    }
}
