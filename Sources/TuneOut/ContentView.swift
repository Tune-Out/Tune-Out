// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import SkipAV
import TuneOutModel

enum ContentTab: String, Hashable {
    case music, browse, settings
}

struct ContentView: View {
    @AppStorage("tab") var tab = ContentTab.music
    @AppStorage("name") var welcomeName = "Skipper"
    @AppStorage("appearance") var appearance = ""
    @State var viewModel = ViewModel()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                WelcomeView(welcomeName: $welcomeName)
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
                SettingsView(appearance: $appearance, welcomeName: $welcomeName)
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(ContentTab.settings)
        }
        .environment(viewModel)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}

struct WelcomeView: View {
    @State var heartBeating = false
    @Binding var welcomeName: String

    var body: some View {
        VStack(spacing: 0) {
            Text("Hello [\(welcomeName)](https://skip.tools)!")
                .padding()
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .scaleEffect(heartBeating ? 1.5 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(), value: heartBeating)
                .task { heartBeating = true }
        }
        .font(.largeTitle)
    }
}

struct BrowseStationsView: View {
    enum BrowseStatonMode: Hashable {
        case countries
        case tags
    }

    let usePicker = false // doesn't look great on Android
    @State var selectedStationMode = BrowseStatonMode.countries

    var body: some View {
        NavigationStack {
            Group {
                if usePicker {
                    modeView(for: selectedStationMode)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Picker("", selection: $selectedStationMode) {
                                    Text("Countries").tag(BrowseStatonMode.countries)
                                    Text("Tags").tag(BrowseStatonMode.tags)
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
            ToolbarItem(placement: .topBarTrailing) {
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
            ToolbarItem(placement: .topBarTrailing) {
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

struct StationListView: View {
    let query: StationQuery
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State var sortOption: StationSortOption = .popularity
    @State var stations: [StationInfo] = []
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
                ForEach(stations, id: \.stationuuid) { station in
                    stationRow(station)
                }
            }
        }
        .navigationTitle(query.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker(selection: $sortOption) {
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
                .onChange(of: sortOption) {
                    withAnimation {
                        sortStations()
                    }
                }
            }
        }
        .task {
            if self.stations.isEmpty {
                await loadStations()
            }
        }
        .refreshable {
            await loadStations()
        }
    }

    func loadStations() async {
        self.loading = true
        defer {
            self.loading = false
        }
        do {
            logger.log("loading stations for \(query.params.queryItems)…")
            let stations = try await APIClient.shared.searchStations(query: query.params)
            withAnimation {
                self.stations = cleanup(stations)
                sortStations()
            }
            logger.log("loaded \(self.stations.count) stations")
        } catch {
            logger.error("error loading stations: \(error)")
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

    func sortStations() {
        self.stations = sortOption.sort(self.stations)
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
        VideoPlayer(player: AVPlayer(url: URL(string: station.url_resolved ?? station.url)!))
            .navigationTitle(station.name)
    }
}


extension View {
    /// Converts a country code like "US" into the Emoji symbol for the country's flag
    func emojiFlag(countryCode: String) -> String {
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
    let title: String
    let params: StationQueryParams
}

enum StationSortOption: Identifiable, Hashable, CaseIterable {
    case name
    case popularity
    case trend

    var id: StationSortOption {
        self
    }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .name: return LocalizedStringResource("Name")
        case .popularity: return LocalizedStringResource("Popularity")
        case .trend: return LocalizedStringResource("Trend")
        }
    }

    func sort(_ stations: [StationInfo]) -> [StationInfo] {
        stations.sorted {
            switch self {
            case .name:
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            case .popularity:
                return ($0.votes ?? 0) > ($1.votes ?? 0)
            case .trend:
                return ($0.clicktrend ?? 0) > ($1.clicktrend ?? 0)
            }
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
        case "jazz": return NSLocalizedString("Jazz", bundle: .module, comment: "station tag name")
        case "rock": return NSLocalizedString("Rock", bundle: .module, comment: "station tag name")
        case "country": return NSLocalizedString("Country", bundle: .module, comment: "station tag name")
        case "pop": return NSLocalizedString("Pop", bundle: .module, comment: "station tag name")
        case "music": return NSLocalizedString("Music", bundle: .module, comment: "station tag name")
        case "classical": return NSLocalizedString("Classical", bundle: .module, comment: "station tag name")
        case "talk": return NSLocalizedString("Talk", bundle: .module, comment: "station tag name")
        case "hits": return NSLocalizedString("Hits", bundle: .module, comment: "station tag name")
        case "dance": return NSLocalizedString("Dance", bundle: .module, comment: "station tag name")
        case "oldies": return NSLocalizedString("Oldies", bundle: .module, comment: "station tag name")
        case "electronic": return NSLocalizedString("Electronic", bundle: .module, comment: "station tag name")
        case "40s": return NSLocalizedString("40s", bundle: .module, comment: "station tag name")
        case "50s": return NSLocalizedString("50s", bundle: .module, comment: "station tag name")
        case "60s": return NSLocalizedString("60s", bundle: .module, comment: "station tag name")
        case "70s": return NSLocalizedString("70s", bundle: .module, comment: "station tag name")
        case "80s": return NSLocalizedString("80s", bundle: .module, comment: "station tag name")
        case "90s": return NSLocalizedString("90s", bundle: .module, comment: "station tag name")
        case "house": return NSLocalizedString("House", bundle: .module, comment: "station tag name")
        case "folk": return NSLocalizedString("Folk", bundle: .module, comment: "station tag name")
        case "metal": return NSLocalizedString("Metal", bundle: .module, comment: "station tag name")
        case "soul": return NSLocalizedString("Soul", bundle: .module, comment: "station tag name")
        case "indie": return NSLocalizedString("Indie", bundle: .module, comment: "station tag name")
        case "techno": return NSLocalizedString("Techno", bundle: .module, comment: "station tag name")
        case "sports": return NSLocalizedString("Sports", bundle: .module, comment: "station tag name")
        case "top 40": return NSLocalizedString("Top 40", bundle: .module, comment: "station tag name")
        case "alternative": return NSLocalizedString("News", bundle: .module, comment: "station tag name")
        case "public radio": return NSLocalizedString("Public Radio", bundle: .module, comment: "station tag name")
        case "adult contemporary": return NSLocalizedString("Adult Contemporary", bundle: .module, comment: "station tag name")
        case "classic rock": return NSLocalizedString("Classic Rock", bundle: .module, comment: "station tag name")
        case "news": return NSLocalizedString("News", bundle: .module, comment: "station tag name")
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
                        Text(item.itemTitle)
                    } icon: {
                        if item.favorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
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
                .navigationTitle(item.itemTitle)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    withAnimation {
                        viewModel.items.insert(Item(), at: 0)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }
}

struct ItemView: View {
    @State var item: Item
    @Environment(ViewModel.self) var viewModel: ViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            TextField("Title", text: $item.title)
                .textFieldStyle(.roundedBorder)
            Toggle("Favorite", isOn: $item.favorite)
            DatePicker("Date", selection: $item.date)
            Text("Notes").font(.title3)
            TextEditor(text: $item.notes)
                .border(Color.secondary, width: 1.0)
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
    @Binding var welcomeName: String

    var body: some View {
        Form {
            TextField("Name", text: $welcomeName)
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
