-- SenseFS Vector Database Schema
-- SQLite3 database for storing document embeddings and metadata

-- Main documents table with vector embeddings
CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    content TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    language TEXT NOT NULL,
    embedding BLOB NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL,
    file_size INTEGER,
    UNIQUE(file_path, chunk_index)
);

-- Indexes for fast lookups and aggregations
CREATE INDEX IF NOT EXISTS idx_documents_file_path ON documents(file_path);
CREATE INDEX IF NOT EXISTS idx_documents_language ON documents(language);
CREATE INDEX IF NOT EXISTS idx_documents_file_path_chunk ON documents(file_path, chunk_index);
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at DESC);

-- Pragmas for performance
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=-32000;  -- 32MB cache
PRAGMA temp_store=MEMORY;
