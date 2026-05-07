# Changelog

All notable changes to the Video Encoding Queue System.

---

## [2026-01-24] - Complete Queue Management Overhaul

### Added

#### Smart Duplicate Prevention
- **`add_to_queue.ps1`**: Intelligent duplicate detection με parent/child awareness
  - **Exact path check**: Αποτρέπει duplicate entries
  - **Parent folder detection**: Όταν προσθέτεις file, ελέγχει αν το parent folder υπάρχει ήδη στο queue
  - **Child file cleanup**: Όταν προσθέτεις folder, αφαιρεί αυτόματα individual files που περιέχονται σε αυτόν
  - **User feedback**: Εμφανίζει μηνύματα για removed files και λόγο rejection
  - Πλήρης προστασία από duplicate encoding

#### Advanced Queue Manager
- **`run_queue.ps1`**: Complete rewrite με modern UI και advanced features
  
  **Core Features:**
  - **Persistent Menu Loop**: Εμφανίζεται πάντα, ακόμα και με άδειο queue
  - **Current Folder Detection**: Δέχεται folder path από registry (`%V`)
  - **Live Updates**: Reload queue από disk σε real-time
  - **Smart Navigation**: ESC key σε κάθε menu level
  
  **Queue Operations:**
  - **NUMPAD +**: Add current folder (με duplicate protection)
  - **NUMPAD -**: Remove current folder (toggle functionality)
  - **R**: Manual refresh από disk
  - **C**: Clear queue (χωρίς exit)
  - **ESC**: Exit χωρίς changes
  - **Status Display**: "(IN QUEUE)" / "(not in queue)" indicator
  
  **Edit Mode (E key):**
  - Multi-digit input support (χωρίς 9-item limit)
  - Type number + ENTER για removal
  - Backspace support για corrections
  - Range validation με user-friendly messages
  - ESC για return σε main menu
  - Auto-refresh μετά από κάθε deletion
  
  **Visual Enhancements:**
  - Full path display: Basename σε Cyan, parent path σε DarkGray
  - Color-coded status messages
  - Clear visual hierarchy
  - Responsive queue updates

#### Registry Improvements
- **`run_encode_queue.reg`**: Enhanced context menu integration
  - Folder background: `%V` parameter για current folder detection
  - Desktop background: `%V` (unified behavior)
  - Proper path normalization

#### Windows Integration Fix
- **Context Menu for >15 Files**: Registry tweak για `MultipleInvokePromptMinimum`
  - Default Windows limit: 15 files
  - New limit: 100 files (configurable)
  - Separate registry file για easy enable/disable
  - Minimal performance impact

### Changed

#### Behavior Changes
- **C Key**: Clear queue αλλά μένει στο menu (πριν: clear + exit)
- **ESC Key**: Μοναδικός τρόπος exit (preserves queue)
- **Edit Mode**: Multi-digit input αντί για single-key (unlimited items)
- **Duplicate Handling**: Smart detection αντί για simple path check

#### UI/UX Improvements
- Full paths με color coding
- Dedicated status messages για κάθε action
- Better error messages με context
- Seamless workflow (λιγότερα exits/restarts)

### Fixed

- ✅ Duplicate encoding όταν files + parent folder στο queue
- ✅ Context menu δεν εμφανιζόταν με >15 selected files
- ✅ ESC δεν λειτουργούσε στο Edit Mode
- ✅ Δεν μπορούσες να edit queue με >9 items
- ✅ C key έκλεινε το window (τώρα μόνο clears)

### Technical Details

**Files Modified:**
- `add_to_queue.ps1` - Smart duplicate detection (54 → 108 lines)
- `run_queue.ps1` - Complete rewrite (143 → 390 lines)
- `run_encode_queue.reg` - Current folder parameter support
- `CHANGELOG.md` - Project documentation

**Architecture Changes:**
- Menu loop architecture για persistent UI
- Flag-based state management για nested menus
- Input buffer system για multi-digit support
- Path relationship detection για smart duplicates

**New Features Summary:**
1. 🔸 Smart duplicate prevention (parent/child aware)
2. 🔸 Live queue updates με manual refresh (R key)
3. 🔸 Toggle current folder με NUMPAD +/-
4. 🔸 Advanced edit mode με unlimited items (E key, multi-digit)
5. 🔸 Full path display με color coding
6. 🔸 Dual exit options (ESC vs C key)
7. 🔸 Empty queue support με add functionality
8. 🔸 >15 files context menu fix

---

## [Previous] - Initial Setup

### Features
- Basic queue system με `queue.txt`
- Context menu integration για files και folders
- Batch encoding με shared settings
- Support για: `.mp4`, `.mkv`, `.avi`, `.mov`, `.wmv`, `.mpg`, `.mpeg`, `.vob`
- QTGMC deinterlacing για MPEG files
- H.264 NVENC encoding με QP control
- Resize options
- GOP control
- Legacy DVD detection και conversion
