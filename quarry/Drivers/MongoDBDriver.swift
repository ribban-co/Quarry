import Foundation
import MongoKitten
import MongoCore

// MARK: - MongoDB Wrappers
struct MongoDBWrapper: DatabaseWrapper {
    let database: MongoDatabase
    
    var name: String {
        database.name
    }
    var size: String? { nil }
    var tableCount: Int? { nil }
}

struct MongoCollectionWrapper: CollectionWrapper {
    var schema: String?
    
    var id: ObjectIdentifier
    let collection: MongoCollection
    let type: String
    
    var name: String {
        collection.name
    }
    
    init(collection: MongoCollection, type: String = "collection") {
        self.collection = collection
        self.id = ObjectIdentifier(collection)
        self.type = type
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
    
    static func == (lhs: MongoCollectionWrapper, rhs: MongoCollectionWrapper) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

actor MongoDBDriver: DatabaseDriver {
    func getInformationSchema() async throws -> [InformationSchema] {
        throw DatabaseError.notImplemented("MongoDB driver not yet implemented")
    }

    func deleteCollection(named collectionName: String, databaseSchema: String?) async throws {
        throw DatabaseError.notImplemented("MongoDB driver not yet implemented")
    }

    func getDatabaseMetadata() async throws -> [MongoDBWrapper] {
        throw DatabaseError.notImplemented("MongoDB driver not yet implemented")
    }

    func findDocuments(in collectionName: String, filter: DatabaseDocument) async throws -> [QueryResult] {
        let result = try await findDocuments(
            in: collectionName,
            databaseSchema: nil,
            filter: filter,
            skip: 0,
            limit: 100,
            sortBy: nil,
            ascending: nil
        )
        return [result]
    }
    
    func buildAICommandPromptSystemPrompt(_ message: String) async throws -> String {
        let currentDate = Date().formatted(.iso8601)
        
        // Get all available collections with error handling
        var collectionsList = ""
        do {
            let collections = try await listCollections(schema: nil)
            collectionsList = collections.map { "- \($0.name) (\($0.type))" }.joined(separator: "\n")
        } catch {
            collectionsList = "No collections available (connection error)"
        }
        
        return """
        You are a MongoDB query assistant designed for CMD+K quick actions. You help users generate, modify, or fix MongoDB queries based on their natural language requests.

        ## Core Responsibilities
        - Generate new MongoDB queries from natural language descriptions
        - Modify existing queries based on user requests
        - Fix syntax errors or logical issues in existing queries
        - Provide clear, optimized, and readable MongoDB query code

        ## Available Collections
        The database contains the following collections:
        \(collectionsList)

        ## Context Handling
        You will receive one of these contexts:
        1. **New Query Request**: User asks to create a query from scratch
        2. **Query Modification**: User provides existing query and asks for changes
        3. **Query Fix**: User provides broken query and asks for fixes

        ## Output Format Rules

        ### For New Queries:
        - Start with a comment describing what the query does
        - Follow with the MongoDB query
        - Use proper formatting and indentation
        - Include appropriate MongoDB operators

        ### For Query Modifications:
        - Return only the modified MongoDB query
        - No commentary unless the change is complex
        - Maintain original formatting style when possible

        ### For Query Fixes:
        - Return only the corrected MongoDB query
        - No explanation of what was wrong

        ## Examples

        **Example 1 - New Query:**
        **Input:** "Get all active users from the last month"
        **Output:**
        ```javascript
        // Find all active users created in the last 30 days
        db.users.find({
          status: "active",
          created_at: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) }
        })
        ```

        **Example 2 - Query Modification:**
        **Input:** "Add sorting by name to this query: db.products.find({price: {$gt: 100}})"
        **Output:**
        ```javascript
        db.products.find({price: {$gt: 100}}).sort({name: 1})
        ```

        **Example 3 - Query Fix:**
        **Input:** "Fix this query: db.user.find({age: {$gt: 30} AND"
        **Output:**
        ```javascript
        db.users.find({age: {$gt: 30}})
        ```

        ## Query Guidelines
        - Use collection names from the provided list
        - Use appropriate MongoDB operators ($gt, $lt, $in, $regex, etc.)
        - Use $regex for pattern matching
        - Use proper MongoDB date functions and operators
        - Optimize for readability and performance
        - Handle ambiguous requests by making reasonable assumptions based on available collections

        ## Formatting Rules
        - Return MongoDB query as plain text (no markdown code blocks)
        - Use consistent indentation (2 or 4 spaces)
        - Use proper MongoDB syntax and operators
        - Use double quotes for string literals
        - For multi-line queries, break at logical points

        ## Error Handling
        - If a collection name doesn't exist in the list, suggest the closest match
        - If the request is unclear, make reasonable assumptions
        - For complex requests requiring schema knowledge, use common field names (_id, name, created_at, updated_at, status, etc.)

        IMPORTANT: If you need detailed schema information about specific tables, use the get_table_schema tool.
        
        Current Date: \(currentDate)
        """
    }
    
    func buildSystemPrompt(for collectionName: String, databaseSchema: String?) async throws -> String {
        let currentDate = Date().formatted(.iso8601)
        let schema = await buildSchemaPrompt(for: collectionName)

        return """
        You are a MongoDB query assistant. Your primary task is to convert natural language user queries into valid MongoDB JSON filter queries.

        Core Responsibilities:
        - Convert the user query into a MongoDB JSON filter query.
        - Return ONLY the JSON filter object without explanation.
        - Use proper MongoDB query operators ($gt, $lt, $in, $regex, etc.).
        - Optimize the query for best performance.

        # Collection Schema
        The current collection structure is:
        \(schema)

        # Output Format
        Return ONLY the MongoDB JSON filter object.
        Do not include any explanation, preamble, or commentary.
        Do not wrap the output in code blocks or markdown.
        Format the JSON for readability with proper indentation.
        Simple queries can be on one line.

        # MongoDB Query Operators
        - Comparison: $eq, $ne, $gt, $gte, $lt, $lte, $in, $nin
        - Logical: $and, $or, $not, $nor
        - Element: $exists, $type
        - Evaluation: $regex, $expr, $text, $where
        - Array: $all, $elemMatch, $size

        # Examples

        **Example 1:**
        **Input:** Find all users where age is greater than 30
        **Output:**
        {"age": {"$gt": 30}}

        **Example 2:**
        **Input:** Get records where status is active and created date is in the last week
        **Output:**
        {
          "status": "active",
          "createdAt": {"$gte": {"$date": "\(Date().addingTimeInterval(-7 * 24 * 3600).ISO8601Format())"}}
        }

        **Example 3:**
        **Input:** Show me customers from New York or California with at least 5 orders
        **Output:**
        {
          "$or": [
            {"state": "New York"},
            {"state": "California"}
          ],
          "orderCount": {"$gte": 5}
        }

        **Example 4:**
        **Input:** Find documents where name starts with "John"
        **Output:**
        {"name": {"$regex": "^John"}}

        **Example 5:**
        **Input:** Find documents where tags array contains "urgent"
        **Output:**
        {"tags": "urgent"}

        # Important Notes
        - For date comparisons, use MongoDB Extended JSON format: {"$date": "ISO8601-string"}
        - For ObjectId matching, use: {"_id": {"$oid": "507f1f77bcf86cd799439011"}}
        - For regex patterns, use: {"field": {"$regex": "pattern"}}
        - For existence checks, use: {"field": {"$exists": true}}
        - For null checks, use: {"field": null}
        - Empty filter {} returns all documents

        # User Intent Detection
        - "find/get/show" → Simple filter query
        - "starts with" → Use $regex with "^pattern"
        - "ends with" → Use $regex with "pattern$"
        - "contains" → Use $regex with "pattern"
        - "in the last X days/weeks" → Use $gte with date calculation
        - "between X and Y" → Use $gte and $lte
        - "or" → Use $or operator
        - "not" → Use $ne or $not

        Current Date: \(currentDate)
        """
    }

    private func buildSchemaPrompt(for collectionName: String) async -> String {
        guard let mongoDatabase = connectedDatabase else {
            return "No database connection available"
        }

        do {
            let collection = mongoDatabase[collectionName]

            // Sample one document to infer structure
            let sampleDocument = try await collection.find().limit(1).firstResult()

            guard let doc = sampleDocument else {
                return """
                Collection: \(collectionName)
                Status: Empty collection (no documents found)
                Note: Common MongoDB fields include: _id, createdAt, updatedAt, name, status, etc.
                """
            }

            // Build field information
            var fieldInfo: [String] = []
            for (key, value) in doc {
                let typeInfo = getTypeDescription(value)
                fieldInfo.append("\(key): \(typeInfo)")
            }

            return """
            Collection: \(collectionName)
            Sample Document Structure:
            \(fieldInfo.joined(separator: "\n"))
            """
        } catch {
            return """
            Collection: \(collectionName)
            Error: Could not retrieve schema information
            Note: Use common MongoDB field patterns
            """
        }
    }

    private func getTypeDescription(_ value: Primitive?) -> String {
        switch value {
        case is ObjectId:
            return "ObjectId"
        case is String:
            return "String"
        case is Int32, is Int:
            return "Number"
        case is Double:
            return "Double"
        case is Bool:
            return "Boolean"
        case is Date:
            return "Date"
        case is Document:
            if let doc = value as? Document, doc.isArray {
                return "Array"
            }
            return "Object"
        case is Null:
            return "Null"
        default:
            return String(describing: type(of: value))
        }
    }
    
    typealias Database = MongoDBWrapper
    typealias Collection = MongoCollectionWrapper
    
    private var connectedDatabase: MongoDatabase?
    
    func connect(to connectionUri: String) async throws -> MongoDBWrapper {
        let database = try await MongoDatabase.connect(to: connectionUri)
        self.connectedDatabase = database
        return MongoDBWrapper(database: database)
    }
    
    func switchDatabase(to databaseName: String) async throws {
        guard let connectedDatabase = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }

        let newDb = connectedDatabase.pool[databaseName]
        self.connectedDatabase = newDb
    }

    func getCurrentDatabaseWrapper() async -> MongoDBWrapper? {
        guard let db = connectedDatabase else { return nil }
        return MongoDBWrapper(database: db)
    }
    
    func disconnect() async {
        if let database = connectedDatabase,
           let cluster = database.pool as? MongoCluster {
            await cluster.disconnect()
        }
        connectedDatabase = nil
    }
    
    func reconnect() async throws {
        throw DatabaseError.notImplemented("MongoDB driver reconnect not yet implemented")
    }
    
    func ping(to connectionUri: String) async throws {
        do {
            let db = try await MongoDatabase.connect(to: connectionUri)
            if let cluster = db.pool as? MongoCluster {
                await cluster.disconnect()
            }
        } catch {
            throw DatabaseError.connectionFailed("Ping failed: \(error.localizedDescription)")
        }
    }
    
    func getBuildInfo() async throws -> BuildInfo {
        guard let database = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }
        
        let buildInfo = try await database.getBuildInfo()
        return BuildInfo(version: buildInfo.version, databaseType: DatabaseType.mongodb)
    }
    
