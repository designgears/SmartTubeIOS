import Testing

/// Suites that post or react to the process-wide `.activeChannelDidChange` and
/// `AccountScope.didChangeNotification`: a channel or account switch in one suite makes every
/// live BrowseViewModel/HomeViewModel reload, which broke exact fetch-count assertions in
/// another suite running in parallel.
@Suite(.serialized)
enum ActiveChannelSuites {}
