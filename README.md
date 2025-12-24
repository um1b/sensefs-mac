# SenseFS - Semantic File Search for macOS

> Intelligent semantic search across your files using CoreML embeddings

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg)]()
[![Swift](https://img.shields.io/badge/swift-5.0-orange.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()

## Overview

SenseFS is a native macOS application that brings powerful semantic search to your local files. Unlike traditional keyword search, SenseFS understands the *meaning* of your queries and finds relevant content even when exact keywords don't match.

### Key Features

- 🔍 **Semantic Search** - Find files by meaning using 384-dimensional embeddings
- 🌍 **12+ Languages** - Auto-detected multilingual support (Japanese, English, Spanish, French, German, Chinese, Korean, Italian, Portuguese, Dutch, Russian, and more)
- 📄 **Multiple Formats** - Text files, PDFs (PDFKit), Office documents (DOCX/XLSX/PPTX), and images with OCR
- 🚀 **Fast & Local** - Neural Engine-accelerated embeddings (~50ms per chunk), 100% offline
- 🔒 **Privacy First** - No network requests, no telemetry, app sandboxed
- ✨ **Smart Indexing** - Auto-skip patterns (20+ directories), incremental reindexing, change detection
- 🎨 **Native UI** - SwiftUI with 4 tabs: Search, Index, Licenses, Settings
- 📊 **Organized Results** - File grouping, chunk counts, relevance scores with color coding
- 📜 **Open Source** - Full dependency attribution in Licenses tab

## Screenshots

> Beautiful, native macOS interface with semantic search capabilities

## Quick Start

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later (for building from source)
- ~500 MB disk space (for app + models)

### Installation

#### Option 1: Download .app (Recommended)

1. **Download** the latest `SenseFS.app.zip` from [Releases](../../releases)
2. **Unzip** the downloaded file (double-click or use `unzip`)
3. **Move** `SenseFS.app` to your Applications folder
4. **First Launch**:
   - Right-click on `SenseFS.app` → Open (or use Finder → Applications → SenseFS)
   - Click "Open" when macOS shows the security warning
   - (Only needed first time - app is not notarized)
5. **Grant Permissions**:
   - Allow file access when indexing folders
   - No other permissions required

> **Note**: If macOS prevents opening, go to System Settings → Privacy & Security → Allow apps from App Store and identified developers

#### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/sensefs-mac.git
cd sensefs-mac

# Install Git LFS (if not already installed)
brew install git-lfs
git lfs pull  # Download ML models

# Open in Xcode
open SenseFS.xcodeproj

# Build and run (⌘R)
```

### First Run

1. **Index Your Files**
   - Click "Add Folder" or drag-and-drop a folder
   - SenseFS will index all supported files
   - Indexing speed: ~30-60 seconds for 100 files

2. **Search**
   - Type your query in natural language
   - Results appear instantly with relevance scores
   - Click any result to open the file

## How It Works

### Semantic Search Engine
1. **Text Extraction**: Extracts text from PDFs, Office documents, and images using native macOS frameworks
2. **Smart Chunking**: Breaks documents into 512-character chunks with 1-sentence overlap
3. **Embedding Generation**: Converts text to 384-dimensional vectors using multilingual-e5-small CoreML model
4. **Vector Search**: Finds similar documents using cosine similarity
5. **Intelligent Ranking**: Deduplicates by file and shows max relevance score

### Indexing Features
- **Change Detection**: Only re-indexes modified files (checks timestamp + file size)
- **Batch Processing**: Embeds multiple chunks in a single inference call for efficiency
- **Auto-Skip Patterns**: Automatically excludes:
  - **Directories**: `node_modules`, `.git`, `.venv`, `build`, `dist`, `.next`, and 15+ more
  - **Common Files**: README, LICENSE, CHANGELOG, CONTRIBUTING
- **Progress Tracking**: Real-time progress with ETA and error reporting
- **Configurable Limits**:
  - Max file size: 10 MB (default, configurable)
  - Max database size: 1 GB (default, configurable)

### Performance Optimizations
- **Neural Engine Acceleration**: Uses Apple Silicon Neural Engine for fast inference
- **Dual-Model Loading**: CPU-only for instant startup, Neural Engine optimization in background
- **SQLite WAL Mode**: Enables concurrent reads during indexing
- **Model Caching**: Compiles and caches CoreML models in Application Support
- **Search Debouncing**: 300ms delay to prevent excessive queries

### Search Results
- **Color-Coded Scores**:
  - 🟢 Green (0.8-1.0): High confidence match
  - 🔵 Blue (0.6-0.8): Good match
  - 🟠 Orange (0.4-0.6): Moderate match
  - ⚪ Gray (<0.4): Low match
- **File Grouping**: Shows best chunk per file with total chunk count
- **Quick Open**: Click any result to open in default app

## Supported File Formats

| Type | Extensions | Extraction Method |
|------|-----------|-------------------|
| **Text** | `.txt`, `.md`, `.swift`, `.py`, `.js`, etc. | Native |
| **PDF** | `.pdf` | PDFKit |
| **Images** | `.jpg`, `.png`, `.heic`, `.tiff`, `.webp` | Vision OCR |
| **Office** | `.docx`, `.xlsx`, `.pptx` | ZIP/XML parsing |

## Architecture

```
SenseFS/
├── Core/                    # Business logic
│   ├── CoreMLEmbeddingService.swift  # ML model integration
│   ├── IndexingService.swift         # File indexing
│   ├── PDFTextExtractor.swift        # PDF extraction
│   ├── VisionOCRService.swift        # Image OCR
│   ├── OfficeDocumentExtractor.swift # Office docs
│   ├── TextChunker.swift             # Text chunking
│   └── SpellChecker.swift            # Spell correction
├── Database/                # Data layer
│   ├── DatabaseManager.swift         # SQLite manager
│   ├── VectorDatabase.swift          # Vector operations
│   └── schema.sql                    # DB schema
├── Services/                # Additional services
│   └── RAGService.swift              # Retrieval-Augmented Generation
├── Models/                  # Data models
│   ├── SearchResult.swift
│   ├── ChatMessage.swift
│   └── LanguageModel.swift
├── Views/                   # SwiftUI views
│   ├── SearchView.swift
│   ├── IndexView.swift
│   ├── LicensesView.swift
│   └── SettingsView.swift
└── Resources/
    ├── multilingual-e5-small-fp16.mlpackage  # CoreML model
    └── e5-tokenizer/                         # Tokenizer

```

## Technology Stack

### Core Technologies
- **UI Framework**: SwiftUI (macOS 14.0+)
- **Language**: Swift 5.0+ with async/await and actors
- **ML Framework**: CoreML with Neural Engine optimization
- **Database**: SQLite3 (C API) with WAL mode, optimized indexes

### ML Model
- **Model**: multilingual-e5-small (sentence embeddings)
- **Format**: CoreML MLModel (FP16 quantized)
- **Size**: 225 MB
- **Dimensions**: 384 (float32 vectors)
- **Max Tokens**: 512 per chunk
- **Tokenizer**: XLM-RoBERTa from Hugging Face
- **Languages**: 100+ languages supported automatically

### Text Extraction
- **PDFs**: PDFKit (native macOS framework)
- **Images**: Vision framework with VNRecognizeTextRequest (OCR)
- **Office Docs**: ZIPFoundation + XML parsing
  - DOCX: Extracts from `word/document.xml`
  - XLSX: Extracts shared strings and worksheets
  - PPTX: Extracts slide content

### Dependencies
- **ZIPFoundation** (0.9.0+) - Office document extraction
- **swift-transformers** (0.1.0+) - Tokenizer support
  - Includes: Jinja, Swift Argument Parser, Swift Collections

## Performance

| Operation | Time | Notes |
|-----------|------|-------|
| App Launch | < 1s | CPU-only model loads immediately |
| Neural Engine Optimization | 3-5s | Background, non-blocking |
| Index 100 text files | 30-60s | ~1-2 MB total, depends on content |
| Index with OCR (images) | Slower | Vision OCR processing adds overhead |
| Search Query | < 100ms | Across 10,000 chunks |
| Embedding Generation | ~50ms | Per chunk (with Neural Engine) |
| Database Query | < 10ms | SQLite with optimized indexes |

## Security & Privacy

- ✅ **App Sandbox** enabled
- ✅ **User-selected file access** only
- ✅ **Path traversal protection**
- ✅ **SQL injection prevention**
- ✅ **100% offline** - no network requests
- ✅ **No telemetry** - your data never leaves your Mac

## Configuration

### Settings (Configurable in Settings Tab)

| Setting | Default | Description |
|---------|---------|-------------|
| **Skip Code Files** | ON | Excludes .swift, .py, .js, .ts, .json, .xml, .html, .css, etc. |
| **Skip Images** | OFF | Excludes .jpg, .png, .heic image files from OCR processing |
| **Max File Size** | 10 MB | Files larger than this are skipped with error logged |
| **Max Database Size** | 1 GB | Total limit for all indexed content (embeddings + text) |

### Auto-Skip Patterns (Always Applied)

SenseFS automatically excludes common development artifacts:

**Directories (20+)**:
- Version control: `.git`, `.svn`, `.hg`
- Dependencies: `node_modules`, `vendor`, `Packages`
- Python: `venv`, `.venv`, `env`, `__pycache__`, `.pytest_cache`
- Build output: `build`, `dist`, `target`, `.next`, `.nuxt`
- IDE: `.idea`, `.vscode`
- Coverage: `coverage`, `.nyc_output`

**Files (Always)**:
- Documentation: `README.*`, `CHANGELOG.*`, `LICENSE.*`
- Contributing: `CONTRIBUTING.*`, `AUTHORS.*`

**Result**: ~50x faster indexing on typical projects with dependencies!

### Keyboard Shortcuts

- `⌘F` - Focus search
- `⌘⇧I` - View index
- `Esc` - Clear search
- `Enter` - Search immediately (bypasses debounce)

## Development

### Project Structure

```
sensefs-mac/
├── SenseFS/              # Main app source code
├── docs/                 # Documentation
├── Package.swift         # Swift Package Manager
├── SenseFS.xcodeproj/    # Xcode project
└── README.md
```

### Building

```bash
# Debug build
xcodebuild -project SenseFS.xcodeproj -scheme SenseFS -configuration Debug build

# Release build
xcodebuild -project SenseFS.xcodeproj -scheme SenseFS -configuration Release build
```

### Testing

```bash
# Run tests
xcodebuild test -project SenseFS.xcodeproj -scheme SenseFS
```

## Dependencies

Managed via Swift Package Manager (Package.swift):

| Package | Version | License | Purpose |
|---------|---------|---------|---------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 0.9.0+ | MIT | Extract Office documents (DOCX/XLSX/PPTX) |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | 0.1.0+ | Apache 2.0 | Tokenizer and Hugging Face Hub integration |

**Transitive Dependencies** (included with swift-transformers):
- Jinja (MIT) - Template engine for tokenizers
- Swift Argument Parser (Apache 2.0) - CLI argument parsing
- Swift Collections (Apache 2.0) - Advanced data structures

All licenses are viewable in the **Licenses tab** within the app.

## Troubleshooting

### Model Not Loading

**Symptom**: "Model not loaded" error in Settings

**Solution**:
1. Ensure `multilingual-e5-small-fp16.mlpackage` is in the app bundle
2. Check console logs for detailed error messages
3. Verify model file is not corrupted (should be ~225 MB)

### Slow Indexing

**Symptom**: Indexing takes very long

**Solutions**:
- Enable "Skip Code Files" in Settings
- Reduce max file size limit
- Index smaller folders incrementally
- Check if large PDFs or Office documents are causing delays

### High Memory Usage

**Symptom**: App uses excessive RAM

**Solutions**:
- Reduce database size limit in Settings
- Clear index and reindex with smaller file set
- Restart app to free cached data

## Features

### ✅ What's Included
- ✅ Semantic search with 384-dim embeddings
- ✅ 4 main tabs: Search, Index, Licenses, Settings
- ✅ Multi-format support (Text, PDF, Office, Images with OCR)
- ✅ 12+ language auto-detection
- ✅ Change detection and incremental reindexing
- ✅ Auto-skip patterns (20+ directories)
- ✅ Configurable size limits
- ✅ Error reporting and progress tracking
- ✅ File grouping with chunk counts
- ✅ Color-coded relevance scores
- ✅ Neural Engine acceleration
- ✅ SQLite vector database with WAL mode
- ✅ Full dependency attribution

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Guidelines

1. Follow Swift API Design Guidelines
2. Use SwiftLint for code style
3. Add tests for new features
4. Update documentation

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **Hugging Face** for the multilingual-e5-small model
- **Apple** for CoreML and Metal Performance Shaders
- **swift-transformers** contributors

## Support

- 📧 Email: support@example.com
- 🐛 Issues: [GitHub Issues](../../issues)
- 💬 Discussions: [GitHub Discussions](../../discussions)

## Citation

If you use SenseFS in your research, please cite:

```bibtex
@software{sensefs2024,
  title = {SenseFS: Semantic File Search for macOS},
  author = {Your Name},
  year = {2024},
  url = {https://github.com/yourusername/sensefs}
}
```

---

**Built with ❤️ using Swift and CoreML**
