// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
import OSLog
import Foundation
import SkipSQL
@testable import TuneOutModel

let logger: Logger = Logger(subsystem: "TuneOutModel", category: "Tests")

@available(macOS 13, *)
final class TuneOutModelTests: XCTestCase {
    @MainActor func testCollections() throws {
        let station1 = APIStationInfo(stationuuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Station 1", url: "https://radio-browser.info")
        let station2 = APIStationInfo(stationuuid: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Station 1", url: "https://radio-browser.info")
        let station3 = APIStationInfo(stationuuid: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Station 1", url: "https://radio-browser.info")
        let station4 = APIStationInfo(stationuuid: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Station 1", url: "https://radio-browser.info")
        let station5 = APIStationInfo(stationuuid: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Station 1", url: "https://radio-browser.info")

        let db = try DatabaseManager(url: nil)
        try db.initializeSchema()

        XCTAssertEqual(try db.fetchCollections(standard: true).map(\.name), [StationCollection.favoritesCollectionName, StationCollection.recentsCollectionName])

        let collection1 = try db.ctx.insert(StationCollection(name: "Collection 1", sortOrder: 1.0))
        XCTAssertEqual(3, collection1.id) // starts at 3 because the first 2 are auto-initialized

        let collection2 = try db.ctx.insert(StationCollection(name: "Collection 2", sortOrder: 2.0))
        XCTAssertEqual(4, collection2.id)

        let stored1 = try db.ctx.insert(StoredStationInfo(info: station1))
        let stored2 = try db.ctx.insert(StoredStationInfo(info: station2))
        let stored3 = try db.ctx.insert(StoredStationInfo(info: station3))
        let stored4 = try db.ctx.insert(StoredStationInfo(info: station4))
        let stored5 = try db.ctx.insert(StoredStationInfo(info: station5))

        try db.addStation(stored1, toCollection: collection1)
        try db.addStation(stored2, toCollection: collection1)
        try db.addStation(stored3, toCollection: collection1)
        try db.addStation(stored4, toCollection: collection1)
        try db.addStation(stored5, toCollection: collection1)
        try db.addStation(stored2, toCollection: collection1) // should move stored2 to top of queue

        try db.addStation(stored4, toCollection: collection2)
        try db.addStation(stored3, toCollection: collection2)

        let stationCollections1 = try db.fetchStations(inCollection: collection1)
        XCTAssertEqual(stationCollections1.map({ $0.0.id }), [stored2.id, stored5.id, stored4.id, stored3.id, /*stored2.id,*/ stored1.id])

        let stationCollections2 = try db.fetchStations(inCollection: collection2)
        XCTAssertEqual(stationCollections2.map({ $0.0.id }), [stored3.id, stored4.id])

        let stored3Collections = try db.fetchStations(inCollection: collection2)
        XCTAssertEqual(stored3Collections.map({ $0.0.id }), [stored3.id, stored4.id])

        // check collection counts
        let collectionCounts = try db.fetchCollectionCounts().filter {
            !$0.0.isStandardCollection
        }
        XCTAssertEqual(collection2, collectionCounts.first?.0)
        XCTAssertEqual(2, collectionCounts.first?.1)
        XCTAssertEqual(collection1, collectionCounts.last?.0)
        XCTAssertEqual(5, collectionCounts.last?.1)

        try db.ctx.delete(instances: [stored1, stored2, stored3, stored4, stored5])
        XCTAssertEqual(5, db.ctx.changes)

        //try db.ctx.delete(instances: [storedCollection1, storedCollection2, storedCollection3, storedCollection4, storedCollection5])
        XCTAssertEqual(0, try db.ctx.count(StationCollectionInfo.self), "relation rows should have been cascade deleted")
    }

    // MARK: API tests (disabled from macOS runs for performance)

    #if os(iOS)
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
        XCTAssertEqual("39B56BEF-5BFA-11EA-BE63-52543BE04C81", station.stationuuid?.uuidString)
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
    #endif
}
