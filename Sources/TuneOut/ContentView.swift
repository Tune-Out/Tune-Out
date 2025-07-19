// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import SkipAV
import TuneOutModel

enum ContentTab: String, Hashable {
    case browse, collections, music, search, settings
}

struct ContentView: View {
    @AppStorage("tab") var tab = ContentTab.browse
    @AppStorage("appearance") var appearance = ""
    @State var viewModel = ViewModel()

    var body: some View {
        TabView(selection: $tab) {
            BrowseStationsView()
                .tabItem { Label("Browse", systemImage: "list.bullet") }
                .tag(ContentTab.browse)

            NavigationStack {
                // CollectionsListView() // FIXME
                FavoritesListView()
                    .navigationTitle("Favorites")
                    .stationNavigationDestinations()
            }
                .tabItem { Label("Collections", systemImage: "star.fill") }
                .tag(ContentTab.collections)

            MusicPlayerView()
            .tabItem {
                Label {
                    Text("Now Playing")
                } icon: {
                    Image("MusicCast", bundle: .module)
                }
            }
            .tag(ContentTab.music)

            NavigationStack {
                StationListView(query: StationQuery(title: "Search"))
                    .navigationTitle("Search")
                    .stationNavigationDestinations()
            }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(ContentTab.search)

            NavigationStack {
                SettingsView(appearance: $appearance)
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(ContentTab.settings)
        }
//            .tabViewBottomAccessory {
//                RadioPlayerView()
//            }
        .environment(viewModel)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}

extension View {
    /// Standard navigation destinations for station browsing
    public func stationNavigationDestinations() -> some View {
        self
        .navigationDestination(for: StationQuery.self) {
            StationListView(query: $0)
        }
        .navigationDestination(for: StationInfo.self) {
            StationInfoView(station: $0)
        }
    }
}

struct MusicPlayerView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var volume = 1.0

    var body: some View {
        VStack {
            if let station = viewModel.nowPlaying {
                Spacer()

                if let favicon = station.favicon, let faviconURL = URL(string: favicon) {
                    AsyncImage(url: faviconURL) { image in
                        image.resizable()
                    } placeholder: {
                    }
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                }

                Spacer()

                Text(station.name.trimmingCharacters(in: .whitespacesAndNewlines))
                    .multilineTextAlignment(.center)
                    #if !SKIP
                    .textSelection(.enabled)
                    #endif
                    .font(.title)
                    .lineLimit(3)
                    .padding()

                Text(viewModel.curentTrackTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                    .multilineTextAlignment(.center)
                    #if !SKIP
                    .textSelection(.enabled)
                    #endif
                    .font(.title2)
                    .lineLimit(5)
                    .padding()

                Spacer()

                HStack {
                    Spacer()
                    Button {
                        // Back
                    } label: {
                        Image("skip_previous_skip_previous_fill1_symbol", bundle: .module, label: Text("Skip to the previous station"))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                    }

                    Spacer()

                    if viewModel.playing {
                        Button {
                            viewModel.pause()
                        } label: {
                            Image("pause_pause_fill1_symbol", bundle: .module, label: Text("Pause the current station"))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                        }
                    } else {
                        Button {
                            viewModel.play(station)
                        } label: {
                            Image("play_arrow_play_arrow_fill1_symbol", bundle: .module, label: Text("Play the current station"))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                        }
                    }

                    Spacer()

                    Button {
                        // Next
                    } label: {
                        Image("skip_next_skip_next_fill1_symbol", bundle: .module, label: Text("Skip to the next station"))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                    }

                    Spacer()
                }

                Slider(value: $volume, in: 0.0...1.0)
                    .padding()
                    .accessibilityLabel(Text("Volume"))
                    .onAppear {
                        self.volume = Double(viewModel.player.volume)
                    }
                    .onChange(of: volume) {
                        viewModel.player.volume = Float(volume)
                    }

                Spacer()
            } else {
                Text("No Station Selected")
                    .font(.title)
            }
        }
    }
}

struct BrowseStationsView: View {
    enum BrowseStatonMode: Hashable {
        case countries
        case tags
    }

    let usePicker = true // doesn't look great on Android
    @State var selectedStationMode = BrowseStatonMode.countries

    #if os(iOS) || os(Android)
    let pickerPlacement = ToolbarItemPlacement.navigationBarLeading
    #else
    let pickerPlacement = ToolbarItemPlacement.navigation
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if usePicker {
                    TabView(selection: $selectedStationMode) {
                        CountriesListView()
                            .navigationTitle("Countries")
                            .navigationBarTitleDisplayMode(.large)
                            .tag(BrowseStatonMode.countries)
                        TagsListView()
                            .navigationTitle("Tags")
                            .navigationBarTitleDisplayMode(.large)
                            .tag(BrowseStatonMode.tags)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .toolbar {
                        ToolbarItem(placement: pickerPlacement) {
                            Picker("Selection", selection: $selectedStationMode) {
                                Text("Countries").tag(BrowseStatonMode.countries)
                                Text("Tags").tag(BrowseStatonMode.tags)
                                //Text("Search").tag(BrowseStatonMode.tags)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 230)
                        }
                    }
                } else {
                    List {
                        NavigationLink("Countries", value: BrowseStatonMode.countries)
                        NavigationLink("Tags", value: BrowseStatonMode.tags)
                    }
                    .navigationTitle(Text("Browse Stations"))
                    .navigationDestination(for: BrowseStatonMode.self) { mode in
                        switch mode {
                        case .countries: CountriesListView().navigationTitle("Countries")
                        case .tags: TagsListView().navigationTitle("Tags")
                        }
                    }
                }
            }
            .stationNavigationDestinations()
        }
    }
}

struct CountriesListView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var sortOption: StationGroupSortOption = .name
    @State var countries: [CountryInfo] = []
    @State var loading = false
    @State var error: Error? = nil

