// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import SkipSQL

/// Provides serialized, strongly-typed access to data items.
public final class DatabaseManager {
    public let ctx: SQLContext
    private var schemaInitializationResult: Result<Void, Error>?

    public init(url: URL?) throws {
        ctx = try SQLContext(path: url?.path ?? ":memory:", flags: [.readWrite, .create])
        ctx.trace { sql in
            logger.info("SQL: \(sql)")
        }
        ctx.foreignKeysEnabled = true
        try initializeSchema()
        try initializeCollections()
    }

    func initializeSchema() throws {
        var version = try currentSchemaVersion()

        version = try migrateSchema(v: 1, current: version, ddl: StoredStationInfo.table.createTableSQL(withIndexes: true, columns: [StoredStationInfo.id, StoredStationInfo.stationuuid, StoredStationInfo.name, StoredStationInfo.url, StoredStationInfo.favicon, StoredStationInfo.tags, StoredStationInfo.countrycode]))

        version = try migrateSchema(v: 3, current: version, ddl: StationCollection.table.createTableSQL(withIndexes: true, columns: [StationCollection.id, StationCollection.name, StationCollection.icon])) // manual column specification from before we added the "SORT_ORDER" column

        version = try migrateSchema(v: 5, current: version, ddl: StationCollectionInfo.table.createTableSQL(withIndexes: true))

        // new COLLECTION_INFO.SORT_ORDER column and pre-populate any pre-existing NULLs with default values
        version = try migrateSchema(v: 7, current: version, ddl: StationCollection.table.addColumnSQL(column: StationCollection.sortOrder, withIndexes: true) + [SQLExpression("UPDATE \(StationCollection.table.quotedName()) SET \(StationCollection.sortOrder.quotedName()) = ROWID WHERE \(StationCollection.sortOrder.quotedName()) IS NULL")])

        version = try migrateSchema(v: 10, current: version, ddl: StoredStationInfo.table.addColumnSQL(column: StoredStationInfo.homepage, withIndexes: true))
    }

    private func currentSchemaVersion() throws -> Int {
        try ctx.exec(sql: "CREATE TABLE IF NOT EXISTS SchemaVersion (id INTEGER PRIMARY KEY, version INTEGER)")
        try ctx.exec(sql: "INSERT OR IGNORE INTO SchemaVersion (id, version) VALUES (0, 0)")
        return try ctx.selectAll(sql: "SELECT version FROM SchemaVersion").first?.first?.longValue.flatMap({ Int($0) }) ?? 0
    }

    private func migrateSchema(v version: Int, current: Int, ddl: [SQLExpression]) throws -> Int {
        guard current < version else {
            return current
        }
        let startTime = Date.now
        try ctx.transaction {
            for stmnt in ddl {
                try ctx.exec(stmnt)
            }
            try ctx.exec(sql: "UPDATE SchemaVersion SET version = ?", parameters: [.long(Int64(version))])
        }
        logger.log("updated database schema to \(version) in \(Date.now.timeIntervalSince1970 - startTime.timeIntervalSince1970)")
        return version
    }

    func initializeCollections() throws {
        _ = try self.recentsCollection
        _ = try self.favoritesCollection
    }

    var favoritesCollection: StationCollection {
        get throws {
            try fetchCollection(named: StationCollection.favoritesCollectionName, create: true)!
        }
    }

    var recentsCollection: StationCollection {
        get throws {
            try fetchCollection(named: StationCollection.recentsCollectionName, create: true)!
        }
    }
}

public extension DatabaseManager {
    func fetchStation(id: StoredStationInfo.ID) throws -> StoredStationInfo? {
        try ctx.fetch(StoredStationInfo.self, primaryKeys: [SQLValue(id)])
    }

    func fetchStation(stationuuid: UUID) throws -> StoredStationInfo? {
        try ctx.query(StoredStationInfo.self)
            .where(.equals(StoredStationInfo.stationuuid, SQLValue(stationuuid.uuidString)))
            .eval()
            .load()
            .first
    }

    func fetchCollection(id: StationCollection.ID) throws -> StationCollection? {
        try ctx.fetch(StationCollection.self, primaryKeys: [SQLValue(id)])
    }

    func fetchCollection(named name: String, create: Bool) throws -> StationCollection? {
        if let collection = try ctx.query(StationCollection.self)
            .where(.equals(StationCollection.name, SQLValue(name)))
            .eval()
            .load()
            .first {
            return collection
        }

        if create {
            let maxSortOrder = try ctx.selectAll(sql: "SELECT MAX(\(StationCollection.sortOrder.quotedName())) FROM \(StationCollection.table.quotedName())").first?.first?.realValue ?? 0.0

            return try ctx.insert(StationCollection(name: name, sortOrder: maxSortOrder))
        }

        return nil
    }

