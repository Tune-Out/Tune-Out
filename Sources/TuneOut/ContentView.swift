// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import SkipAV
import TuneOutModel

enum ContentTab: String, Hashable {
    case music, browse, settings
}

struct ContentView: View {
    @AppStorage("tab") var tab = ContentTab.music
    @AppStorage("appearance") var appearance = ""
    @State var viewModel = ViewModel()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                ItemListView()
                    .navigationTitle(Text("\(viewModel.items.count) Favorites"))
            }
            .tabItem {
                Label {
                    Text("Music")
                } icon: {
                    Image("MusicCast", bundle: .module)
                }
            }
            .tag(ContentTab.music)

            BrowseStationsView()
                .tabItem { Label("Browse", systemImage: "list.bullet") }
                .tag(ContentTab.browse)

            NavigationStack {
                SettingsView(appearance: $appearance)
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(ContentTab.settings)
        }
        .environment(viewModel)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}

struct BrowseStationsView: View {
    enum BrowseStatonMode: Hashable {
        case countries
        case tags
        case search
    }

    let usePicker = false // doesn't look great on Android
    @State var selectedStationMode = BrowseStatonMode.countries

    var body: some View {
        NavigationStack {
            Group {
                if usePicker {
                    modeView(for: selectedStationMode)
                        #if os(iOS) || os(Android)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Picker("", selection: $selectedStationMode) {
                                    Text("Countries").tag(BrowseStatonMode.countries)
                                    Text("Tags").tag(BrowseStatonMode.tags)
                                    Text("Search").tag(BrowseStatonMode.tags)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 230)
                            }
                        }
                        #endif
                } else {
                    List {
                        NavigationLink("Countries", value: BrowseStatonMode.countries)
                        NavigationLink("Tags", value: BrowseStatonMode.tags)
                        NavigationLink("Search", value: BrowseStatonMode.search)
                    }
                    .navigationTitle(Text("Browse Stations"))
                    .navigationDestination(for: BrowseStatonMode.self) { mode in
                        modeView(for: mode)
                    }
                }
            }
            .navigationDestination(for: StationQuery.self) {
                StationListView(query: $0)
            }
            .navigationDestination(for: StationInfo.self) {
                StationInfoView(station: $0)
            }
        }
    }

    func modeView(for mode: BrowseStatonMode) -> some View {
        Group {
            switch mode {
            case .countries: CountriesListView().navigationTitle("Countries")
            case .tags: TagsListView().navigationTitle("Tags")
            case .search: StationListView(query: StationQuery(title: "Search")).navigationTitle("Search")
            }
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
                    Button("More…") {
                        withAnimation {
                            showAdditionalTags = !showAdditionalTags
                        }
                    }
                    if showAdditionalTags {
                        // we still filter on stationcount > 10 because many stations create nonsense tags
                        ForEach(tags.filter({ $0.localizedTitle == nil && $0.stationcount > 10 }), id: \.name) { tag in
                            tagLink(tag)
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
                            logger.log("loading from \(stations.count)")
                            await loadStations()
                        }
                    }
                }
            }
            if stations.isEmpty && complete && !loading {
                if self.query.params.queryItems.isEmpty {
                    Text("Search Stations")
                        .font(.title)
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
            let params = QueryParams(order: sortAttr, reverse: reverse, hidebroken: true, offset: self.stations.count, limit: 100)
            logger.log("loading stations for \(query.params.queryItems)…")
            var stations = try await APIClient.shared.searchStations(query: query.params, params: params)
            if stations.isEmpty {
                complete = true
            } else {
                complete = false
                stations = cleanup(stations)
                self.updateStations(unique(self.stations + stations))
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

    /// Ensure that no duplicate IDs exist in the list of stations, which will crash on Android with:
    /// `07-11 17:48:47.636 11894 11894 E AndroidRuntime: java.lang.IllegalArgumentException: Key "9617A958-0601-11E8-AE97-52543BE04C81" was already used. If you are using LazyColumn/Row please make sure you provide a unique key for each item.`
    func unique(_ stations: [StationInfo]) -> [StationInfo] {
        var uniqueStations: [StationInfo] = []
        #if !SKIP
        uniqueStations.reserveCapacity(stations.count)
        #endif
        var ids = Set<StationInfo.ID>()
        for station in stations {
            if ids.insert(station.id).inserted {
                uniqueStations.append(station)
            }
        }
        return uniqueStations
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
            Label {
                HStack {
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
}

struct StationInfoView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    let station: StationInfo

    var body: some View {
        //VideoPlayer(player: AVPlayer(url: URL(string: station.url_resolved ?? station.url)!))

        Form {
            #if !SKIP
            LabeledContent("Name", value: station.name)
            LabeledContent("ID", value: station.stationuuid.uuidString)
            Text("Bit Rate").badge(station.bitrate ?? 0)
            #endif
            //LabeledContent("Bit Rate", value: station.bitrate)

            Button("Play") {
                viewModel.play(station)
            }
            Button("Pause") {
                viewModel.pause(station)
            }
            Button("Favorite") {
                viewModel.favorite(station)
            }
        }
            .navigationTitle(station.name)

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

struct ItemListView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel

    var body: some View {
        List {
            ForEach(viewModel.items) { item in
                NavigationLink(value: item) {
                    Label {
                        Text(item.name)
                    } icon: {
//                        if item.favorite {
//                            Image(systemName: "star.fill")
//                                .foregroundStyle(.yellow)
//                        }
                    }
                }
            }
            .onDelete { offsets in
                viewModel.items.remove(atOffsets: offsets)
            }
            .onMove { fromOffsets, toOffset in
                viewModel.items.move(fromOffsets: fromOffsets, toOffset: toOffset)
            }
        }
        .navigationDestination(for: Item.self) { item in
            ItemView(item: item)
                .navigationTitle(item.name)
        }
        .toolbar {
//            ToolbarItemGroup {
//                Button {
//                    withAnimation {
//                        viewModel.items.insert(Item(), at: 0)
//                    }
//                } label: {
//                    Label("Add", systemImage: "plus")
//                }
//            }
        }
    }
}

struct ItemView: View {
    @State var item: Item
    @Environment(ViewModel.self) var viewModel: ViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            TextField("Title", text: $item.name)
                .textFieldStyle(.roundedBorder)
//            Toggle("Favorite", isOn: $item.favorite)
//            DatePicker("Date", selection: $item.date)
//            Text("Notes").font(.title3)
//            TextEditor(text: $item.notes)
//                .border(Color.secondary, width: 1.0)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save(item: item)
                    dismiss()
                }
                .disabled(!viewModel.isUpdated(item))
            }
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