    var body: some View {
        List {
            if self.loading {
                HStack {
                    ProgressView()
                    Text("Loading…")
                }
            } else if let error = self.error {
                Text("Error: \(error.localizedDescription)")
            } else {
                Section {
                    ForEach(countries.filter({ $0.name == Locale.current.region?.identifier }), id: \.name) { country in
                        countryLink(country)
                    }
                }
                Section {
                    ForEach(countries.filter({ $0.name != Locale.current.region?.identifier }), id: \.name) { country in
                        countryLink(country)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Picker(selection: $sortOption) {
                    ForEach(StationGroupSortOption.allCases) { opt in
                        Text(opt.localizedTitle)
                    }
                } label: {
                    Label {
                        Text("Sort")
                    } icon: {
                        Image("Sort", bundle: .module)
                    }

                }
                .pickerStyle(.menu)
                .onChange(of: sortOption) {
                    withAnimation {
                        sortCountries()
                    }
                }
            }
        }
        .task {
            if self.countries.isEmpty {
                await loadCountries()
            }
        }
        .refreshable {
            await loadCountries()
        }
    }

    func loadCountries() async {
        self.loading = true
        self.error = nil
        defer {
            self.loading = false
        }
        do {
            logger.log("loading countries…")
            let countries = try await APIClient.shared.fetchCountries(params: viewModel.queryParams).filter {
                // FIXME: the https://docs.radio-browser.info/#list-of-countries endpoint doesn't normalize these to be uppercase, so there are duplicates in lower-case
                $0.name == $0.name.uppercased()
            }
            withAnimation {
                self.countries = countries
                sortCountries()
            }
            logger.log("loaded \(self.countries.count) countries")
        } catch {
            logger.error("error loading countries: \(error)")
            self.error = error
        }
    }

    func countryLink(_ country: CountryInfo) -> some View {
        NavigationLink(value: StationQuery(title: country.localizedName, params: StationQueryParams(countrycode: country.name))) {
            Label {
                HStack {
                    Text(country.localizedName)
                    Spacer()
                    //Text("\(country.stationcount, format: .number)") // not supported in Skip
                    //Text(country.stationcount.formatted())
                    Text(NumberFormatter.localizedString(from: country.stationcount as NSNumber, number: .decimal))
                }
            } icon: {
                Text(emojiFlag(countryCode: country.normalizedCountryCode))
                    .font(.title)
            }
        }
    }

    func sortCountries() {
        self.countries = sortOption.sort(countries: self.countries)
    }
}

struct TagsListView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var sortOption: StationGroupSortOption = .stationCount
    @State var tags: [TagInfo] = []
    @State var showAdditionalTags: Bool = false
    @State var loading = false
    @State var error: Error? = nil

    var body: some View {
        List {
            if self.loading {
                HStack {
                    ProgressView()
                    Text("Loading…")
                }
            } else if let error = self.error {
                Text("Error: \(error.localizedDescription)")
            } else {
                // first section is for known and localized tag names
                Section {
                    ForEach(tags.filter({ $0.localizedTitle != nil }), id: \.name) { tag in
                        tagLink(tag)
                    }
                }
                // second section is for the remaining tag names
                Section {
                    if showAdditionalTags {
                        // we still filter on stationcount > 10 because many stations create nonsense tags
                        ForEach(tags.filter({ $0.localizedTitle == nil && $0.stationcount > 10 }), id: \.name) { tag in
                            tagLink(tag)
                        }
                    }

                    Button {
                        withAnimation {
                            showAdditionalTags = !showAdditionalTags
                        }
                    } label: {
                        if !showAdditionalTags {
                            Text(LocalizedStringResource("More…", comment: "button title to expand the list of tags in the browse stations view"))
                        } else {
                            Text(LocalizedStringResource("Show Less", comment: "button title to collapse the list of tags in the browse stations view"))
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Picker(selection: $sortOption) {
                    ForEach(StationGroupSortOption.allCases) { opt in
                        Text(opt.localizedTitle)
                    }
                } label: {
                    Label {
                        Text("Sort")
                    } icon: {
                        Image("Sort", bundle: .module)
                    }

                }
                .pickerStyle(.menu)
                .onChange(of: sortOption) {
                    withAnimation {
                        sortTags()
                    }
                }
            }
        }
        .task {
            if self.tags.isEmpty {
                await loadTags()
            }
        }
        .refreshable {
            await loadTags()
        }
    }

    func loadTags() async {
        self.loading = true
        self.error = nil
        defer {
            self.loading = false
        }
        do {
            logger.log("loading tags…")
            let tags = try await APIClient.shared.fetchTags(params: viewModel.queryParams)
            withAnimation {
                self.tags = tags
                sortTags()
            }
            logger.log("loaded \(self.tags.count) tags")
        } catch {
            logger.error("error loading tags: \(error)")
            self.error = error
        }
    }

    func tagLink(_ tag: TagInfo) -> some View {
        NavigationLink(value: StationQuery(title: tag.localizedName, params: StationQueryParams(tag: tag.name))) {
            Label {
                HStack {
                    Text(tag.localizedName)
                    Spacer()
                    //Text("\(country.stationcount, format: .number)") // not supported in Skip
                    Text(NumberFormatter.localizedString(from: tag.stationcount as NSNumber, number: .decimal))
                }
            } icon: {
                //Text(emojiFlag(countryCode: country.normalizedCountryCode))
                //    .font(.title)
            }
        }
    }

    func sortTags() {
        self.tags = sortOption.sort(tags: self.tags)
    }
}

extension StationQueryParams {
    var queryString: String {
        get {
            self.name ?? ""
        }

        set {
            self.name = newValue.isEmpty ? nil : newValue
        }
    }
}

struct StationListView: View {
    @State var query: StationQuery
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var stations: [StationInfo] = []
    @State var error: Error? = nil
    @State var loading = false
    @State var complete = true
    let queryBatchSize = 50

    var body: some View {
        ZStack {
            List {
                if let error = self.error {
                    Text("Error: \(error.localizedDescription)")
                } else {
                    ForEach(stations, id: \.stationuuid) { station in
                        stationRow(station)
                    }
                    if !complete {
                        HStack {
                            ProgressView()
                            Text("Loading…")
                        }
                        .task(id: self.stations.count) {
                            logger.log("loading from \(stations.count) (loading=\(loading))")
                            await loadStations()
                        }
                    }
                }
            }
            if stations.isEmpty && complete && !loading {
                if self.query.params.queryItems.isEmpty {
                    VStack {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                        Text("Search Stations")
                            .font(.title)
                    }
                } else {
                    Text("No Stations Found")
                        .font(.title)
                }
            }
        }
        .navigationTitle(query.title)
        .toolbar {
            ToolbarItem {
                Picker(selection: $query.sortOption) {
                    ForEach(StationSortOption.allCases) { opt in
                        Text(opt.localizedTitle)
                    }
                } label: {
                    Label {
                        Text("Sort")
                    } icon: {
                        Image("Sort", bundle: .module)
                    }

                }
                .pickerStyle(.menu)
            }
        }
        .task(id: query) {
            // clear stations so the query is re-fetched with the new sort
            await loadStations(clear: true)
        }
        // the only reason to make this refreshable is if we were to use the "Random" search (which doesn't work), otherwise it just interferes with the scroll up to show the search field
//        .refreshable {
//            await loadStations(clear: true)
//        }
        .searchable(text: $query.params.queryString)
    }

    func loadStations(clear: Bool = false) async {
        self.loading = true
        if clear {
            self.stations.removeAll()
        }
        defer {
            self.loading = false
        }
        // do nothing when there are no query parameters
        if self.query.params.queryItems.isEmpty {
            return
        }
        do {
            let (sortAttr, reverse) = query.sortOption.sortAttribute
            let params = QueryParams(order: sortAttr, reverse: reverse, hidebroken: true, offset: self.stations.count, limit: queryBatchSize)
            logger.log("loading stations for \(query.params.queryItems)…")
            var stations = try await APIClient.shared.searchStations(query: query.params, params: params)
            self.complete = stations.count < queryBatchSize
            if !stations.isEmpty {
                stations = cleanup(stations)
                self.updateStations(ViewModel.unique(self.stations + stations))
            }
            logger.log("loaded \(self.stations.count) stations")
        } catch {
            logger.error("error loading stations: \(error)")
            // we don't do this because we might have a Swift cancellation error or the Compose equivalent like
            /// `error loading stations: skip.lib.ErrorException: androidx.compose.runtime.LeftCompositionCancellationException: The coroutine scope left the composition`
            // self.error = error
        }
    }

    @MainActor func updateStations(_ stations: [StationInfo]) {
        withAnimation {
            self.stations = stations
        }
    }

    func cleanup(_ stations: [StationInfo]) -> [StationInfo] {
        stations.map {
            var station = $0
            station.name = station.name.trimmingCharacters(in: .whitespacesAndNewlines)
            station.tags = station.tags?.trimmingCharacters(in: .whitespacesAndNewlines)
            return station
        }
    }

    func stationRow(_ station: StationInfo) -> some View {
        NavigationLink(value: station) {
            StationInfoRowView(station: station, showIcon: false)
        }
    }
}

struct StationInfoFormView: View {
    let title: LocalizedStringResource
    let value: String?

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .frame(alignment: .leading)
            Spacer()
            Text(value ?? "")
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(alignment: .trailing)
        }
    }
}

struct StationInfoView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    let station: StationInfo

    var body: some View {
        Form {
            StationInfoFormView(title: LocalizedStringResource("Station Name"), value: station.name)
            StationInfoFormView(title: LocalizedStringResource("Country"), value: station.country)
            StationInfoFormView(title: LocalizedStringResource("Bit Rate"), value: station.bitrate?.description)
            StationInfoFormView(title: LocalizedStringResource("Tags"), value: station.tags)
            if let homepage = station.homepage, let homepageURL = URL(string: homepage) {
                Link(homepage, destination: homepageURL)
            }

            if let favicon = station.favicon, let faviconURL = URL(string: favicon) {
                AsyncImage(url: faviconURL) { image in
                    image.resizable()
                } placeholder: {
                }
                .scaledToFit()
                //.frame(width: 100, height: 100)
            }
        }
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Button {
                    if viewModel.isFavorite(station) {
                        viewModel.unfavorite(station)
                    } else {
                        viewModel.favorite(station)
                    }
                } label: {
                    if viewModel.isFavorite(station) {
                        Image("star_star_fill1_symbol", bundle: .module, label: Text("Unfavorite"))
                            .resizable()
                            .foregroundStyle(Color.yellow)
                            .frame(width: 30, height: 30)
                    } else {
                        Image("star_star_fill1_symbol", bundle: .module, label: Text("Favorite"))
                            .resizable()
                            .foregroundStyle(Color.gray)
                            .frame(width: 30, height: 30)
                    }
                }
            }

            ToolbarItem {
                if viewModel.isPlaying(station) {
                    Button {
                        viewModel.pause()
                    } label: {
                        Image("pause_pause_fill1_symbol", bundle: .module, label: Text("Pause"))
                            .resizable()
                            .font(.title)
                            .frame(width: 25, height: 25)
                    }
                } else {
                    Button {
                        viewModel.play(station)
                    } label: {
                        Image("play_arrow_play_arrow_fill1_symbol", bundle: .module, label: Text("Play"))
                            .resizable()
                            .frame(width: 25, height: 25)
                    }
                }
            }
        }
    }
}

