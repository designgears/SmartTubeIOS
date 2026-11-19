# Twitch and Kick on Apple TV

Date: 2026-11-19. Branch: `tvos-overhaul`.

## Goal

Watch Twitch and Kick in SmartTube on Apple TV next to YouTube:

- **Twitch**: sign in with a code on twitch.tv/activate (device code flow) and use the
  account's real follows. Live streams and past broadcasts (VODs).
- **Kick**: channels followed inside SmartTube (stored on the device; Kick's sign-in has
  no TV-friendly flow). Live streams and past broadcasts.
- **Where**: a Twitch tab and a Kick tab in the sidebar, and live followed channels mixed
  into Home's Live Now (with a platform badge).
- **Extras**: read-only live chat beside the video; past broadcasts on each channel page.

Out of scope for now: following/unfollowing on Twitch from the app (Twitch removed that
API), sending chat, clips, top-streams browsing, Twitch subscriber ad-free playback.

## Findings (2026-11-19, live requests)

- Twitch playback: GQL `PlaybackAccessToken` (persisted query, web client ID
  `kimne78kx3ncx6brgo4mv6wki5h1ko`, no user token) + `usher.ttvnw.net/api/channel/hls/<login>.m3u8`
  gives H.264/AAC HLS, 160p-1080p60. AVPlayer plays it as is. VODs: same token query with
  `isVod`, then `usher.ttvnw.net/vod/<id>.m3u8`. Non-subscribers get Twitch's own ads in the stream.
- Twitch account data: Helix (`api.twitch.tv/helix`) with the user's token and the user's
  own registered **public** client ID: `users`, `channels/followed`, `streams/followed`,
  `videos?type=archive`. Device code flow: `id.twitch.tv/oauth2/device` then `/token`;
  refresh with client ID only (public client). Scope: `user:read:follows`.
- Kick: `kick.com/api/v2/channels/<slug>` answers without an account (browser User-Agent):
  `livestream`, `playback_url` (Amazon IVS HLS), `user.profile_pic`, `chatroom.id`.
  Past broadcasts: `kick.com/api/v2/channels/<slug>/videos`. The official API
  (`api.kick.com/public/v1`) needs a registered app; not used. Kick sits behind
  Cloudflare: check from the Apple TV, not only from Linux.
- Chat: Twitch IRC over WebSocket (`wss://irc-ws.chat.twitch.tv`, anonymous `justinfan`
  login, read-only). Kick: Pusher WebSocket, channel `chatrooms.<id>.v2`.

## Design

- **Identity**: no model change. `Video.id` / `Channel.id` carry a platform prefix:
  `twitch:live:<login>`, `twitch:vod:<id>`, `twitch:<login>` (channel),
  `kick:live:<slug>`, `kick:vod:<uuid>`, `kick:<slug>`. `StreamPlatform(id:)` derives the
  platform; everything unprefixed is YouTube. Prefixed ids never collide in the history,
  watched, preload or state stores.
- **Core (Foundation only)**: `TwitchClient`, `KickClient` (actors, injectable URLSession,
  JSON parsing as static functions tested with fixtures), `TwitchAuth` (device flow, token
  refresh), `ExternalFollowStore` (Kick follows), `ExternalLiveStore` (followed channels
  live now, both platforms; refresh like `SubscriptionLiveStore`), `ExternalStreamResolver`
  (id -> fresh HLS URL at play time; Twitch tokens expire).
- **Playback**: one direct-HLS branch in `PlaybackViewModel` for prefixed ids (shared with
  the downloaded-file path, not a new fallback branch). YouTube-only features are skipped for
  them: SponsorBlock, DeArrow, related/Up Next, history and watched sync, likes, comments,
  speed memory, chapters.
- **UI (tvOS)**: Twitch and Kick tabs (Live, Following, Search), a channel page (live
  card, past broadcasts, Follow for Kick), Settings > Twitch account. Home's Live Now merges
  `ExternalLiveStore` with YouTube's live list. Chat: a panel beside the video, toggled from
  the player's transport bar.
- **Twitch client ID**: the user's own app (public client). Read from a gitignored
  `twitch-client-id.txt` resource, else Settings. Without it Twitch still plays streams and
  VODs; only sign-in is off.

## Phases (each: unit tests, `just`-equivalent checks on the Mac, sim check, commit)

1. Core clients and parsing: Twitch GQL/usher/Helix, Kick channel/videos/search; ids.
2. Playback of Twitch/Kick live and VODs; YouTube-only features gated.
3. Kick follows + Twitch sign-in + `ExternalLiveStore`.
4. Tabs, channel pages, search; Home Live Now merge.
5. Live chat panel.
6. Device check on the Apple TV (Kick behind Cloudflare, Twitch ads, chat), deploy.