    func saveStation(_ station: StoredStationInfo, unlessExists: Bool = true) throws -> StoredStationInfo {
        if unlessExists, let existingStation = try ctx.query(StoredStationInfo.self)
            .where(.equals(StoredStationInfo.stationuuid, SQLValue(station.stationuuid?.uuidString))).eval().load().first {
            return existingStation
        }
        return try ctx.insert(station, upsert: true)
    }

    func addStation(_ station: StoredStationInfo, toCollection collection: StationCollection) throws {
        // every addition to a collection will increment the sort order by 100
        let maxSortOrder = try ctx.selectAll(sql: "SELECT MAX(\(StationCollectionInfo.sortOrder.quotedName())) FROM \(StationCollectionInfo.table.quotedName())").first?.first?.realValue ?? 0.0
        try ctx.insert(StationCollectionInfo(stationID: station.id, collectionID: collection.id, sortOrder: maxSortOrder + 1.0), upsert: true)
    }

    func removeCollection(_ collection: StationCollection) throws {
        try ctx.delete(instances: [collection])
    }

    func removeStation(_ station: StoredStationInfo, fromCollection collection: StationCollection) throws {
        try ctx.delete(StationCollectionInfo.self, where: .equals(StationCollectionInfo.stationID, SQLValue(station.id)).and(.equals(StationCollectionInfo.collectionID, SQLValue(collection.id))))
    }
    
    /// Returns whether the given station is contained in the given collection.
    func isStation(_ station: StationInfo, inCollection collection: StationCollection) throws -> Bool {
        try ctx.query(StoredStationInfo.self, alias: "t0")
            .where(StoredStationInfo.stationuuid.alias("t0").equals(SQLValue(station.stationuuid?.uuidString)))
            .join(StationCollectionInfo.self, alias: "t1", kind: .inner, on: StationCollectionInfo.stationID)
            .where(StationCollectionInfo.collectionID.alias("t1").equals(SQLValue(collection.id)))
            .eval()
            .load()
            .first != nil
    }

    func fetchStations(inCollection collection: StationCollection) throws -> [(StoredStationInfo, StationCollectionInfo)] {
        try ctx.query(StoredStationInfo.self, alias: "t0")
            .join(StationCollectionInfo.self, alias: "t1", kind: .inner, on: StationCollectionInfo.stationID)
            .where(StationCollectionInfo.collectionID.alias("t1").equals(SQLValue(collection.id)))
            .orderBy(StationCollectionInfo.sortOrder.alias("t1"), order: .descending)
            .eval()
            .load()
            .map({ ($0.0!, $0.1!) })
    }

    func shuffleStations(inCollection collection: StationCollection) throws {
        var infos = try ctx.query(StationCollectionInfo.self)
            .where(StationCollectionInfo.collectionID.equals(SQLValue(collection.id)))
            .eval()
            .load()
        infos.shuffle()
        for (order, var info) in infos.enumerated() {
            info.sortOrder = Double(order) + 1.0
            try ctx.update(info)
        }
    }

    @discardableResult func createCollection(named name: String, sortOrder: Double? = nil) throws -> StationCollection {
        let sortOrder = try sortOrder ?? (ctx.selectAll(sql: "SELECT MAX(\(StationCollection.sortOrder.quotedName())) FROM \(StationCollection.table.quotedName())").first?.first?.realValue ?? 0.0)

        return try ctx.insert(StationCollection(name: name, sortOrder: sortOrder))
    }

    func fetchAllCollections() throws -> [StationCollection] {
        try ctx.query(StationCollection.self).eval().load()
    }

    func fetchCollections(standard: Bool?) throws -> [StationCollection] {
        let standardCollectionQuery = SQLPredicate.in(StationCollection.name, [SQLValue(StationCollection.favoritesCollectionName), SQLValue(StationCollection.recentsCollectionName)])

        return try ctx.query(StationCollection.self)
            .where(standard == true ? standardCollectionQuery : standard == false ? .not(standardCollectionQuery) : nil)
            .orderBy(StationCollection.sortOrder, order: .descending)
            .eval()
            .load()
    }

    func fetchCollections(forStation station: StoredStationInfo) throws -> [StationCollection] {
        try ctx.query(StationCollection.self, alias: "t0")
            .join(StationCollectionInfo.self, alias: "t1", kind: .inner, on: StationCollectionInfo.stationID)
            .where(StationCollectionInfo.stationID.alias("t1").equals(SQLValue(station.id)))
            .eval()
            .load()
            .compactMap(\.0)
    }