extension View {
    /// Converts a country code like "US" into the Emoji symbol for the country's flag
    public func emojiFlag(countryCode: String) -> String {
        if countryCode.count != 2 {
            return "🏳️" // Return white flag for invalid codes
        }
        let countryCode = countryCode.uppercased()
        let offset = 127397
        #if SKIP
        // Build the string from the two Unicode code points
        return String(intArrayOf(countryCode[0].code + offset, countryCode[1].code + offset), 0, 2)
        #else
        let codes = countryCode.unicodeScalars.compactMap {
            UnicodeScalar($0.value + UInt32(offset))
        }
        return String(codes.map({ Character($0) }))
        #endif
    }
}


struct StationQuery: Hashable {
    var title: String
    var params: StationQueryParams = StationQueryParams()
    var sortOption: StationSortOption = .popularity
}

enum StationSortOption: Identifiable, Hashable, CaseIterable {
    case name
    case popularity
    case trend
    case random

    var id: StationSortOption {
        self
    }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .name: return LocalizedStringResource("Name")
        case .popularity: return LocalizedStringResource("Popularity")
        case .trend: return LocalizedStringResource("Trend")
        case .random: return LocalizedStringResource("Random")
        }
    }

//    func sort(_ stations: [StationInfo]) -> [StationInfo] {
//        stations.sorted {
//            switch self {
//            case .name:
//                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
//            case .popularity:
//                return ($0.votes ?? 0) > ($1.votes ?? 0)
//            case .trend:
//                return ($0.clicktrend ?? 0) > ($1.clicktrend ?? 0)
//            }
//        }
//    }

    var sortAttribute: (attribute: String, reverse: Bool?) {
        switch self {
        case .name: return (StationInfo.CodingKeys.name.rawValue, false)
        case .popularity: return (StationInfo.CodingKeys.votes.rawValue, true)
        case .trend: return (StationInfo.CodingKeys.clicktrend.rawValue, true)
        case .random: return ("random", nil)
        }
    }
}

