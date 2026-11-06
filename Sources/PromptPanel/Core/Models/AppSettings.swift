import Foundation
import GRDB

/// Key-value settings stored in the database.
struct AppSetting: Codable, Equatable {
    /// Setting key (primary key).
    var key: String
    /// Setting value.
    var value: String?
}

// MARK: - GRDB Conformance

extension AppSetting: FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_settings"

    enum Columns: String, ColumnExpression {
        case key
        case value
    }
}