    func fetchCollectionCounts() throws -> [(StationCollection, Int)] {
        // TODO: SkipSQL currently does not support aggregate in joins, but doing something like this would be more efficient:
        //let collectionInfos: [(StationCollection, CountOf<StationCollectionInfo>)] = try ctx.query(StationCollection.self, "t0", join: .inner, on: StationCollectionInfo.collectionID, CountOf<StationCollectionInfo>.self, "t1").load()

        let collectionInfos = try ctx.query(StationCollection.self, alias: "t0")
            .join(StationCollectionInfo.self, alias: "t1", kind: .left, on: StationCollectionInfo.collectionID)
            .orderBy(StationCollection.sortOrder.alias("t0"), order: .descending)
            .eval()
            .load()

        // build up a map of all the keys
        var collectionInfoCountMap: [StationCollection.ID: Int] = [:]
        for info in collectionInfos {
            if let collection = info.0 {
                collectionInfoCountMap[collection.id, default: 0] += (info.1 == nil ? 0 : 1) // outer join might have nil when there are no members of the collection
            }
        }

        // now return the tuple of the collections and counts
        var collectionInfoCounts: [(StationCollection, Int)] = []
        for collection in collectionInfos.compactMap(\.0) {
            if let count = collectionInfoCountMap.removeValue(forKey: collection.id) {
                collectionInfoCounts.append((collection, count))
            }
        }
        return collectionInfoCounts
    }
}

/// A station stored locally
public struct StoredStationInfo : StationInfo, Identifiable, Hashable, Codable, SQLCodable {
    public typealias ID = Int64

    public let id: ID
    static let id = SQLColumn(name: "ID", type: .long, primaryKey: true, autoincrement: true)

    // stationuuid: 01234567-89ab-cdef-0123-456789abcdef
    public var stationuuid: UUID?
    static let stationuuid = SQLColumn(name: "STATION_UUID", type: .text, index: SQLIndex(name: "IDX_SERVER_UUID"))

    // name: Best Radio
    public var name: String
    static let name = SQLColumn(name: "NAME", type: .text, index: SQLIndex(name: "IDX_STATION_NAME"))

    // url: http://www.example.com/test.pls
    public var url: String
    static let url = SQLColumn(name: "URL", type: .text, index: SQLIndex(name: "IDX_STATION_URL"))

    public var homepage: String?
    static let homepage = SQLColumn(name: "HOMEPAGE", type: .text, index: SQLIndex(name: "IDX_STATION_HOMEPAGE"))

    // favicon: https://www.example.com/icon.png
    public var favicon: String?
    static let favicon = SQLColumn(name: "ICON", type: .text)

    // tags: jazz,pop,rock,indie
    public var tags: String?
    static let tags = SQLColumn(name: "TAGS", type: .text, index: SQLIndex(name: "IDX_STATION_TAGS"))

    // countrycode: US
    public var countrycode: String?
    static let countrycode = SQLColumn(name: "COUNTRY_CODE", type: .text, index: SQLIndex(name: "IDX_STATION_COUNTY_CODE"))

    public static let table = SQLTable(name: "STATION_INFO", columns: [id, stationuuid, name, url, homepage, favicon, tags, countrycode])

    public init(id: ID = 0, stationuuid: UUID? = nil, name: String, url: String, homepage: String? = nil, favicon: String? = nil, tags: String? = nil, countrycode: String? = nil) {
        self.id = id
        self.stationuuid = stationuuid
        self.name = name
        self.url = url
        self.homepage = homepage
        self.favicon = favicon
        self.tags = tags
        self.countrycode = countrycode
    }

    public init(row: SQLRow, context: SQLContext) throws {
        self.id = try Self.id.longValueRequired(in: row)
        self.stationuuid = Self.stationuuid.textValue(in: row).flatMap({ UUID(uuidString: $0) })
        self.name = try Self.name.textValueRequired(in: row)
        self.url = try Self.url.textValueRequired(in: row)
        self.homepage = Self.homepage.textValue(in: row)
        self.favicon = Self.favicon.textValue(in: row)
        self.tags = Self.tags.textValue(in: row)
        self.countrycode = Self.countrycode.textValue(in: row)
    }