enum StationGroupSortOption: Identifiable, Hashable, CaseIterable {
    case name
    case stationCount

    var id: StationGroupSortOption {
        self
    }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .name: return LocalizedStringResource("Name")
        case .stationCount: return LocalizedStringResource("Station Count")
        }
    }

    func sort(countries: [CountryInfo]) -> [CountryInfo] {
        countries.sorted {
            switch self {
            case .name:
                return $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
            case .stationCount:
                return $0.stationcount > $1.stationcount
            }
        }
    }

    func sort(tags: [TagInfo]) -> [TagInfo] {
        tags.sorted {
            switch self {
            case .name:
                return $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
            case .stationCount:
                return $0.stationcount > $1.stationcount
            }
        }
    }
}

extension CountryInfo {
    var localizedName: String {
        Locale.current.localizedString(forRegionCode: self.name) ?? self.name
    }

    var normalizedCountryCode: String {
        // TODO: fixup invalid names and convert to known country codes
        self.name
    }
}

extension StationInfo {
    var localizedTagList: String {
        (self.tags ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { TagInfo(name: $0, stationcount: 0) }
            .compactMap(\.localizedTitle)
            .joined(separator: ", ")
    }
}

extension TagInfo {
    var localizedName: String {
        self.localizedTitle ?? self.name
    }