    func listDatabases() async throws -> [MongoDBWrapper] {
        guard let database = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }
        
        let databases = try await database.pool.listDatabases()
        return databases.map { MongoDBWrapper(database: $0) }
    }
    
    func listCollections(schema: String?) async throws -> [MongoCollectionWrapper] {
        guard let database = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }
        
        let collections = try await database.listCollections()
        return collections.map { MongoCollectionWrapper(collection: $0, type: "collection") }.sorted { $0.name < $1.name }
    }
    
    func getDocumentCount(for collectionName: String, filter: DatabaseDocument) async throws -> Int {
        guard let mongoDatabase = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }
        
        let collection = mongoDatabase[collectionName]
        return try await collection.count()
    }

    func findDocuments(in collectionName: String, filter: DatabaseDocument, skip: Int, limit: Int) async throws -> QueryResult {
        return try await findDocuments(in: collectionName, databaseSchema: nil, filter: filter, skip: skip, limit: limit, sortBy: nil, ascending: nil)
    }
    
    func findDocuments(in collectionName: String, databaseSchema: String?, filter: DatabaseDocument, skip: Int, limit: Int, sortBy: String?, ascending: Bool?) async throws -> QueryResult {
        guard let mongoDatabase = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }

        let collection = mongoDatabase[collectionName]

        // Parse filter from rawQuery if provided
        var mongoFilter: Document = [:]
        if let rawQuery = filter["rawQuery"]?.stringValue, !rawQuery.isEmpty {
            do {
                // Try to parse the JSON string as a MongoDB Document using Extended JSON format
                mongoFilter = try Document(fromJSON: rawQuery)
            } catch {
                // If parsing fails, log and continue with empty filter
                debugLog("Failed to parse MongoDB filter: \(error.localizedDescription)")
                debugLog("Filter string was: \(rawQuery)")
            }
        }

        // Build query with filter
        var query = mongoFilter.isEmpty ? collection.find() : collection.find(mongoFilter)
        query = query.skip(skip).limit(limit)

        // Add sorting if specified
        if let sortBy = sortBy {
            let sortOrder: Int32 = ascending == false ? -1 : 1
            query = query.sort([sortBy: sortOrder])
        }

        var convertedRows: [[String: QueryRowInfo]] = []
        var rawRows: [DatabaseRawRow] = []

        for try await document in query {
            let convertedRow = convertFormattedDocumentToRow(document.formattedPayload())

            convertedRows.append(convertedRow)
            rawRows.append(convertRawDocument(document))
        }

        return QueryResult(
            columns: [],
            rows: convertedRows,
            totalCount: convertedRows.count,
            rawRows: rawRows
        )
    }

    func createDocument(in collectionName: String, databaseSchema: String?, document: DatabaseDocument) async throws {
        guard let mongoDatabase = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }

        let collection = mongoDatabase[collectionName]

        // Convert dictionary to MongoDB Document
        var mongoDocument = MongoKitten.Document()
        for (key, value) in document {
            mongoDocument[key] = primitive(from: value)
        }

        let reply = try await collection.insertEncoded(mongoDocument)
        if reply.ok != 1 {
            throw MongoError.invalidData
        }
    }
    
    func updateDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID, data: DatabaseDocument) async throws {
        guard let mongoDatabase = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }

        let collection = mongoDatabase[collectionName]
        guard let objectIdString = id.value.stringValue,
              let objectId = ObjectId(objectIdString) else {
            throw MongoError.invalidData
        }

        // Create update document from dictionary
        var updateDoc = MongoKitten.Document()
        for (key, value) in data {
            updateDoc[key] = primitive(from: value)
        }

        let filter: MongoKitten.Document = ["_id": objectId]
        let result = try await collection.updateOne(where: filter, to: updateDoc)

        if result.updatedCount == 0 {
            throw MongoError.invalidData
        }
    }
    
    func deleteDocument(in collectionName: String, databaseSchema: String?, id: DatabaseRecordID) async throws {
        guard let mongoDatabase = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }
        
        let collection = mongoDatabase[collectionName]
        guard let objectIdString = id.value.stringValue,
              let objectId = ObjectId(objectIdString) else {
            throw MongoError.invalidData
        }
        
        let filter: MongoKitten.Document = ["_id": objectId]
        try await collection.deleteOne(where: filter)
    }
    
    func executeRawQuery(_ query: String, databaseSchema: String?) async throws -> [QueryResult] {
        guard connectedDatabase != nil else {
            throw MongoError.databaseNotInitialized
        }

        let queryColumns: [QueryColumnInfo] = [
            QueryColumnInfo(name: "message", dataType: "String", format: nil, index: 0),
            QueryColumnInfo(name: "query", dataType: "String", format: nil, index: 1),
            QueryColumnInfo(name: "note", dataType: "String", format: nil, index: 2)
        ]

        let convertedRows: [[String: QueryRowInfo]] = [
            [
                "message": QueryRowInfo(value: .string("MongoDB uses document-based queries, not SQL"), dataType: "String", format: nil),
                "query": QueryRowInfo(value: .string(query), dataType: "String", format: nil),
                "note": QueryRowInfo(value: .string("Use the collection browser or aggregation pipeline for MongoDB queries"), dataType: "String", format: nil)
            ]
        ]

        let convertedRawRows: [DatabaseRawRow] = [
            [
                "message": .string("MongoDB uses document-based queries, not SQL"),
                "query": .string(query),
                "note": .string("Use the collection browser or aggregation pipeline for MongoDB queries")
            ]
        ]

        return [QueryResult(
            columns: queryColumns,
            rows: convertedRows,
            totalCount: convertedRows.count,
            rawRows: convertedRawRows
        )]
    }
    
    func createCollection(named collectionName: String) async throws {
        guard let mongoDatabase = connectedDatabase else {
            throw MongoError.databaseNotInitialized
        }
        
        let createCommand: Document = ["create": collectionName]
        
        let connection = try await mongoDatabase.pool.next(for: .basic)
        _ = try await connection.execute(
            createCommand,
            namespace: mongoDatabase.commandNamespace
        )
    }
    
    func renameCollection(databaseSchema: String?, from oldName: String, to newName: String) async throws {
        guard connectedDatabase != nil else {
            throw MongoError.databaseNotInitialized
        }
        throw DatabaseError.notImplemented("MongoDB collection rename not yet implemented")
    }
    
    func getSchema(for collectionName: String, schema: String?) async throws -> DatabaseSchemaResult? {
        throw DatabaseError.notImplemented("MongoDB schema introspection not yet implemented")
    }

    func getIndexes(for collectionName: String, schema: String?) async throws -> [DatabaseIndexInfo] {
        // MongoDB indexes are different from relational database indexes
        // This can be implemented in the future by querying collection.listIndexes()
        return []
    }

    // MARK: - Database Management

    func createDatabase(named databaseName: String, options: CreateDatabaseOptions) async throws {
        guard let database = connectedDatabase,
              let cluster = database.pool as? MongoCluster else {
            throw MongoError.databaseNotInitialized
        }

        let newDb = cluster[databaseName]
        let tempCollectionName = "_quarry_temp_\(UUID().uuidString)"
        let createCommand: Document = ["create": tempCollectionName]

        let connection = try await newDb.pool.next(for: .basic)
        _ = try await connection.execute(createCommand, namespace: newDb.commandNamespace)

        let dropCommand: Document = ["drop": tempCollectionName]
        _ = try await connection.execute(dropCommand, namespace: newDb.commandNamespace)

        debugLog("✓ Created database \(databaseName)")
    }

    // MARK: - Helper Methods
    
    private func convertFormattedDocumentToRow(_ formattedDoc: MongoFormattedDocumentPayload) -> [String: QueryRowInfo] {
        var row: [String: QueryRowInfo] = [:]

        row["__formattedDocument"] = QueryRowInfo(
            value: .string(formattedDoc.jsonString),
            dataType: "FormattedDocument",
            format: nil,
            metadata: .mongoDocument(formattedDoc)
        )

        row["_id"] = QueryRowInfo(value: .objectID(formattedDoc.id), dataType: "ObjectId", format: nil)

        for field in formattedDoc.fields {
            if field.key == "_id" {
                continue
            }

            row[field.key] = QueryRowInfo(
                value: .string(field.formattedValue.value),
                dataType: field.formattedValue.type,
                format: nil,
                metadata: .mongoField(field)
            )
        }

        return row
    }

    private func convertRawDocument(_ document: Document) -> DatabaseRawRow {
        var row: DatabaseRawRow = [:]
        for key in document.keys {
            row[key] = databaseValue(from: document[key])
        }
        return row
    }

    private func databaseValue(from primitive: Primitive?) -> DatabaseValue? {
        guard let primitive else { return .null }

        switch primitive {
        case let objectId as ObjectId:
            return .objectID(objectId.hexString)
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let int as Int32:
            return .int(Int(int))
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let date as Date:
            return .date(date)
        case let decimal as BSON.Decimal128:
            return .decimalString(String(describing: decimal.toString))
        case is Null:
            return .null
        case let array as [Primitive]:
            return .array(array.compactMap(databaseValue(from:)))
        case let document as Document:
            var object: [String: DatabaseValue] = [:]
            for key in document.keys {
                guard let value = databaseValue(from: document[key]) else { return nil }
                object[key] = value
            }
            return .object(object)
        default:
            return nil
        }
    }

    private func primitive(from value: DatabaseValue) -> Primitive? {
        switch value {
        case .null:
            return Null()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .int64(let value):
            return Int(exactly: value) ?? Double(value)
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .date(let value):
            return value
        case .decimalString(let value):
            return value
        case .objectID(let value):
            return ObjectId(value)
        case .array(let values):
            var arrayDocument = MongoKitten.Document()
            for (index, item) in values.enumerated() {
                arrayDocument["\(index)"] = primitive(from: item)
            }
            return arrayDocument
        case .object(let values):
            var document = MongoKitten.Document()
            for (key, value) in values {
                document[key] = primitive(from: value)
            }
            return document
        case .data, .uuid:
            return nil
        }
    }
}