    public func encode(row: inout SQLRow) throws {
        row[Self.id] = SQLValue(self.id)
        row[Self.stationuuid] = SQLValue(self.stationuuid?.uuidString)
        row[Self.name] = SQLValue(self.name)
        row[Self.url] = SQLValue(self.url)
        row[Self.homepage] = SQLValue(self.homepage)
        row[Self.favicon] = SQLValue(self.favicon)
        row[Self.tags] = SQLValue(self.tags)
        row[Self.countrycode] = SQLValue(self.countrycode)
    }

    /// Create this stored station from the StationInfo API type
    public static func create(from info: StationInfo) -> Self {
        if let storedInfo = info as? StoredStationInfo {
            return storedInfo
        }

        var storedInfo = StoredStationInfo(name: info.name, url: info.url)
        storedInfo.stationuuid = info.stationuuid
        storedInfo.name = info.name
        storedInfo.url = info.url
        storedInfo.homepage = info.homepage
        storedInfo.favicon = info.favicon
        storedInfo.tags = info.tags
        storedInfo.countrycode = info.countrycode

        return storedInfo
    }
}


public struct StationCollection : Identifiable, Hashable, Codable, SQLCodable {
    /// The symbolic name for the favorites collection
    public static let favoritesCollectionName = "_favorites"
    /// The symbolic name for the recently playes items collection
    public static let recentsCollectionName = "_recents"

    public var isStandardCollection: Bool {
        self.name == StationCollection.favoritesCollectionName || self.name == StationCollection.recentsCollectionName
    }

    public typealias ID = Int64

    public let id: ID
    static let id = SQLColumn(name: "ID", type: .long, primaryKey: true, autoincrement: true)

    public var name: String
    static let name = SQLColumn(name: "NAME", type: .text, index: SQLIndex(name: "IDX_COLLECTION_NAME"))

    public var icon: String?
    static let icon = SQLColumn(name: "ICON", type: .text)

    public var sortOrder: Double
    static let sortOrder = SQLColumn(name: "SORT_ORDER", type: .real, index: SQLIndex(name: "IDX_COLLECTION_SORT_ORDER"))

    public static let table = SQLTable(name: "COLLECTION_INFO", columns: [id, name, icon, sortOrder])

    public init(id: ID = 0, name: String, icon: String? = nil, sortOrder: Double) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
    }

    public init(row: SQLRow, context: SQLContext) throws {
        self.id = try Self.id.longValueRequired(in: row)
        self.name = try Self.name.textValueRequired(in: row)
        self.icon = Self.icon.textValue(in: row)
        self.sortOrder = try Self.sortOrder.realValueRequired(in: row)
    }

    public func encode(row: inout SQLRow) throws {
        row[Self.id] = SQLValue(self.id)
        row[Self.name] = SQLValue(self.name)
        row[Self.icon] = SQLValue(self.icon)
        row[Self.sortOrder] = SQLValue(self.sortOrder)
    }
}

/// The link between the categories and
public struct StationCollectionInfo : Identifiable, SQLCodable {
    public struct ID : Hashable {
        public let stationID: StoredStationInfo.ID
        public let collectionID: StationCollection.ID
    }

    public var id: ID { ID(stationID: stationID, collectionID: collectionID) }

    public let stationID: StoredStationInfo.ID
    static let stationID = SQLColumn(name: "STATION_ID", type: .long, primaryKey: true, references: SQLForeignKey(table: StoredStationInfo.table, column: StoredStationInfo.id, onDelete: .cascade))

    public let collectionID: StationCollection.ID
    static let collectionID = SQLColumn(name: "COLLECTION_ID", type: .long, primaryKey: true, references: SQLForeignKey(table: StationCollection.table, column: StationCollection.id, onDelete: .cascade))

    public var sortOrder: Double
    static let sortOrder = SQLColumn(name: "SORT_ORDER", type: .real)

    public static let table = SQLTable(name: "STATION_COLLECTION", columns: [stationID, collectionID, sortOrder])

    public init(stationID: StoredStationInfo.ID, collectionID: StationCollection.ID, sortOrder: Double) {
        self.stationID = stationID
        self.collectionID = collectionID
        self.sortOrder = sortOrder
    }

    public init(row: SQLRow, context: SQLContext) throws {
        self.stationID = try Self.stationID.longValueRequired(in: row)
        self.collectionID = try Self.collectionID.longValueRequired(in: row)
        self.sortOrder = try Self.sortOrder.realValueRequired(in: row)
    }

    public func encode(row: inout SQLRow) throws {
        row[Self.stationID] = SQLValue(self.stationID)
        row[Self.collectionID] = SQLValue(self.collectionID)
        row[Self.sortOrder] = SQLValue(self.sortOrder)
    }
}