    var localizedTitle: String? {
        switch self.name.lowercased() {
        case "jazz": return NSLocalizedString("Jazz", bundle: .module, comment: "station tag name for the jazz music genre")
        case "rock": return NSLocalizedString("Rock", bundle: .module, comment: "station tag name for the rock music genre")
        case "country": return NSLocalizedString("Country", bundle: .module, comment: "station tag name for the country music genre")
        case "pop": return NSLocalizedString("Pop", bundle: .module, comment: "station tag name for the pop music genre")
        case "music": return NSLocalizedString("Music", bundle: .module, comment: "station tag name for the music music genre")
        case "classical": return NSLocalizedString("Classical", bundle: .module, comment: "station tag name for the classical music genre")
        case "talk": return NSLocalizedString("Talk", bundle: .module, comment: "station tag name for the talk music genre")
        case "hits": return NSLocalizedString("Hits", bundle: .module, comment: "station tag name for the hits music genre")
        case "dance": return NSLocalizedString("Dance", bundle: .module, comment: "station tag name for the dance music genre")
        case "oldies": return NSLocalizedString("Oldies", bundle: .module, comment: "station tag name for the oldies music genre")
        case "electronic": return NSLocalizedString("Electronic", bundle: .module, comment: "station tag name for the electronic music genre")
        case "40s": return NSLocalizedString("40s", bundle: .module, comment: "station tag name for the 40s music genre")
        case "50s": return NSLocalizedString("50s", bundle: .module, comment: "station tag name for the 50s music genre")
        case "60s": return NSLocalizedString("60s", bundle: .module, comment: "station tag name for the 60s music genre")
        case "70s": return NSLocalizedString("70s", bundle: .module, comment: "station tag name for the 70s music genre")
        case "80s": return NSLocalizedString("80s", bundle: .module, comment: "station tag name for the 80s music genre")
        case "90s": return NSLocalizedString("90s", bundle: .module, comment: "station tag name for the 90s music genre")
        case "house": return NSLocalizedString("House", bundle: .module, comment: "station tag name for the house music genre")
        case "folk": return NSLocalizedString("Folk", bundle: .module, comment: "station tag name for the folk music genre")
        case "metal": return NSLocalizedString("Metal", bundle: .module, comment: "station tag name for the metal music genre")
        case "soul": return NSLocalizedString("Soul", bundle: .module, comment: "station tag name for the soul music genre")
        case "indie": return NSLocalizedString("Indie", bundle: .module, comment: "station tag name for the indie music genre")
        case "techno": return NSLocalizedString("Techno", bundle: .module, comment: "station tag name for the techno music genre")
        case "sports": return NSLocalizedString("Sports", bundle: .module, comment: "station tag name for the sports music genre")
        case "top 40": return NSLocalizedString("Top 40", bundle: .module, comment: "station tag name for the top music genre")
        case "alternative": return NSLocalizedString("News", bundle: .module, comment: "station tag name for the alternative music genre")
        case "public radio": return NSLocalizedString("Public Radio", bundle: .module, comment: "station tag name for the public radio music genre")
        case "adult contemporary": return NSLocalizedString("Adult Contemporary", bundle: .module, comment: "station tag name for the adult contemporary music genre")
        case "classic rock": return NSLocalizedString("Classic Rock", bundle: .module, comment: "station tag name for the classic rock music genre")
        case "news": return NSLocalizedString("News", bundle: .module, comment: "station tag name for the news genre")
        // TODO: fill in all the popular tags…
        default: return nil
        }
    }
}

struct FavoritesListView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel

