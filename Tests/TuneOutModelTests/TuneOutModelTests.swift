// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
import OSLog
import Foundation
@testable import TuneOutModel

let logger: Logger = Logger(subsystem: "TuneOutModel", category: "Tests")

@available(macOS 13, *)
final class TuneOutModelTests: XCTestCase {
    func testCountryList() async throws {
        let countries = try await APIClient.shared.fetchCountries()
        XCTAssertTrue(countries.map(\.name).contains("US"))

        let countriesFilter = try await APIClient.shared.fetchCountries(filter: "FR")
        XCTAssertGreaterThanOrEqual(countriesFilter.count, 1)
    }

    func testLanguageList() async throws {
        let languages = try await APIClient.shared.fetchLanguages()
        XCTAssertTrue(languages.compactMap(\.iso_639).contains("en"))

        let languagesFilter = try await APIClient.shared.fetchLanguages(filter: "fr")
        XCTAssertGreaterThanOrEqual(languagesFilter.count, 1)
    }

    func testTagsList() async throws {
        let tags = try await APIClient.shared.fetchTags()
        XCTAssertTrue(tags.map(\.name).contains("jazz"))

        let tagsFilter = try await APIClient.shared.fetchTags(filter: "jazz")
        XCTAssertGreaterThanOrEqual(tagsFilter.count, 1)
    }

    func testStationQuery() async throws {
        let stations = try await APIClient.shared.fetchStations(filter: .bynameexact(searchterm: "Radio Paradise"))
        logger.debug("stations: \(stations.map(\.name))")
        XCTAssertEqual(1, stations.count)
        let station = try XCTUnwrap(stations.first)
        XCTAssertEqual("39B56BEF-5BFA-11EA-BE63-52543BE04C81", station.stationuuid.uuidString)
        XCTAssertEqual("https://www.radioparadise.com/", station.homepage)
        XCTAssertEqual("en", station.languagecodes)
    }

    func testStationSearch() async throws {
        do {
            // unknown codec
            let stations = try await APIClient.shared.searchStations(query: StationQueryParams(tag: "rock", codec: "XXX"), params: QueryParams(order: "country", reverse: true, hidebroken: true, offset: 10, limit: 10))
            XCTAssertEqual(0, stations.count)
        }

        do {
            let stations = try await APIClient.shared.searchStations(query: StationQueryParams(tag: "rock", codec: "mp3"), params: QueryParams(order: "country", reverse: true, hidebroken: true, offset: 10, limit: 100))
            logger.debug("stations: \(stations.map(\.name))")
            XCTAssertEqual(100, stations.count)
        }

        do {
            let stations = try await APIClient.shared.searchStations(query: StationQueryParams(name: nil, nameExact: false, country: nil, countryExact: false, countrycode: nil, state: nil, stateExact: false, language: nil, languageExact: false, tag: nil, tagExact: false, tagList: "jazz,rock", codec: nil, bitrateMin: 0, bitrateMax: 100000, has_geo_info: false, has_extended_info: false, is_https: true), params: QueryParams(order: "country", reverse: true, hidebroken: true, offset: 10, limit: 10))
            logger.debug("stations: \(stations.map(\.name))")
            XCTAssertEqual(10, stations.count)
        }
    }

    func testStationUpvote() async throws {
        do {
            let uuid = try XCTUnwrap(UUID(uuidString: "99999999-9999-9999-9999-999999999999"))
            let response = try await APIClient.shared.upvote(id: uuid)
            XCTAssertEqual(false, response.ok)
            XCTAssertEqual("VoteError 'could not find station with matching id'", response.message)
        }

        do {
            let uuid = try XCTUnwrap(UUID(uuidString: "39B56BEF-5BFA-11EA-BE63-52543BE04C81"))
            let response = try await APIClient.shared.upvote(id: uuid)
            if response.ok {
                XCTAssertEqual(true, response.ok)
                XCTAssertEqual("voted for station successfully", response.message)
            } else {
                XCTAssertEqual(false, response.ok)
                XCTAssertEqual("VoteError 'you are voting for the same station too often'", response.message)
            }
        }
    }

    func testStationClick() async throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "39B56BEF-5BFA-11EA-BE63-52543BE04C81"))
        let response = try await APIClient.shared.click(id: uuid)
        XCTAssertEqual(true, response.ok)
        XCTAssertEqual(uuid, response.stationuuid)
        XCTAssertEqual("retrieved station url", response.message)
    }
}
