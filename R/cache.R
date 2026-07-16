##
## cache.R: SQLite3-based persistent data store for UI consumption
##
## Provides persistent storage of provider data with:
## - SQLite3 storage for reliability and queryability
## - Metadata tracking (source, timestamps, versions)
## - No automatic expiration - data refresh is manual
## - Serialization of complex R objects
##
## Data refresh is handled separately by R/refresh_data.R
##

suppressPackageStartupMessages({
  library(R6)
  library(DBI)
  library(RSQLite)
  library(glue)
})

#' DataStore Class
#'
#' R6 class for persistent storage of provider data using SQLite3.
#' This is the static storage layer consumed by the UI.
#' Data is never automatically expired - refresh is a manual operation.
#'
#' @export
DataStore <- R6::R6Class(
  "DataStore",
  public = list(
    #' @field dbPath Path to SQLite database file.
    dbPath = NULL,

    #' @field conn Database connection (lazily initialized).
    conn = NULL,

    #' @description
    #' Initialize DataStore.
    #' @param dbPath Path to SQLite database file.
    initialize = function(dbPath = "OUTPUT/datastore.sqlite") {
      self$dbPath <- dbPath

      # Ensure directory exists
      dir.create(dirname(dbPath), recursive = TRUE, showWarnings = FALSE)
    },

    #' @description
    #' Get or create database connection.
    #' @return DBI connection object.
    getConnection = function() {
      if (is.null(self$conn) || !DBI::dbIsValid(self$conn)) {
        self$conn <- DBI::dbConnect(RSQLite::SQLite(), self$dbPath)
        private$initializeTables()
      }
      return(self$conn)
    },

    #' @description
    #' Close database connection.
    close = function() {
      if (!is.null(self$conn) && DBI::dbIsValid(self$conn)) {
        DBI::dbDisconnect(self$conn)
        self$conn <- NULL
      }
    },

    #' @description
    #' Get a stored value by key.
    #' @param key Storage key string.
    #' @return Stored value or NULL if not found.
    get = function(key) {
      conn <- self$getConnection()

      query <- glue::glue_sql(
        "SELECT value FROM data_store WHERE key = {key}",
        .con = conn
      )

      result <- DBI::dbGetQuery(conn, query)

      if (nrow(result) == 0) {
        return(NULL)
      }

      # Deserialize value
      tryCatch({
        value <- unserialize(charToRaw(result$value[1]))
        return(value)
      }, error = function(e) {
        warning(paste0("Failed to deserialize value for key '", key, "': ", e$message))
        return(NULL)
      })
    },

    #' @description
    #' Store a value with metadata.
    #' @param key Storage key string.
    #' @param value Value to store (any R object).
    #' @param provider Name of the provider that generated this data.
    #' @param version Optional version string.
    #' @return Invisible TRUE on success.
    set = function(key, value, provider = "unknown", version = NULL) {
      conn <- self$getConnection()

      # Serialize value
      serialized <- rawToChar(serialize(value, NULL, ascii = TRUE))
      now <- as.numeric(Sys.time())
      version <- if (is.null(version)) "" else version

      # Upsert
      query <- glue::glue_sql(
        "INSERT OR REPLACE INTO data_store
         (key, value, provider, version, created_at, updated_at)
         VALUES ({key}, {serialized}, {provider}, {version}, 
                 COALESCE((SELECT created_at FROM data_store WHERE key = {key}), {now}),
                 {now})",
        .con = conn
      )

      DBI::dbExecute(conn, query)
      return(invisible(TRUE))
    },

    #' @description
    #' Delete a stored value.
    #' @param key Storage key string.
    #' @return Invisible TRUE on success.
    delete = function(key) {
      conn <- self$getConnection()

      query <- glue::glue_sql(
        "DELETE FROM data_store WHERE key = {key}",
        .con = conn
      )

      DBI::dbExecute(conn, query)
      return(invisible(TRUE))
    },

    #' @description
    #' Get metadata for a stored entry.
    #' @param key Storage key string.
    #' @return List with metadata or NULL if not found.
    getMetadata = function(key) {
      conn <- self$getConnection()

      query <- glue::glue_sql(
        "SELECT provider, version, created_at, updated_at
         FROM data_store WHERE key = {key}",
        .con = conn
      )

      result <- DBI::dbGetQuery(conn, query)

      if (nrow(result) == 0) {
        return(NULL)
      }

      return(list(
        provider = result$provider[1],
        version = result$version[1],
        created_at = as.POSIXct(result$created_at[1], origin = "1970-01-01"),
        updated_at = as.POSIXct(result$updated_at[1], origin = "1970-01-01")
      ))
    },

    #' @description
    #' List all keys, optionally filtered by provider.
    #' @param provider Optional provider name to filter by.
    #' @return Character vector of keys.
    listKeys = function(provider = NULL) {
      conn <- self$getConnection()

      if (is.null(provider)) {
        query <- glue::glue_sql(
          "SELECT key FROM data_store ORDER BY key",
          .con = conn
        )
      } else {
        query <- glue::glue_sql(
          "SELECT key FROM data_store WHERE provider = {provider} ORDER BY key",
          .con = conn
        )
      }

      result <- DBI::dbGetQuery(conn, query)
      return(result$key)
    },

    #' @description
    #' Check if a key exists.
    #' @param key Storage key string.
    #' @return TRUE if key exists, FALSE otherwise.
    exists = function(key) {
      conn <- self$getConnection()

      query <- glue::glue_sql(
        "SELECT 1 FROM data_store WHERE key = {key} LIMIT 1",
        .con = conn
      )

      result <- DBI::dbGetQuery(conn, query)
      return(nrow(result) > 0)
    },

    #' @description
    #' Clear all data for a specific provider.
    #' @param provider Provider name.
    #' @return Number of deleted entries.
    clearProvider = function(provider) {
      conn <- self$getConnection()

      query <- glue::glue_sql(
        "DELETE FROM data_store WHERE provider = {provider}",
        .con = conn
      )

      result <- DBI::dbExecute(conn, query)
      message(paste0("Cleared ", result, " entries for provider: ", provider))
      return(result)
    },

    #' @description
    #' Clear all stored data.
    #' @return Number of deleted entries.
    clearAll = function() {
      conn <- self$getConnection()

      query <- "DELETE FROM data_store"
      result <- DBI::dbExecute(conn, query)
      message(paste0("Cleared ", result, " entries"))
      return(result)
    },

    #' @description
    #' Log a refresh operation.
    #' @param provider Provider name.
    #' @param status Status string ("started", "completed", "failed").
    #' @param message Optional message.
    #' @param recordsAffected Number of records affected.
    logRefresh = function(provider, status, message = NULL, recordsAffected = 0) {
      conn <- self$getConnection()

      message <- if (is.null(message)) "" else message

      query <- glue::glue_sql(
        "INSERT INTO refresh_log (provider, status, message, records_affected, timestamp)
         VALUES ({provider}, {status}, {message}, {recordsAffected}, {as.numeric(Sys.time())})",
        .con = conn
      )

      DBI::dbExecute(conn, query)
    },

    #' @description
    #' Get refresh history for a provider.
    #' @param provider Optional provider name to filter by.
    #' @param limit Maximum number of records to return.
    #' @return Data frame with refresh history.
    getRefreshHistory = function(provider = NULL, limit = 100) {
      conn <- self$getConnection()

      if (is.null(provider)) {
        query <- glue::glue_sql(
          "SELECT * FROM refresh_log ORDER BY timestamp DESC LIMIT {limit}",
          .con = conn
        )
      } else {
        query <- glue::glue_sql(
          "SELECT * FROM refresh_log WHERE provider = {provider}
           ORDER BY timestamp DESC LIMIT {limit}",
          .con = conn
        )
      }

      result <- DBI::dbGetQuery(conn, query)
      if (nrow(result) > 0) {
        result$timestamp <- as.POSIXct(result$timestamp, origin = "1970-01-01")
      }
      return(result)
    },

    #' @description
    #' Get storage statistics.
    #' @return List with storage statistics.
    stats = function() {
      conn <- self$getConnection()

      totalQuery <- "SELECT COUNT(*) as count FROM data_store"
      total <- DBI::dbGetQuery(conn, totalQuery)$count

      providersQuery <- "SELECT DISTINCT provider FROM data_store"
      providers <- DBI::dbGetQuery(conn, providersQuery)$provider

      sizeQuery <- "SELECT SUM(LENGTH(value)) as size FROM data_store"
      sizeBytes <- DBI::dbGetQuery(conn, sizeQuery)$size
      sizeBytes <- if (is.na(sizeBytes)) 0 else sizeBytes

      oldestQuery <- "SELECT MIN(updated_at) as oldest FROM data_store"
      oldest <- DBI::dbGetQuery(conn, oldestQuery)$oldest
      oldest <- if (is.na(oldest)) NA else as.POSIXct(oldest, origin = "1970-01-01")

      newestQuery <- "SELECT MAX(updated_at) as newest FROM data_store"
      newest <- DBI::dbGetQuery(conn, newestQuery)$newest
      newest <- if (is.na(newest)) NA else as.POSIXct(newest, origin = "1970-01-01")

      return(list(
        total_entries = total,
        providers = providers,
        size_bytes = sizeBytes,
        size_mb = round(sizeBytes / (1024 * 1024), 2),
        oldest_update = oldest,
        newest_update = newest,
        db_path = self$dbPath
      ))
    },

    #' @description
    #' Print storage information.
    print = function() {
      stats <- self$stats()
      cat("<DataStore>\n")
      cat(paste0("  Database: ", stats$db_path, "\n"))
      cat(paste0("  Total entries: ", stats$total_entries, "\n"))
      cat(paste0("  Providers: ", paste(stats$providers, collapse = ", "), "\n"))
      cat(paste0("  Size: ", stats$size_mb, " MB\n"))
      if (!is.na(stats$oldest_update)) {
        cat(paste0("  Oldest update: ", stats$oldest_update, "\n"))
        cat(paste0("  Newest update: ", stats$newest_update, "\n"))
      }
    }
  ),

  private = list(
    # Clean up connection on garbage collection
    finalize = function() {
      self$close()
    },

    #' Initialize database tables
    initializeTables = function() {
      conn <- self$conn

      # Main data store table
      DBI::dbExecute(conn, "
        CREATE TABLE IF NOT EXISTS data_store (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          provider TEXT NOT NULL,
          version TEXT,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        )
      ")

      # Index for provider queries
      DBI::dbExecute(conn, "
        CREATE INDEX IF NOT EXISTS idx_provider ON data_store (provider)
      ")

      # Refresh log table
      DBI::dbExecute(conn, "
        CREATE TABLE IF NOT EXISTS refresh_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          provider TEXT NOT NULL,
          status TEXT NOT NULL,
          message TEXT,
          records_affected INTEGER DEFAULT 0,
          timestamp REAL NOT NULL
        )
      ")

      # Index for log queries
      DBI::dbExecute(conn, "
        CREATE INDEX IF NOT EXISTS idx_log_provider ON refresh_log (provider, timestamp)
      ")
    }
  )
)


#' Create a configured DataStore instance
#'
#' Factory function for creating DataStore.
#'
#' @param dbPath Path to SQLite database file.
#' @return Configured DataStore instance.
#' @export
createDataStore <- function(dbPath = "OUTPUT/datastore.sqlite") {
  DataStore$new(dbPath = dbPath)
}


#' ProviderStore wrapper for provider-specific operations
#'
#' Returns a wrapper that automatically handles provider namespacing.
#'
#' @param dataStore DataStore instance.
#' @param providerName Provider name.
#' @return List with get/set/delete methods scoped to provider.
#' @export
createProviderStore <- function(dataStore, providerName) {
  prefixKey <- function(key) {
    return(paste0(providerName, ":", key))
  }

  return(list(
    get = function(key) {
      dataStore$get(prefixKey(key))
    },
    set = function(key, value, version = NULL) {
      dataStore$set(prefixKey(key), value, provider = providerName, version = version)
    },
    delete = function(key) {
      dataStore$delete(prefixKey(key))
    },
    exists = function(key) {
      dataStore$exists(prefixKey(key))
    },
    listKeys = function() {
      dataStore$listKeys(provider = providerName)
    },
    getMetadata = function(key) {
      dataStore$getMetadata(prefixKey(key))
    },
    clear = function() {
      dataStore$clearProvider(providerName)
    },
    logRefresh = function(status, message = NULL, recordsAffected = 0) {
      dataStore$logRefresh(providerName, status, message, recordsAffected)
    },
    getRefreshHistory = function(limit = 100) {
      dataStore$getRefreshHistory(providerName, limit)
    }
  ))
}