    var body: some View {
        List {
            ForEach(viewModel.favorites) { item in
                NavigationLink(value: item) {
                    StationInfoRowView(station: item, showIcon: true)
                }
            }
            .onDelete { offsets in
                viewModel.favorites.remove(atOffsets: offsets)
            }
            .onMove { fromOffsets, toOffset in
                viewModel.favorites.move(fromOffsets: fromOffsets, toOffset: toOffset)
            }
        }
    }
}

struct StationInfoRowView: View {
    let station: StationInfo
    let showIcon: Bool
    @Environment(ViewModel.self) var viewModel: ViewModel

    var body: some View {
        Label {
            HStack {
                if showIcon, let favicon = station.favicon, let faviconURL = URL(string: favicon) {
                    AsyncImage(url: faviconURL) { image in
                        image.resizable()
                    } placeholder: {
                    }
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                }
                VStack(alignment: .leading) {
                    Text(station.name.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.headline)
                        .lineLimit(1)
                    Text(station.localizedTagList)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                //Text(station.languagecodes ?? "")
            }
        } icon: {
            // TODO: use an image based on the tag(s)…
            //if let favicon = station.favicon {
            // too much noise for the station list
            //AsyncImage(url: URL(string: favicon))
            //}
        }
    }
}

struct SettingsView: View {
    @Binding var appearance: String

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(buildNumber))")
            }
            HStack {
                PlatformHeartView()
                Text("Powered by [Skip](https://skip.tools)")
            }
        }
    }
}

/// A view that shows a blue heart on iOS and a green heart on Android.
struct PlatformHeartView: View {
    var body: some View {
       #if SKIP
       ComposeView { ctx in // Mix in Compose code!
           androidx.compose.material3.Text("💚", modifier: ctx.modifier)
       }
       #else
       Text(verbatim: "💙")
       #endif
    }
}
