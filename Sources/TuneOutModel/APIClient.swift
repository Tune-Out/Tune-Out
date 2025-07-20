// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

/// “Please send a descriptive User-Agent in your HTTP requests, which makes it easier for me to get in touch with developers to help with the usage of the API. Something like appname/appversion, for example Cool Radio App/1.2. This also helps me to know which apps are using this service, so I can keep the list of apps up to date and tell people in which ways they can use this service.” — https://docs.radio-browser.info/#using-the-api
let userAgent = "Tune-Out/\(appVersion)"

/// https://docs.radio-browser.info
public struct APIClient {
    nonisolated(unsafe) public static let shared = APIClient()

    public static let hostDefault = "de1.api.radio-browser.info" // or de2.api.radio-browser.info or fi1.api.radio-browser.info or all.api.radio-browser.info
    public static let baseURLDefault: String = "https://\(hostDefault)/json"

    /// The root URL for API requsts, configurable by the user
    public var baseURL: String {
        UserDefaults.standard.string(forKey: "baseURL") ?? APIClient.baseURLDefault
    }

    private init() {
    }

    private func fetchData(endpoint: String, filter: String?, params: [URLQueryItem]?) async throws -> Data {
        guard var components = URLComponents(string: baseURL, encodingInvalidCharacters: true) else {
            throw URLError(.badURL)
        }

        components.path += "/" + endpoint
        if let filter {
            // FIXME: URLComponents on Android encodes space as "+", but API requites "%20"
            components.path += "/" + filter
        }

        if let params {
            components.queryItems = params
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        // FIXME: URLComponents encodes space as "+" instead of "%20" in Kotlin
        let url2 = URL(string: url.absoluteString.replacingOccurrences(of: "+", with: "%20")) ?? url
        logger.trace("fetchData: \(url2.absoluteString)")

        var request = URLRequest(url: url2)
        //request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData // needed for random sort?
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    @inline(__always) private func fetchSingle<T: Decodable>(_ type: T.Type, endpoint: String, filter: String?, params: [URLQueryItem]?) async throws -> T {
        let data = try await fetchData(endpoint: endpoint, filter: filter, params: params)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    @inline(__always) private func fetchArray<T: Decodable>(_ type: T.Type, endpoint: String, filter: String?, params: [URLQueryItem]?) async throws -> [T] {
        let data = try await fetchData(endpoint: endpoint, filter: filter, params: params)
        let decoder = JSONDecoder()
        return try decoder.decode([T].self, from: data)
    }

    /// https://docs.radio-browser.info/#list-of-country-codes
    public func fetchCountries(filter: String? = nil, params: QueryParams? = nil) async throws -> [CountryInfo] {
        try await fetchArray(CountryInfo.self, endpoint: "countrycodes", filter: filter, params: params?.queryItems)
    }

    /// https://docs.radio-browser.info/#list-of-languages
    public func fetchLanguages(filter: String? = nil, params: QueryParams? = nil) async throws -> [LanguageInfo] {
        try await fetchArray(LanguageInfo.self, endpoint: "languages", filter: filter, params: params?.queryItems)
    }

    /// https://docs.radio-browser.info/#list-of-languages
    public func fetchTags(filter: String? = nil, params: QueryParams? = nil) async throws -> [TagInfo] {
        try await fetchArray(TagInfo.self, endpoint: "tags", filter: filter, params: params?.queryItems)
    }

    /// https://docs.radio-browser.info/#list-of-radio-stations
    public func fetchStations(filter: StationFilter? = nil, params: QueryParams? = nil) async throws -> [StationInfo] {
        try await fetchArray(StationInfo.self, endpoint: "stations", filter: filter?.asQuery, params: params?.queryItems)
    }

    /// https://docs.radio-browser.info/#advanced-station-search
    public func searchStations(query: StationQueryParams, params: QueryParams? = nil) async throws -> [StationInfo] {
        try await fetchArray(StationInfo.self, endpoint: "stations/search", filter: nil, params: query.queryItems + (params?.queryItems ?? []))
    }

    public func click(id: UUID) async throws -> ClickResponse {
        try await fetchSingle(ClickResponse.self, endpoint: "url", filter: id.uuidString.lowercased(), params: nil)
    }

    public func upvote(id: UUID) async throws -> UpvoteResponse {
        try await fetchSingle(UpvoteResponse.self, endpoint: "vote", filter: id.uuidString.lowercased(), params: nil)
    }
}


public enum StationFilter {
    case byuuid(searchterm: String)
    case byname(searchterm: String)
    case bynameexact(searchterm: String)
    case bycodec(searchterm: String)
    case bycodecexact(searchterm: String)
    case bycountry(searchterm: String)
    case bycountryexact(searchterm: String)
    case bycountrycodeexact(searchterm: String)
    case bystate(searchterm: String)
    case bystateexact(searchterm: String)
    case bylanguage(searchterm: String)
    case bylanguageexact(searchterm: String)
    case bytag(searchterm: String)
    case bytagexact(searchterm: String)

    var asQuery: String {
        switch self {
        case .byuuid(let searchterm): return "byuuid/" + searchterm
        case .byname(let searchterm): return "byname/" + searchterm
        case .bynameexact(let searchterm): return "bynameexact/" + searchterm
        case .bycodec(let searchterm): return "bycodec/" + searchterm
        case .bycodecexact(let searchterm): return "bycodecexact/" + searchterm
        case .bycountry(let searchterm): return "bycountry/" + searchterm
        case .bycountryexact(let searchterm): return "bycountryexact/" + searchterm
        case .bycountrycodeexact(let searchterm): return "bycountrycodeexact/" + searchterm
        case .bystate(let searchterm): return "bystate/" + searchterm
        case .bystateexact(let searchterm): return "bystateexact/" + searchterm
        case .bylanguage(let searchterm): return "bylanguage/" + searchterm
        case .bylanguageexact(let searchterm): return "bylanguageexact/" + searchterm
        case .bytag(let searchterm): return "bytag/" + searchterm
        case .bytagexact(let searchterm): return "bytagexact/" + searchterm
        }
    }
}

public struct StationInfo: Hashable, Sendable, Codable {
    // changeuuid: 01234567-89ab-cdef-0123-456789abcdef
    public var changeuuid: UUID?
    // stationuuid: 01234567-89ab-cdef-0123-456789abcdef
    public var stationuuid: UUID
    // serveruuid: 01234567-89ab-cdef-0123-456789abcdef
    public var serveruuid: UUID?
    // name: Best Radio
    public var name: String
    // url: http://www.example.com/test.pls
    public var url: String
    // url_resolved: http://stream.example.com/mp3_128
    public var url_resolved: String?
    // homepage: https://www.example.com
    public var homepage: String?
    // favicon: https://www.example.com/icon.png
    public var favicon: String?
    // tags: jazz,pop,rock,indie
    public var tags: String?
    // country: Switzerland
    public var country: String?
    // countrycode: US
    public var countrycode: String?
    // iso_3166_2: US-NY
    public var iso_3166_2: String?
    // state:
    public var state: String?
    // language: german,english
    public var language: String?
    // languagecodes: ger,eng
    public var languagecodes: String?
    // votes: 0,
    public var votes: Int?
    // lastchangetime: 2019-12-12 18:37:02
    public var lastchangetime: String?
    // lastchangetime_iso8601: 2019-12-12T18:37:02Z
    public var lastchangetime_iso8601: String?
    // codec: MP3
    public var codec: String?
    // bitrate:  128
    public var bitrate: Int?
    // hls:  0
    public var hls: Int?
    // lastcheckok: 1
    public var lastcheckok: Int?
    // lastchecktime: 2020-01-09 18:16:35
    public var lastchecktime: String?
    // lastchecktime_iso8601: 2020-01-09T18:16:35Z
    public var lastchecktime_iso8601: String?
    // lastcheckoktime: 2020-01-09 18:16:35
    public var lastcheckoktime: String?
    // lastcheckoktime_iso8601: 2020-01-09T18:16:35Z
    public var lastcheckoktime_iso8601: String?
    // lastlocalchecktime: 2020-01-08 23:18:38
    public var lastlocalchecktime: String?
    // lastlocalchecktime_iso8601: 2020-01-08T23:18:38Z
    public var lastlocalchecktime_iso8601: String?
    // clicktimestamp:
    public var clicktimestamp: String?
    // clicktimestamp_iso8601: null
    public var clicktimestamp_iso8601: String?
    // clickcount: 0
    public var clickcount: Int?
    // clicktrend: 0
    public var clicktrend: Int?
    // ssl_error: 0
    public var ssl_error: Int?
    // geo_lat: 1.1
    public var geo_lat: Double?
    // geo_long: -2.2
    public var geo_long: Double?
    // has_extended_info: false
    public var has_extended_info: Bool?

    public enum CodingKeys : String, CodingKey {
        case changeuuid = "changeuuid"
        case stationuuid = "stationuuid"
        case serveruuid = "serveruuid"
        case name = "name"
        case url = "url"
        case url_resolved = "url_resolved"
        case homepage = "homepage"
        case favicon = "favicon"
        case tags = "tags"
        case country = "country"
        case countrycode = "countrycode"
        case iso_3166_2 = "iso_3166_2"
        case state = "state"
        case language = "language"
        case languagecodes = "languagecodes"
        case votes = "votes"
        case lastchangetime = "lastchangetime"
        case lastchangetime_iso8601 = "lastchangetime_iso8601"
        case codec = "codec"
        case bitrate = "bitrate"
        case hls = "hls"
        case lastcheckok = "lastcheckok"
        case lastchecktime = "lastchecktime"
        case lastchecktime_iso8601 = "lastchecktime_iso8601"
        case lastcheckoktime = "lastcheckoktime"
        case lastcheckoktime_iso8601 = "lastcheckoktime_iso8601"
        case lastlocalchecktime = "lastlocalchecktime"
        case lastlocalchecktime_iso8601 = "lastlocalchecktime_iso8601"
        case clicktimestamp = "clicktimestamp"
        case clicktimestamp_iso8601 = "clicktimestamp_iso8601"
        case clickcount = "clickcount"
        case clicktrend = "clicktrend"
        case ssl_error = "ssl_error"
        case geo_lat = "geo_lat"
        case geo_long = "geo_long"
        case has_extended_info = "has_extended_info"
    }
}

extension StationInfo: Identifiable {
    public typealias ID = UUID
    public var id: ID { stationuuid }
}

public struct QueryParams: Sendable {
    // name of the attribute the result list will be sorted by
    public var order: String?
    // reverse the result list if set to true
    public var reverse: Bool?
    // do not count broken stations
    public var hidebroken: Bool?
    // starting value of the result list from the database. For example, if you want to do paging on the server side.
    public var offset: Int?
    // number of returned data rows (stations) starting with offset
    public var limit: Int?

    public init(order: String? = nil, reverse: Bool? = nil, hidebroken: Bool? = nil, offset: Int? = nil, limit: Int? = nil) {
        self.order = order
        self.reverse = reverse
        self.hidebroken = hidebroken
        self.offset = offset
        self.limit = limit
    }

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let order = order {
            items.append(URLQueryItem(name: "order", value: order))
        }
        if let reverse = reverse {
            items.append(URLQueryItem(name: "reverse", value: "\(reverse)"))
        }
        if let hidebroken = hidebroken {
            items.append(URLQueryItem(name: "hidebroken", value: "\(hidebroken)"))
        }
        if let offset = offset {
            items.append(URLQueryItem(name: "offset", value: "\(offset)"))
        }
        if let limit = limit {
            items.append(URLQueryItem(name: "limit", value: "\(limit)"))
        }
        return items
    }
}

public struct StationQueryParams: Hashable, Sendable {
    // name        string    OPTIONAL, name of the station
    public var name: String?
    // nameExact    false    true, false    OPTIONAL. True: only exact matches, otherwise all matches.
    public var nameExact: Bool?
    // country        string    OPTIONAL, country of the station
    public var country: String?
    // countryExact    false    true, false    OPTIONAL. True: only exact matches, otherwise all matches.
    public var countryExact: Bool?
    // countrycode        string    OPTIONAL, 2-digit countrycode of the station (see ISO 3166-1 alpha-2).
    public var countrycode: String?
    // state        string    OPTIONAL, state of the station
    public var state: String?
    // stateExact    false    true, false    OPTIONAL. True: only exact matches, otherwise all matches.
    public var stateExact: Bool?
    // language        string    OPTIONAL, language of the station
    public var language: String?
    // languageExact    false    true, false    OPTIONAL. True: only exact matches, otherwise all matches.
    public var languageExact: Bool?
    // tag        string    OPTIONAL, a tag of the station
    public var tag: String?
    // tagExact    false    true, false    OPTIONAL. True: only exact matches, otherwise all matches.
    public var tagExact: Bool?
    // tagList        string, string, ...    OPTIONAL. , a comma-separated list of tag. It can also be an array of string in JSON HTTP POST parameters. All tags in list have to match.
    public var tagList: String?
    // codec        string    OPTIONAL, codec of the station
    public var codec: String?
    // bitrateMin    0    POSITIVE INTEGER    OPTIONAL, minimum of kbps for bitrate field of stations in result
    public var bitrateMin: Int?
    // bitrateMax    1000000    POSITIVE INTEGER    OPTIONAL, maximum of kbps for bitrate field of stations in result
    public var bitrateMax: Int?
    // has_geo_info    both    not set, true, false    OPTIONAL, not set=display all, true=show only stations with geo_info, false=show only stations without geo_info
    public var has_geo_info: Bool?
    // has_extended_info    both    not set, true, false    OPTIONAL, not set=display all, true=show only stations which do provide extended information, false=show only stations without extended information
    public var has_extended_info: Bool?
    // is_https    both    not set, true, false    OPTIONAL, not set=display all, true=show only stations which have https url, false=show only stations that do stream unencrypted with http
    public var is_https: Bool?

    public init(name: String? = nil, nameExact: Bool? = nil, country: String? = nil, countryExact: Bool? = nil, countrycode: String? = nil, state: String? = nil, stateExact: Bool? = nil, language: String? = nil, languageExact: Bool? = nil, tag: String? = nil, tagExact: Bool? = nil, tagList: String? = nil, codec: String? = nil, bitrateMin: Int? = nil, bitrateMax: Int? = nil, has_geo_info: Bool? = nil, has_extended_info: Bool? = nil, is_https: Bool? = nil) {
        self.name = name
        self.nameExact = nameExact
        self.country = country
        self.countryExact = countryExact
        self.countrycode = countrycode
        self.state = state
        self.stateExact = stateExact
        self.language = language
        self.languageExact = languageExact
        self.tag = tag
        self.tagExact = tagExact
        self.tagList = tagList
        self.codec = codec
        self.bitrateMin = bitrateMin
        self.bitrateMax = bitrateMax
        self.has_geo_info = has_geo_info
        self.has_extended_info = has_extended_info
        self.is_https = is_https
    }

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let name = name {
            items.append(URLQueryItem(name: "name", value: name))
        }
        if let nameExact = nameExact {
            items.append(URLQueryItem(name: "nameExact", value: nameExact ? "true" : "false"))
        }
        if let country = country {
            items.append(URLQueryItem(name: "country", value: country))
        }
        if let countryExact = countryExact {
            items.append(URLQueryItem(name: "countryExact", value: countryExact ? "true" : "false"))
        }
        if let countrycode = countrycode {
            items.append(URLQueryItem(name: "countrycode", value: countrycode))
        }
        if let state = state {
            items.append(URLQueryItem(name: "state", value: state))
        }
        if let stateExact = stateExact {
            items.append(URLQueryItem(name: "stateExact", value: stateExact ? "true" : "false"))
        }
        if let language = language {
            items.append(URLQueryItem(name: "language", value: language))
        }
        if let languageExact = languageExact {
            items.append(URLQueryItem(name: "languageExact", value: languageExact ? "true" : "false"))
        }
        if let tag = tag {
            items.append(URLQueryItem(name: "tag", value: tag))
        }
        if let tagExact = tagExact {
            items.append(URLQueryItem(name: "tagExact", value: tagExact ? "true" : "false"))
        }
        if let tagList = tagList {
            items.append(URLQueryItem(name: "tagList", value: tagList))
        }
        if let codec = codec {
            items.append(URLQueryItem(name: "codec", value: codec))
        }
        if let bitrateMin = bitrateMin {
            items.append(URLQueryItem(name: "bitrateMin", value: bitrateMin.description))
        }
        if let bitrateMax = bitrateMax {
            items.append(URLQueryItem(name: "bitrateMax", value: bitrateMax.description))
        }
        if let has_geo_info = has_geo_info {
            items.append(URLQueryItem(name: "has_geo_info", value: has_geo_info ? "true" : "false"))
        }
        if let has_extended_info = has_extended_info {
            items.append(URLQueryItem(name: "has_extended_info", value: has_extended_info ? "true" : "false"))
        }
        if let is_https = is_https {
            items.append(URLQueryItem(name: "is_https", value: is_https ? "true" : "false"))
        }

        return items
    }
}

public struct CountryInfo: Hashable, Sendable, Decodable {
    /// https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
    public var name: String
    public var stationcount: Int

    public init(name: String, stationcount: Int) {
        self.name = name
        self.stationcount = stationcount
    }
}

public struct LanguageInfo: Hashable, Sendable, Decodable {
    public var name: String
    public var iso_639: String?
    public var stationcount: Int

    public init(name: String, iso_639: String? = nil, stationcount: Int) {
        self.name = name
        self.iso_639 = iso_639
        self.stationcount = stationcount
    }
}

public struct TagInfo: Hashable, Sendable, Decodable {
    public var name: String
    public var stationcount: Int

    public init(name: String, stationcount: Int) {
        self.name = name
        self.stationcount = stationcount
    }
}

public struct ClickResponse: Hashable, Sendable, Decodable {
    // ok: true
    public var ok: Bool
    // message: retrieved station url
    public var message: String?
    // stationuuid: 9617a958-0601-11e8-ae97-52543be04c81
    public var stationuuid: UUID
    // name: Station name
    public var name: String?
    // url: http://this.is.an.url
    public var url: String?
}

public struct UpvoteResponse: Hashable, Sendable, Decodable {
    // ok: true
    public var ok: Bool
    // message: retrieved station url
    public var message: String?
}
