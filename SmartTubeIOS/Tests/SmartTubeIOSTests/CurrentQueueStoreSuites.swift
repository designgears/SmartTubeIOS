import Testing

/// Every suite that mutates the process-wide `CurrentQueueStore.shared` is nested here.
/// `.serialized` only orders tests *within* a suite, so separate suites touching the same
/// singleton ran in parallel and cleared or replaced each other's queue mid-test.
@Suite(.serialized)
enum CurrentQueueStoreSuites {}
