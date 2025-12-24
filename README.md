# SenseFS - Semantic File Search for macOS

> Intelligent semantic search across your files using CoreML embeddings

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg)]()
[![Swift](https://img.shields.io/badge/swift-5.0-orange.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()

## Overview

SenseFS is a native macOS application that brings powerful semantic search to your local files. Unlike traditional keyword search, SenseFS understands the *meaning* of your queries and finds relevant content even when exact keywords don't match.

### Key Features

- 🔍 **Semantic Search** - Find files by meaning, not just keywords
- 🌍 **100+ Languages** - Multilingual support using multilingual-e5-small model
- 📄 **Multiple Formats** - Text, PDF, Office documents (docx/xlsx/pptx), and images (OCR)
- 🚀 **Fast & Local** - CoreML-optimized inference, 100% offline
- 🔒 **Privacy First** - All processing happens locally, no data sent to cloud
- ✨ **Smart Features** - Auto-skip patterns, incremental indexing, change detection
- 🎨 **Native UI** - Modern SwiftUI interface with drag-and-drop support
- 📜 **Open Source** - MIT licensed with full dependency attribution

## Screenshots

> Beautiful, native macOS interface with semantic search capabilities

## Quick Start

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later (for building from source)
- ~500 MB disk space (for app + models)

### Installation

#### Option 1: Download Release (Recommended)

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the `.dmg` file
3. Drag `SenseFS.app` to your Applications folder
4. Launch SenseFS

#### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/sensefs.git
cd sensefs/sensefs-mac

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

- **UI Framework**: SwiftUI
- **ML Framework**: CoreML + Neural Engine
- **Embedding Model**: multilingual-e5-small (FP16, 384 dimensions)
- **Database**: SQLite3 with WAL mode
- **Concurrency**: Swift actors for thread-safety
- **Text Extraction**: PDFKit, Vision, ZIPFoundation

## Performance

| Operation | Time | Notes |
|-----------|------|-------|
| App Launch | < 1s | CPU-only model for instant startup |
| Model Load (Optimized) | ~3-5s | Background Neural Engine optimization |
| Index 100 files | ~30-60s | Depends on file sizes |
| Search Query | < 100ms | For 10,000 chunks |
| Embedding Generation | ~50ms | Per chunk |

## Security & Privacy

- ✅ **App Sandbox** enabled
- ✅ **User-selected file access** only
- ✅ **Path traversal protection**
- ✅ **SQL injection prevention**
- ✅ **100% offline** - no network requests
- ✅ **No telemetry** - your data never leaves your Mac

## Configuration

### Settings

- **Skip Code Files**: Exclude programming files from indexing (default: ON)
- **Skip Images**: Exclude image files from OCR indexing (default: OFF)
- **Max File Size**: Skip files larger than limit (default: 10 MB)
- **Max Database Size**: Total indexed content limit (default: 1 GB)

### Auto-Skip Patterns (Zero Configuration)

SenseFS automatically skips common files and directories:

**Files**: README, LICENSE, CHANGELOG, CONTRIBUTING, AUTHORS
**Directories**: node_modules, .git, .venv, __pycache__, build, dist, .next, and 14 more

**Performance**: 50x faster indexing on typical projects!

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

Managed via Swift Package Manager:

- [swift-transformers](https://github.com/huggingface/swift-transformers) - Tokenizer support
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) - Office document parsing

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

## Roadmap

### Current Version
- [x] Semantic search with CoreML
- [x] Auto-skip patterns
- [x] Multi-format support
- [x] License attribution tab

### Possible Enhancements
- [ ] Boolean search operators (AND, OR, NOT)
- [ ] Custom skip patterns
- [ ] Multi-folder indexing
- [ ] Spotlight integration
- [ ] Export search results

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
