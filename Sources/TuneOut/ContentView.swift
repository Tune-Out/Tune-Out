// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import SkipAV
import SkipSQL
import TuneOutModel
import AppFairUI

struct ContentView: View {
    @AppStorage("appearance") var appearance = ""
    @State var viewModel = ViewModel()

    var body: some View {
        TabView(selection: $viewModel.tab) {
            NavigationStack(path: $viewModel.browseNavigationPath) {
                BrowseStationsView()
                    .stationNavigationDestinations()
            }
                .tabItem { Label("Browse", systemImage: "list.bullet") }
                .tag(ContentTab.browse)

            NavigationStack(path: $viewModel.collectionsNavigationPath) {
                CollectionsListView()
                    .navigationTitle("Collections")
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
            .tag(ContentTab.nowPlaying)

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
        //.tabViewBottomAccessory { // TODO: future enhancement
        // TODO: make the miniplayer nicer
        //.overlay(alignment: .bottom) {
        //    MiniPlayerView()
        //}
        .environment(viewModel)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}

extension View {
    /// Standard navigation destinations for station browsing
    public func stationNavigationDestinations() -> some View {
        navigationDestination(for: NavPath.self) {
            switch $0 {
            case .stationQuery(let query): StationListView(query: query)
            case .apiStationInfo(let station): StationInfoView(station: station)
            case .storedStationInfo(let station): StationInfoView(station: station)
            case .stationCollection(let collection): StationCollectionView(collection: collection)
            case .browseStationMode(let mode):
                switch mode {
                //case .languages: LanguagesListView().navigationTitle("Languages")
                case .countries: CountriesListView().navigationTitle("Countries")
                case .tags: TagsListView().navigationTitle("Tags")
                }
            }
        }
    }
}

struct MiniPlayerView : View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // TODO: better adaptation to tab bar height
    let tabBarHeight = 88.0

    var body: some View {
        HStack {
            VStack {
                Text((viewModel.curentTrackTitle ?? viewModel.nowPlaying?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.title2)
                Text((viewModel.nowPlaying?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.title3)
            }
            .padding()
            .lineLimit(1)
            .multilineTextAlignment(.leading)
            #if !SKIP
            .truncationMode(.tail)
            #endif
            PlayPauseButton()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(BackgroundStyle.background.opacity(0.8))
        //.background(.ultraThinMaterial)
        .cornerRadius(12)
        #if SKIP
        .border(Color.gray, width: 0.5)
        #else
        .shadow(radius: 4) // shadow blurs the text in Skip as opposed to the radius
        #endif
        .padding(.horizontal)
        .opacity(viewModel.tab == .nowPlaying ? 0.0 : 1.0)
        .padding(.bottom, tabBarHeight)
        .onTapGesture {
            viewModel.tab = .nowPlaying
        }
    }
}

struct MusicPlayerView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var volume = 1.0
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var currentArtworkURL: URL? {
        if let url = viewModel.currentTrackArtwork {
            return url
        }
        if let favicon = viewModel.nowPlaying?.favicon, let faviconURL = URL(string: favicon) {
            return faviconURL
        }
        return nil
    }

    var body: some View {
        VStack {
            if let station = viewModel.nowPlaying {
                if verticalSizeClass == .regular {
                    Spacer()

                    if let artworkURL = self.currentArtworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image.resizable()
                        } placeholder: {
                        }
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                    }

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

                HStack {
                    Spacer()
                    Button {
                        self.viewModel.previousItem()
                    } label: {
                        Image("skip_previous_skip_previous_fill1_symbol", bundle: .module, label: Text("Skip to the previous station"))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                    }

                    Spacer()

                    PlayPauseButton()

                    Spacer()

                    Button {
                        self.viewModel.nextItem()
                    } label: {
                        Image("skip_next_skip_next_fill1_symbol", bundle: .module, label: Text("Skip to the next station"))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
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

                Text(viewModel.curentTrackTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                    .multilineTextAlignment(.center)
                    #if !SKIP
                    .textSelection(.enabled)
                    #endif
                    .font(.title2)
                    .lineLimit(5)
                    .frame(minHeight: 100, alignment: .top)
                    .padding()

                Spacer()
            } else {
                Text("No Station Selected")
                    .font(.title)
            }
        }
    }
}

struct PlayPauseButton : View {
    @Environment(ViewModel.self) var viewModel: ViewModel

    var body: some View {
        if viewModel.playerState == .playing {
            Button {
                viewModel.pause()
            } label: {
                Image("pause_pause_fill1_symbol", bundle: .module, label: Text("Pause the current station"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            }
        } else {
            Button {
                viewModel.play()
            } label: {
                Image("play_arrow_play_arrow_fill1_symbol", bundle: .module, label: Text("Play the current station"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            }
        }
    }
}
struct BrowseStationsView: View {
    let usePicker = true // doesn't look great on Android
    @State var selectedStationMode = BrowseStationMode.countries

    #if os(iOS) || os(Android)
    let pickerPlacement = ToolbarItemPlacement.navigationBarLeading
    #else
    let pickerPlacement = ToolbarItemPlacement.navigation
    #endif

    var body: some View {
        Group {
            if usePicker {
                TabView(selection: $selectedStationMode) {
                    //LanguagesListView()
                    //    .navigationTitle("Languages")
                    //    #if os(iOS) || os(Android)
                    //    .navigationBarTitleDisplayMode(.large)
                    //    #endif
                    //    .tag(BrowseStationMode.languages)
                    CountriesListView()
                        .navigationTitle("Countries")
                        #if os(iOS) || os(Android)
                        .navigationBarTitleDisplayMode(.large)
                        #endif
                        .tag(BrowseStationMode.countries)
                    TagsListView()
                        .navigationTitle("Tags")
                        #if os(iOS) || os(Android)
                        .navigationBarTitleDisplayMode(.large)
                        #endif
                        .tag(BrowseStationMode.tags)
                }
                #if os(iOS) || os(Android)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .toolbar {
                    ToolbarItem(placement: pickerPlacement) {
                        Picker("Selection", selection: $selectedStationMode) {
                            //Text("Languages").tag(BrowseStationMode.languages)
                            Text("Countries").tag(BrowseStationMode.countries)
                            Text("Tags").tag(BrowseStationMode.tags)
                            //Text("Search").tag(BrowseStationMode.tags)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 230)
                    }
                }
            } else {
                List {
                    //NavigationLink("Languages", value: BrowseStationMode.languages)
                    NavigationLink("Countries", value: NavPath.browseStationMode(BrowseStationMode.countries))
                    NavigationLink("Tags", value: NavPath.browseStationMode(BrowseStationMode.tags))
                }
                .navigationTitle(Text("Browse Stations"))
            }
        }
    }
}

struct LanguagesListView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var sortOption: StationGroupSortOption = .name
    @State var languages: [LanguageInfo] = []
    @State var loading = false
    @State var error: Error? = nil

    var currentLanguageCode: String? {
        Locale.current.language.languageCode?.identifier
    }

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
                    ForEach(languages.filter({ $0.name == currentLanguageCode }), id: \.name) { language in
                        languageLink(language)
                    }
                }
                Section {
                    ForEach(languages.filter({ $0.name != currentLanguageCode }), id: \.name) { language in
                        languageLink(language)
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
                        sortLanguages()
                    }
                }
            }
        }
        .task {
            if self.languages.isEmpty {
                await loadLanguages()
            }
        }
        .refreshable {
            await loadLanguages()
        }
    }

    func loadLanguages() async {
        self.loading = true
        self.error = nil
        defer {
            self.loading = false
        }
        do {
            logger.log("loading languages…")
            let languages = try await APIClient.shared.fetchLanguages(params: viewModel.queryParams).filter {
                $0.name == $0.name.uppercased()
            }
            withAnimation {
                self.languages = languages
                sortLanguages()
            }
            logger.log("loaded \(self.languages.count) languages")
        } catch {
            logger.error("error loading languages: \(error)")
            self.error = error
        }
    }

    func languageLink(_ language: LanguageInfo) -> some View {
        NavigationLink(value: NavPath.stationQuery(StationQuery(title: language.localizedName, params: StationQueryParams(language: language.name, languageExact: true)))) {
            Label {
                HStack {
                    Text(language.localizedName)
                    Spacer()
                    //Text("\(country.stationcount, format: .number)") // not supported in Skip
                    //Text(country.stationcount.formatted())
                    Text(NumberFormatter.localizedString(from: language.stationcount as NSNumber, number: .decimal))
                }
            } icon: {
//                Text(emojiFlag(countryCode: country.normalizedCountryCode))
//                    .font(.title)
            }
        }
    }

    func sortLanguages() {
        self.languages = sortOption.sort(languages: self.languages)
    }
}


struct CountriesListView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var sortOption: StationGroupSortOption = .name
    @State var countries: [CountryInfo] = []
    @State var loading = false
    @State var error: Error? = nil

    var currentRegionIdentifier: String? {
        Locale.current.region?.identifier
    }

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
                    ForEach(countries.filter({ $0.name == currentRegionIdentifier }), id: \.name) { country in
                        countryLink(country)
                    }
                }
                Section {
                    ForEach(countries.filter({ $0.name != currentRegionIdentifier }), id: \.name) { country in
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
        NavigationLink(value: NavPath.stationQuery(StationQuery(title: country.localizedName, params: StationQueryParams(countrycode: country.name)))) {
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
        NavigationLink(value: NavPath.stationQuery(StationQuery(title: tag.localizedName, params: StationQueryParams(tag: tag.name)))) {
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
    @State var stations: [APIStationInfo] = []
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
                    .foregroundStyle(.gray)
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

    @MainActor func updateStations(_ stations: [APIStationInfo]) {
        withAnimation {
            self.stations = stations
        }
    }

    func cleanup(_ stations: [APIStationInfo]) -> [APIStationInfo] {
        stations.map {
            var station = $0
            station.name = station.name.trimmingCharacters(in: .whitespacesAndNewlines)
            station.tags = station.tags?.trimmingCharacters(in: .whitespacesAndNewlines)
            return station
        }
    }

    func stationRow(_ station: APIStationInfo) -> some View {
        NavigationLink(value: NavPath.apiStationInfo(station)) {
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
    let station: StationInfo
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var newCollectionName = ""
    @State var addCollectionActive = false // whether we are showing the dialog for adding a new collection
    @FocusState var addCollectionNameFocused: Bool

    var body: some View {
        Form {
            StationInfoFormView(title: LocalizedStringResource("Station Name"), value: station.name)
            StationInfoFormView(title: LocalizedStringResource("Country"), value: station.countrycode)
            //StationInfoFormView(title: LocalizedStringResource("Bit Rate"), value: station.bitrate?.description)
            StationInfoFormView(title: LocalizedStringResource("Tags"), value: station.tags)

            if let homepage = station.homepage, let homepageURL = URL(string: homepage) {
                Link(homepage, destination: homepageURL)
            }

            StationInfoFormView(title: LocalizedStringResource("URL"), value: station.url)

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
        #if os(iOS) || os(Android)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Menu {
                    Text("Add to Collection")
                    Section {
                        addStationButton(to: viewModel.favoritesCollection)
                        ForEach(viewModel.customCollections) { collection in
                            addStationButton(to: collection)
                        }
                    }
                    Divider()
                    Button("New Collection…") {
                        newCollectionName = ""
                        addCollectionActive = true
                        addCollectionNameFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .resizable()
                        .accessibilityLabel(Text("Add to collection"))
                        .font(.title)
                        .frame(width: 25, height: 25)
                }
            }

            ToolbarItem {
                if viewModel.isPlaying(station) {
                    Button {
                        viewModel.pause()
                    } label: {
                        Image("pause_pause_fill1_symbol", bundle: .module, label: Text("Pause"))
                            .resizable()
                            .accessibilityLabel(Text("Pause Station"))
                            .font(.title)
                            .frame(width: 25, height: 25)
                    }
                } else {
                    Button {
                        viewModel.play(station)
                        //self.selectedTab = .nowPlaying // TODO
                    } label: {
                        Image("play_arrow_play_arrow_fill1_symbol", bundle: .module, label: Text("Play"))
                            .resizable()
                            .accessibilityLabel(Text("Play Station"))
                            .frame(width: 25, height: 25)
                    }
                }
            }
        }
        .alert("New Collection", isPresented: $addCollectionActive) {
            TextField("Collection Name", text: $newCollectionName)
                .focused($addCollectionNameFocused)
            Button("Cancel", role: .cancel) {
                addCollectionActive = false
            }
            Button("Create") {
                addCollectionActive = false
                viewModel.withDatabase("create collection") { db in
                    let collection = try db.createCollection(named: newCollectionName)
                    addStation(to: collection)
                }
            }
            .disabled(!viewModel.isValidCollectionName(newCollectionName))
        }
    }

    func addStationButton(to collection: StationCollection) -> some View {
        let present = viewModel.withDatabase("check station in collection", block: { try $0.isStation(station, inCollection: collection )}) == true
        return Button {
            addStation(to: collection)
        } label: {
            Label {
                Text(collection.localizedName)
            } icon: {
                if present {
                    Image("check_small_check_small_symbol", bundle: .module)
                }
            }
        }
    }

    func addStation(to collection: StationCollection) {
        do {
            logger.log("add station to collection: \(collection.localizedName)")
            try viewModel.addStation(station, to: collection)
        } catch {
            logger.error("error saving station to collection: \(error)")
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


extension StationSortOption {
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
        case .name: return (APIStationInfo.CodingKeys.name.rawValue, false)
        case .popularity: return (APIStationInfo.CodingKeys.votes.rawValue, true)
        case .trend: return (APIStationInfo.CodingKeys.clicktrend.rawValue, true)
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

    func sort(languages: [LanguageInfo]) -> [LanguageInfo] {
        languages.sorted {
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

extension LanguageInfo {
    var localizedName: String {
        Locale.current.localizedString(forLanguageCode: self.name) ?? self.name
    }

    var normalizedLanguageCode: String {
        // TODO: fixup invalid names and convert to known language codes
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

struct CollectionsListView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var newCollectionName = ""
    @State var addCollectionActive = false // whether we are showing the dialog for adding a new collection
    @FocusState var addCollectionNameFocused: Bool
    @State var deleteCollections: [StationCollection]? = nil
    @State var deleteCollectionActive = false

    var body: some View {
        let collectionCounts = viewModel.collectionCounts
        let standardCollections = collectionCounts.filter({ $0.0.isStandardCollection })
        let customCollections = collectionCounts.filter({ !$0.0.isStandardCollection })

        List {
            Section {
                ForEach(standardCollections, id: \.0.id) { item in
                    NavigationLink(value: NavPath.stationCollection(item.0)) {
                        HStack {
                            Text(item.0.localizedName)
                            Spacer()
                            // SKIP NOWARN
                            Text(item.1.formatted())
                        }
                    }
                }
            }
            Section {
                ForEach(customCollections, id: \.0.id) { item in
                    NavigationLink(value: NavPath.stationCollection(item.0)) {
                        HStack {
                            Text(item.0.localizedName)
                            Spacer()
                            // SKIP NOWARN
                            Text(item.1.formatted())
                        }
                    }
                }
                .onMove { fromOffsets, toOffset in
                    for var collection in fromOffsets.map({ customCollections[$0].0 }) {
                        viewModel.withDatabase("update station collection order") { db in
                            collection.sortOrder = targetOffset(forDestination: toOffset, in: customCollections.map(\.0.sortOrder), ascending: false)
                            try db.ctx.update(collection)
                        }
                    }
                }
                .onDelete { offsets in
                    self.deleteCollections = offsets.map({ customCollections[$0].0 })
                    self.deleteCollectionActive = true
                }
                .confirmationDialog("Delete Collection", isPresented: $deleteCollectionActive) {
                    Button("Delete Collection", role: .destructive) {
                        for collection in deleteCollections ?? [] {
                            withAnimation {
                                viewModel.withDatabase("delete collection") { db in
                                    try db.removeCollection(collection)
                                }
                            }
                        }
                        self.deleteCollections = nil
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    newCollectionName = ""
                    addCollectionActive = true
                    addCollectionNameFocused = true
                } label: {
                    Label("Add Collection", systemImage: "plus")
                }
            }
        }
        .alert("New Collection", isPresented: $addCollectionActive) {
            TextField("Collection Name", text: $newCollectionName)
                .focused($addCollectionNameFocused)
            Button("Cancel", role: .cancel) {
                addCollectionActive = false
            }
            Button("Create") {
                addCollectionActive = false
                viewModel.withDatabase("create collection") { db in
                    try db.createCollection(named: newCollectionName)
                }
            }
            .disabled(!viewModel.isValidCollectionName(newCollectionName))
        }
    }
}

struct StationCollectionView: View {
    @State var collection: StationCollection

    @State var addCustomStationActive = false
    @State var addCustomStationName = ""
    @State var addCustomStationURL = ""
    @FocusState var addCustomStationNameFocused: Bool

    @State var renameCollectionName = ""
    @State var renameCollectionActive = false // whether we are showing the dialog for adding a new collection
    @FocusState var renameCollectionNameFocused: Bool

    @Environment(ViewModel.self) var viewModel: ViewModel

    var stationsInCollection: [(StoredStationInfo, StationCollectionInfo)] {
        viewModel.withDatabase("stationsInCollection") { db in
            try db.fetchStations(inCollection: collection)
        } ?? []
    }

    var body: some View {
        List {
            let stationCollections = self.stationsInCollection
            let stations = stationCollections.map(\.0)
            let infos = stationCollections.map(\.1)
            ForEach(stations) { station in
                NavigationLink(value: NavPath.storedStationInfo(station)) {
                    Text(station.name)
                }
            }
            .onDelete { offsets in
                for station in offsets.map({ stations[$0] }) {
                    viewModel.withDatabase("delete stations from collection") { db in
                        try db.removeStation(station, fromCollection: self.collection)
                    }
                }
            }
            .onMove { fromOffsets, toOffset in
                for var info in fromOffsets.map({ infos[$0] }) {
                    viewModel.withDatabase("update station collection order") { db in
                        info.sortOrder = targetOffset(forDestination: toOffset, in: infos.map(\.sortOrder), ascending: false)
                        try db.ctx.update(info)
                    }
                }
            }
        }
        .navigationTitle(collection.localizedName)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Add Custom Station") {
                        addCustomStationNameFocused = true
                        addCustomStationActive = true
                    }

                    Button("Rename Collection") {
                        // need to manually disable due to: https://github.com/skiptools/skip-ui/issues/246
                        if collection.isStandardCollection { return }
                        renameCollectionName = collection.name
                        renameCollectionNameFocused = true
                        renameCollectionActive = true
                    }
                    .disabled(collection.isStandardCollection)

                    Button("Shuffle") {
                        withAnimation {
                            viewModel.withDatabase("shuffle collection order") { db in
                                try db.shuffleStations(inCollection: collection)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel(Text("Collection Actions Menu"))
                }
            }
        }
        .alert("Rename Collection", isPresented: $renameCollectionActive) {
            TextField("Collection Name", text: $renameCollectionName)
                .focused($renameCollectionNameFocused)
            Button("Cancel", role: .cancel) {
                renameCollectionActive = false
            }
            Button("Rename") {
                renameCollectionActive = false
                viewModel.withDatabase("rename collection") { db in
                    collection.name = renameCollectionName
                    try db.ctx.update(collection)
                }
            }
            .disabled(!viewModel.isValidCollectionName(renameCollectionName))
        }
        .sheet(isPresented: $addCustomStationActive) {
            Form {
                TextField("Station Name", text: $addCustomStationName)
                    .autocorrectionDisabled()
                    .focused($addCustomStationNameFocused)
                TextField("Station URL", text: $addCustomStationURL)
                    #if os(Android) || os(iOS)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Add Station") {
                    let station = StoredStationInfo(stationuuid: UUID(), name: addCustomStationName, url: addCustomStationURL)
                    let savedStation = viewModel.withDatabase("save custom station") {
                        let savedStation = try $0.saveStation(station)
                        try $0.addStation(savedStation, toCollection: collection)
                        return savedStation
                    }
                    addCustomStationActive = false
                    if let savedStation {
                        // push the saved station onto the nav stack to save it
                        viewModel.collectionsNavigationPath.append(.storedStationInfo(savedStation))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isValidStationName(addCustomStationName) || !viewModel.isValidStationURL(addCustomStationURL))
            }
            .presentationDetents([.medium])
        }
    }
}

extension StationCollection {
    var localizedName: String {
        switch self.name {
        case StationCollection.favoritesCollectionName: return NSLocalizedString("Favorites", comment: "name of standard collection for favorite stations")
        case StationCollection.recentsCollectionName: return NSLocalizedString("Recently Played", comment: "name of standard collection for recently played stations")
        default: return self.name
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
        AppFairSettings {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(buildNumber))")
            }
        }
    }
}

/// Given the destination index against the given array of sort orders, return the
/// value of the sort order that should be applied to the element such that it will appear
/// in between the elements around the destination.
private func targetOffset(forDestination toOffset: Int, in sortOrders: [Double], ascending: Bool) -> Double {
    // TODO: this is ascending=false; handle ascending=true
    return toOffset == 0 ? (sortOrders[0] + 1.0)
        : toOffset == sortOrders.count ? (sortOrders[sortOrders.count - 1] / 2.0)
        : (sortOrders[toOffset - 1] - ((sortOrders[toOffset - 1] - sortOrders[toOffset]) / 2.0))
}
