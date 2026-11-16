#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVSearchView

/// Native tvOS search: system keyboard grid + suggestions (`.searchable`), results as a
/// card grid with Sort / Upload date filters.
struct TVSearchView: View {
    @Environment(\.innerTubeAPI) private var api
    @Environment(TVNavigator.self) private var navigator
    @State private var vm: SearchViewModel?
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let vm {
                    content(vm)
                } else {
                    TVLoadingView().frame(height: 500)
                }
            }
            .padding(.bottom, 80)
        }
        .searchable(text: $text, prompt: "Search YouTube")
        .searchSuggestions {
            if let vm {
                ForEach(vm.suggestions.prefix(8), id: \.self) { suggestion in
                    Text(suggestion).searchCompletion(suggestion)
                }
            }
        }
        .onSubmit(of: .search) { runSearch() }
        .task {
            if vm == nil { vm = SearchViewModel(api: api) }
        }
        .task(id: text) {
            guard let vm else { return }
            vm.query = text
            await vm.updateSuggestions(for: text)
        }
    }

    @ViewBuilder
    private func content(_ vm: SearchViewModel) -> some View {
        if !vm.results.isEmpty || (didSearch && vm.isLoading) {
            // The filter bar stays put while results (re)load, so changing Sort or Upload date
            // doesn't pull the focused control out from under the remote.
            filterBar(vm)
            if vm.results.isEmpty {
                TVLoadingView(message: "Searching…").frame(height: 500)
            } else {
                TVVideoGrid(
                    videos: vm.results.uniquedByID(),
                    onReachEnd: { vm.loadMore() },
                    pageKey: vm.results.count,
                    onSelect: { navigator.play($0) }
                )
            }
        } else if vm.isLoading {
            TVLoadingView(message: "Searching…").frame(height: 500)
        } else if let error = vm.error {
            TVMessageView(
                systemImage: AppSymbol.warningOutline,
                title: "Search failed",
                message: error.localizedDescription,
                actionTitle: "Try Again"
            ) { runSearch() }
            .frame(height: 500)
        } else if !vm.query.isEmpty, vm.query == text, !text.isEmpty, didSearch {
            TVMessageView(systemImage: AppSymbol.search, title: "No results for “\(text)”")
                .frame(height: 500)
        } else {
            TVMessageView(
                systemImage: AppSymbol.search,
                title: "Search YouTube",
                message: "Find videos, channels and playlists."
            )
            .frame(height: 500)
        }
    }

    @State private var didSearch = false

    private func runSearch() {
        guard let vm, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        vm.query = text
        didSearch = true
        vm.search()
    }

    private func filterBar(_ vm: SearchViewModel) -> some View {
        HStack(spacing: 24) {
            Menu {
                ForEach(SearchFilter.SortOrder.allCases, id: \.self) { order in
                    Button(order.label) {
                        var filter = vm.filter
                        filter.sortOrder = order
                        vm.applyFilter(filter)
                    }
                }
            } label: {
                Label("Sort: \(vm.filter.sortOrder.label)", systemImage: AppSymbol.sortOrder)
            }
            Menu {
                ForEach(SearchFilter.UploadDate.allCases, id: \.self) { date in
                    Button(date.label) {
                        var filter = vm.filter
                        filter.uploadDate = date
                        vm.applyFilter(filter)
                    }
                }
            } label: {
                Label(vm.filter.uploadDate.label, systemImage: AppSymbol.calendar)
            }
            Spacer()
        }
        .padding(.horizontal, TVLayout.pageInset)
        .padding(.top, 12)
        .focusSection()
    }
}
#endif
