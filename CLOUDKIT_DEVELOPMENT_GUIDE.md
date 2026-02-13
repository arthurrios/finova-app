# Finova v1.6.0 — CloudKit Sync & Budget Sharing Development Guide

## Overview

This guide covers the full implementation of **iCloud data sync** and **collaborative budget sharing** for Finova. It is organized into **short-term build phases** designed so that UI changes are visible on-screen after each sub-phase, while logic-heavy phases can be longer.

---

## UI Pattern Catalog — Mandatory Reference for All New Screens

Every new view, component, and cell in this guide **must** follow these exact patterns.
All values below are extracted from the existing codebase. Do not deviate.

### Foundations

**Colors** (`Colors.*`):
| Token | Hex | Usage |
|-------|-----|-------|
| `gray100` | `#F9FBF9` | Card/container backgrounds, header backgrounds, light surfaces |
| `gray200` | `#EFF0EF` | **View backgrounds** (every screen root), input backgrounds, unselected button bg |
| `gray300` | `#E5E6E5` | Borders (1px), separators, input default border, badge count bg |
| `gray400` | `#A1A2A1` | Placeholder text, chevron icons, disabled text, inactive icons |
| `gray500` | `#676767` | Secondary text (subtitles, descriptions, section headers), icon default tint |
| `gray600` | `#494A49` | Setting row icons, tertiary labels, section detail text |
| `gray700` | `#0F0F0F` | **Primary text** (titles, values, labels), back button tint (iOS 26+) |
| `mainMagenta` | `#DA4BDD` | Primary brand color — buttons, active states, selected borders, switch tint, badges |
| `mainRed` | `#D93A4A` | Expense color, destructive actions, error states, delete labels |
| `mainGreen` | `#1FA342` | Income color, success states, synced indicator |
| `warningAmber` | `#F59E0B` | Warning banners, near-limit status |
| `lowMagenta` | `rgba(220,84,222,0.05)` | Outlined button background, badge/chip tint backgrounds |
| `lightGreen` | `rgba(31,163,66,0.05)` | Income button normal state bg |
| `lightRed` | `rgba(217,58,74,0.05)` | Expense button normal state bg |
| `lowAmber` | `rgba(245,158,11,0.05)` | Warning banner background |

**Fonts** (`Fonts.*` — all Lato family, scaled with `UIFontMetrics`):
| Token | Size | Weight | Casing | Usage |
|-------|------|--------|--------|-------|
| `titleLG` | 28 | `.black` | none | Hero numbers (balance) |
| `titleMD` | 16 | `.bold` | none | Money values in cells, card values, currency prefix |
| `titleSM` | 14 | `.bold` | `.uppercase` | **Headers**, setting row labels, cell primary text. Uses `label.fontStyle = Fonts.titleSM` + `applyStyle()` |
| `titleXS` | 12 | `.bold` | `.uppercase` | **Modal titles**, card header titles |
| `title2XS` | 10 | `.bold` | `.uppercase` | Card header section labels (e.g., "TRANSACTIONS") |
| `textSM` | 14 | `.regular` | none | Body text, subtitles, descriptions |
| `textSMBold` | 14 | `.bold` | none | Cell titles (transaction name), payment method titles |
| `textXS` | 12 | `.regular` | none | Date labels, hints, badge text, section headers in settings |
| `input` | 16 | `.regular` | `lineHeight: 24` | Text field content, segmented control text |
| `buttonMD` | 16 | `.bold` | `lineHeight: 24` | Primary button label |
| `buttonSM` | 14 | `.bold` | `lineHeight: 20` | Transaction type selector label |

**Label styling pattern** — For `titleSM`, `titleXS`, `title2XS` (fonts with text casing/line height):
```swift
label.fontStyle = Fonts.titleSM   // Sets associated object
label.text = "My Text"
label.applyStyle()                // Applies attributedText with casing + paragraphStyle
label.textColor = Colors.gray700  // Set AFTER applyStyle
```
For other fonts (no casing/lineHeight), use directly:
```swift
label.font = Fonts.textSM.font
label.textColor = Colors.gray500
```

**Spacing** (`Metrics.*` — 4px base grid):
| Token | Value | Common Usage |
|-------|-------|-------------|
| `spacing1` | 4 | Tiny gaps (between label + sublabel in stack) |
| `spacing2` | 8 | Icon-to-text in small components, badge padding |
| `spacing3` | 12 | Icon-to-label in setting rows, input spacing, between stacked inputs |
| `spacing4` | 16 | Section padding (leading/trailing), content margins, between section elements |
| `spacing5` | 20 | Card internal padding (top/leading/bottom/trailing), header horizontal margins |
| `spacing6` | 24 | Header bottom padding |
| `spacing7` | 28 | Stack spacing in modals between major sections |
| `spacing8` | 32 | Modal horizontal margins, large component height |
| `spacing10` | 40 | Modal top padding |

**Corner Radii** (`CornerRadius.*`):
| Token | Value | Usage |
|-------|-------|-------|
| `small` | 4 | Small badges, recurring indicator |
| `medium` | 6 | Warning banners, icon containers in cells |
| `large` | 8 | **Setting rows**, buttons, inputs, card containers, cards |
| `extraLarge` | 12 | **Cards with CardHeader** (top corners on header, bottom corners on content), credit card cells |
| `bottomSheet` | 20 | Modal bottom sheets |

**Component Sizes** (`Metrics.*`):
| Token | Value | Usage |
|-------|-------|-------|
| `buttonHeight` | 48 | All buttons (Button component) |
| `inputHeight` | 48 | All inputs (Input component), segmented controls, payment method options |
| `profileImageSize` | 40 | Avatar size |
| `profileIconSize` | 20 | Avatar fallback icon size |
| `logoutButtonSize` | 24 | Header action buttons (settings, notifications) |
| `backButtonSize` | 24 | Back button icon size |
| `inputIconSize` | 20 | Icon inside inputs |
| `cardHeaderHeight` | 44 | CardHeader component height |
| `addButtonSize` | 48 | FAB (floating action button) |
| `headerHeight` | 136/116 | Dynamic (136 with Dynamic Island, 116 without) |
| `tableEmptyViewHeight` | 68 | Empty state containers inside tables |

### Screen-Level Patterns

**Every screen root view:**
```swift
backgroundColor = Colors.gray200
```

**Header pattern** (used by: Settings, TransactionDetails, Budgets, CreditCards, StatementDetails, BudgetAllocationDetails, NotificationHistory, NotificationSettings — all non-Dashboard detail screens):
```swift
// Container
let headerContainerView: UIView  // backgroundColor = Colors.gray100
// Height: Metrics.headerHeight (for full headers) or Metrics.headerHeight - 12 (for compact headers like Settings)

// Items view
let headerItemsView: UIView  // directionalLayoutMargins:
// top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5, trailing: Metrics.spacing5

// Back button (glass container pattern for iOS 26+)
let backButtonGlassContainer: UIView  // 36x36, cornerRadius: 18
let backButton: UIButton  // chevronLeft image, tint: Colors.gray700 (iOS 26+) / Colors.gray500 (older)
// Glass effect: UIGlassEffect(style: .clear), isInteractive = true

// Title
let headerTitleLabel: UILabel  // fontStyle = Fonts.titleSM, textColor = Colors.gray700

// Optional subtitle
let headerSubtitleLabel: UILabel  // font = Fonts.textSM.font, textColor = Colors.gray500

// Layout: backButton.leading → title.leading (spacing4 gap), both centerY to backButton
```

**Dashboard header** (unique — no back button, has avatar instead):
```swift
// Same gray100 container, Metrics.headerHeight
// Avatar (40x40), welcomeTitle (Fonts.titleSM, gray700), welcomeSubtitle (Fonts.textSM, gray500)
// Settings button + notification button (24x24, tint gray500) trailing
// Notification badge: 18x18, bg mainMagenta, border 2px gray100, font systemFont(10, .bold) white
```

### Card Patterns

**Card with CardHeader** (used for transactions table, budget table, info sections):
```
┌─────────────────────────────┐ ← CardHeader: bg gray100, height 44,
│  SECTION TITLE          (3) │   cornerRadius extraLarge (top corners only)
│                             │   border: 1px gray300 (top + sides, NOT bottom)
├─────────────────────────────┤   title: Fonts.title2XS, gray500, UPPERCASE
│                             │   badge: bg gray300, font titleXS, gray600, pill shape
│  Card content               │
│                             │ ← Content: bg gray100, padding spacing5 all sides,
│                             │   border: 1px gray300 (sides + bottom)
│                             │   cornerRadius extraLarge (bottom corners only)
│                             │   maskedCorners: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
└─────────────────────────────┘
```

### Setting Row Pattern

Used by: Settings, NotificationSettings. **Every new settings-like row must use this pattern.**

```swift
// Factory method (from SettingsView):
private static func createSettingContainer() -> UIView {
    let container = UIView()
    container.backgroundColor = Colors.gray100
    container.layer.cornerRadius = CornerRadius.large  // 8
    container.translatesAutoresizingMaskIntoConstraints = false
    container.heightAnchor.constraint(equalToConstant: 56).isActive = true
    return container
}

private static func createIconView(imageName: String, tintColor: UIColor = Colors.gray600) -> UIImageView {
    // image: UIImage(systemName: imageName), 20x20, tint: Colors.gray600
}

private static func createSettingLabel(text: String) -> UILabel {
    // font: Fonts.titleSM.font (note: .font, not fontStyle — no uppercase in settings labels)
    // textColor: Colors.gray700
}

private static func createDetailLabel(text: String) -> UILabel {
    // font: Fonts.textSM.font, textColor: Colors.gray500, textAlignment: .right
}

private static func createChevronView() -> UIImageView {
    // systemName "chevron.right", 12x12, tint: Colors.gray400
}
```

Layout:
```
│ [icon 20x20]  spacing3  [label]  ────────  [detail]  spacing2  [chevron 12x12] │
│   gray600      12dp      gray700            gray500    8dp        gray400        │
│  spacing4                                                         spacing4       │
│   16dp                                                            16dp           │
```

For rows with a switch instead of chevron:
```
│ [icon 20x20]  spacing3  [label]  ────────────────────  [UISwitch onTint:mainMagenta] │
```

### Section Header Pattern (in scrollable settings-style views)

```swift
private static func createSectionHeader(title: String) -> UIView {
    // label: title.uppercased(), font: Fonts.textXS.font, textColor: Colors.gray500
    // height: 24, padding: top spacing3, leading spacing2
}
```

### Table Cell Pattern

**Transaction-type cells** (height ~67):
```
│ [iconContainer 32x32]  spacing3  [title textSMBold gray700]    [amount titleMD gray700] │
│   bg gray200                     [date textXS gray500]         [symbol textXS gray700]  │
│   border 1px gray300                                                                     │
│   cornerRadius medium (6)                                                                │
│   icon tint: category.color                                                              │
│                                                                                          │
│ separator: 1px gray300 full width ───────────────────────────────────────────────────── │
```

### Modal / Bottom Sheet Pattern

Used by: AddTransaction, AdjustBalance, AddAllocation.

```swift
// Presentation
modalPresentationStyle = .pageSheet
sheetPresentationController.detents = [.medium(), .large()]
sheetPresentationController.prefersGrabberHandle = true
sheetPresentationController.preferredCornerRadius = CornerRadius.bottomSheet // 20

// View
backgroundColor = Colors.gray100  // ← NOTE: modals use gray100, not gray200

// Content stack
contentStackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
    top: Metrics.spacing10,     // 40 — top padding
    leading: Metrics.spacing8,  // 32 — horizontal padding
    bottom: Metrics.spacing4,   // 16 — bottom padding
    trailing: Metrics.spacing8  // 32 — horizontal padding
)

// Section spacing between major groups: Metrics.spacing7 (28)
// Input spacing within groups: Metrics.spacing3 (12)

// Modal title
headerTitleLabel.fontStyle = Fonts.titleXS  // 12pt bold UPPERCASE
headerTitleLabel.textColor = Colors.gray700

// Close button (top-right)
closeIconButton.setImage(UIImage(systemName: "xmark"), for: .normal)
closeIconButton.tintColor = Colors.gray500
// 24x24

// Section labels inside modals
sectionLabel.font = Fonts.textSM.font  // 14pt regular
sectionLabel.textColor = Colors.gray400

// Hint labels
hintLabel.font = Fonts.textXS.font  // 12pt regular
hintLabel.textColor = Colors.gray400

// Separator before save button
separator.backgroundColor = Colors.gray300
separator.heightAnchor.constraint(equalToConstant: 1)

// Save button: Button(variant: .base, label: "Save") — full width
```

### Button Component Variants

```swift
// PRIMARY (.base)
backgroundColor = Colors.mainMagenta
titleColor = Colors.gray100
cornerRadius = 8 (hardcoded, not CornerRadius token)
height = Metrics.buttonHeight (48)
font = Fonts.buttonMD

// SECONDARY (.outlined)
backgroundColor = Colors.lowMagenta
titleColor = Colors.mainMagenta
border = 1px Colors.mainMagenta

// DISABLED (.outlinedDisabled)
backgroundColor = Colors.gray600
titleColor = Colors.gray400
border = 1px Colors.gray400
opacity = 0.5
```

### Input Component Defaults

```swift
backgroundColor = Colors.gray200
border = 1px Colors.gray300
cornerRadius = CornerRadius.large (8)
height = Metrics.inputHeight (48)
font = Fonts.input (16pt, lineHeight 24)
placeholder color = Colors.gray400
icon tint: Colors.gray600 (default), Colors.mainMagenta (focused), Colors.mainRed (error)
border color: Colors.gray300 (default), Colors.mainMagenta (focused), Colors.mainRed (error)
```

### Segmented Control Pattern

```swift
backgroundColor = Colors.gray200
selectedSegmentTintColor = Colors.mainMagenta
border = 1px Colors.gray300
cornerRadius = CornerRadius.large (8)
height = Metrics.inputHeight (48)
normal text: [.foregroundColor: Colors.gray700, .font: Fonts.input.font]
selected text: [.foregroundColor: Colors.gray100, .font: Fonts.input.font]
```

### Radio Option Pattern (PaymentMethodOptionView)

```swift
backgroundColor = Colors.gray200
border = 1px Colors.gray300 (default), 1px Colors.mainMagenta (selected)
cornerRadius = CornerRadius.large (8)
height = Metrics.inputHeight (48)
radio circle: 20x20, border 2px gray400 (default) / mainMagenta (selected)
radio fill: 10x10, bg mainMagenta, hidden when unselected
title: Fonts.textSMBold, Colors.gray700
subtitle: Fonts.textXS, Colors.gray500
```

### Badge / Chip Patterns

**Count badge** (e.g., notification badge, transaction count):
```swift
backgroundColor = Colors.gray300  // or mainMagenta for notification badge
font = Fonts.titleXS (12pt bold UPPERCASE)
textColor = Colors.gray600
height = 18
cornerRadius = height / 2 (pill shape)
padding = spacing2 horizontal
```

**Status badge** (e.g., recurring indicator, role badge):
```swift
backgroundColor = Colors.lowMagenta  // or semantic color with 0.15 alpha
border = 1px Colors.mainMagenta
cornerRadius = CornerRadius.small (4)
padding = spacing1 vertical, spacing2 horizontal
icon = 14x14, tint Colors.mainMagenta
font = Fonts.textXS, textColor = Colors.mainMagenta
```

**Warning banner**:
```swift
backgroundColor = Colors.lowAmber
cornerRadius = CornerRadius.medium (6)
padding = spacing3 vertical, spacing4 horizontal
icon = 20x20, tint Colors.warningAmber
font = Fonts.textSM, textColor = Colors.warningAmber
```

### Information Row Pattern (detail screens)

Used for key-value pairs in transaction/statement/allocation details:
```swift
// Horizontal stack, distribution .equalSpacing
titleLabel.font = Fonts.textSM.font       // 14pt regular
titleLabel.textColor = Colors.gray500      // or gray600
valueLabel.font = Fonts.textSMBold.font   // 14pt bold
valueLabel.textColor = Colors.gray700
valueLabel.textAlignment = .right
// Row height: ~24 (determined by font height)
// Minimum spacing between title and value: Metrics.spacing3
```

### Footer Pattern (screens with bottom action buttons)

```swift
// Container
footerView.backgroundColor = Colors.gray100
// Top separator: 1px Colors.gray300
// Padding: spacing4 all sides
// Bottom: respects safe area (safeAreaLayoutGuide.bottomAnchor)
// Button: full width Button(variant: .base, label: "...")
```

### Empty State Pattern

```swift
// Icon: UIImage(systemName: "..."), tint Colors.gray400, 48x48 (large) or 24x24 (inline)
// Title: fontStyle = Fonts.titleSM, textColor = Colors.gray500 (or gray600), centered
// Subtitle: font = Fonts.textSM.font, textColor = Colors.gray400, centered, numberOfLines = 0
// For inline empty states (inside cards): height = Metrics.tableEmptyViewHeight (68)
```

### iOS 26+ Glass Effect Pattern

Applied to back buttons and FAB (floating action button):
```swift
if #available(iOS 26.0, *) {
    let glassEffect = UIGlassEffect(style: .clear)
    glassEffect.isInteractive = true
    let glassView = UIVisualEffectView(effect: glassEffect)
    // Pin glassView to container edges
    container.layer.cornerRadius = containerHeight / 2  // pill shape for FAB, 18 for back button
    container.clipsToBounds = true
}
```

### Swipe-to-Delete Pattern (table cells)

```swift
// Trailing swipe action
action.backgroundColor = Colors.mainMagenta  // not red — uses brand color
action.image = UIImage(systemName: "trash.fill")  // white icon
```

### Credit Card Cell Pattern

```swift
// Container: bg gray100, cornerRadius extraLarge (12)
// Card preview: 100dp height, gradient background (CardColor.startColor → endColor)
//   cornerRadius extraLarge, all 4 corners
//   Card name: Fonts.titleSM white, top-left (spacing4 inset)
//   Last four: Fonts.textSM white 80% opacity, bottom-left
//   Brand: Fonts.textXS white 70% opacity, bottom-right
//   Default badge: bg white 25% opacity, cornerRadius spacing4 (16)
// Info label below card: Fonts.textXS, gray500
```

### Core Features
1. **CloudKit Sync** — Sync all user data (transactions, budgets, credit cards) across devices via iCloud Private Database
2. **Budget Sharing Groups** — Create groups to share financial management with family/partners
3. **Permissions System** — Owner controls what members can do (create/edit/delete transactions, edit budgets, etc.)
4. **Push Notifications** — Notify all group members of actions taken by any member
5. **Last Active Indicator** — Lightweight "last seen" status on dashboard (deferred real-time presence)

### Architecture Principles
- **Offline-First**: Local SQLite remains the source of truth. CloudKit syncs in the background.
- **Incremental Sync**: Use `CKServerChangeToken` for efficient delta updates.
- **Conflict Resolution**: Last-writer-wins with user prompt for critical conflicts.
- **Privacy**: Users explicitly opt-in to sharing. Private data stays in CK Private Database, shared data in CK Shared Database.

---

## Shared Data Model — What Gets Shared and Why

When a group shares finances, there is a **dependency chain** that must be respected.
Sharing only transactions without their linked credit cards, statements, or budgets
would produce incorrect totals and broken UX.

### The Credit Card Dependency Chain

```
Shared CreditCard (owner opts-in to share a card with the group)
  └── CreditCardStatements (auto-follow: statement total MUST reflect all members' charges)
        └── Transactions linked via creditCardId / statementId
              ├── Recurring Transaction Templates (parentTransactionId)
              └── Installment Templates + Instances
```

If Member B charges $50 to a shared card but the statement only reflects Member A's
charges, the statement total is wrong and bill payment coordination breaks.

### Full Shared Data Matrix

| Data | Shared? | Sharing Mechanism | Notes |
|------|---------|-------------------|-------|
| **Transactions** | Yes | `shared_group_id` column | Core shared data. Members contribute expenses/income to the group. |
| **Credit Cards** | Yes (opt-in per card) | `shared_group_id` column | Owner shares specific cards. Members see card details based on `canViewCreditCards` permission. |
| **Credit Card Statements** | Yes (follows card) | Implicit via `creditCardId` → shared card | Statement `totalAmount` must be recalculated from ALL group members' transactions on that card. |
| **Budgets** (monthly amount) | Yes | `shared_group_id` column | The group shares one budget. Everyone's spending counts against it. |
| **Budget Allocations** | Yes (follows budget) | Implicit via shared budget's `monthDate` | Category limits apply to the combined group spending, not per-member. |
| **Recurring Tx Templates** | Yes (if on shared card/budget) | `shared_group_id` column | Instances must generate and be visible to all group members. |
| **Installment Templates** | Yes (same logic) | `shared_group_id` column | A 12x installment on a shared card must appear for everyone. |
| **Balance Adjustments** | Yes | Logged as group activity | If someone adjusts the group balance, everyone must see the updated figure. |
| **Currency** | Group-level setting | `BudgetGroup.currency` field | If members have different personal currencies, group must enforce a single currency for correct totals. |

### What is NOT Shared

| Data | Why |
|------|-----|
| Personal transactions (no `shared_group_id`) | Private by default |
| Personal credit cards (not shared with group) | Only cards explicitly shared |
| Biometric / auth settings | Per-device, per-user |
| Notification preferences | Personal choice |
| User profile / login credentials | Per-account |

### Data Isolation — Personal vs Group Context

**The core rule:** `shared_group_id = NULL` means personal. Everything else is
filtered by the group ID. Existing data is NEVER touched when joining a group.

```
User's SQLite Database
├── Transactions
│   ├── shared_group_id = NULL    → Personal (all pre-v1.6.0 data lives here)
│   ├── shared_group_id = "grp-A" → Group A data
│   └── shared_group_id = "grp-B" → Group B data (user can be in multiple groups)
├── Budgets
│   ├── shared_group_id = NULL    → Personal budget
│   └── shared_group_id = "grp-A" → Group A's shared budget
├── CreditCards
│   ├── shared_group_id = NULL    → Personal cards (only you see them)
│   └── shared_group_id = "grp-A" → Shared with Group A
└── ... same pattern for all tables
```

**Migration safety:** The `ALTER TABLE ... ADD COLUMN shared_group_id TEXT` migration
sets the default to `NULL`. This means every existing row stays personal automatically.
No data moves, no data lost, zero user action required.

**Scenario: User with existing data joins a group**
1. User has 200 personal transactions, 3 personal credit cards, budget history
2. User accepts a group invitation
3. All 200 transactions remain personal (`shared_group_id = NULL`) — untouched
4. The group's shared data syncs DOWN to the user's device via CloudKit
5. User switches to group context in dashboard → sees only group data
6. User switches back to personal → sees all their original 200 transactions

**Scenario: User wants to move a personal transaction to the group**
This is an explicit action — the user taps a transaction, and from the detail screen
chooses "Move to Group". This updates `shared_group_id` from `NULL` to the group ID
and pushes the change to CloudKit. The reverse ("Move to Personal") removes the
`shared_group_id`. This is essentially a "reassign" operation.

**Scenario: User is in multiple groups**
The context switcher shows: Personal | Group A | Group B
Each context is a complete filter — dashboard, budgets, transactions, cards all
filter by that `shared_group_id`. A user can be in up to N groups simultaneously.

**Scenario: User leaves a group**
- User's locally cached group data is soft-deleted
- Transactions they personally created in the group remain in the group for other members
- Their personal data (`shared_group_id = NULL`) is completely unaffected

### Impact on Existing Services

**`TransactionLedgerService.calculateMonthlyData()`** — Currently fetches only the current
user's transactions. In group context, it must aggregate ALL group members' transactions
that have a matching `shared_group_id`. The `fetchAllTransactionsIncludingStatements()`
method needs a group-aware variant.

**`CreditCardService.generateStatementTransactions()`** — Currently filters by `userId`.
For shared cards, it must pull transactions from ALL group members linked to that card's
`creditCardId`. The statement `totalAmount` must reflect the combined charges.

**`RecurringTransactionManager`** — Recurring templates with a `shared_group_id` must
generate instances that are also marked with the same `shared_group_id`, so they appear
in every group member's view.

**`BudgetAllocationService`** — `usedAmount` for each allocation must sum transactions
from ALL group members (filtered by `shared_group_id` + category), not just the current user.

---

## File Structure (New Files)

```
Finova/Sources/
├── Core/
│   ├── CloudKit/
│   │   ├── CloudKitManager.swift              # CKContainer setup, account status, permissions
│   │   ├── SyncEngine.swift                   # Bidirectional sync orchestrator
│   │   ├── SyncStateManager.swift             # Track sync tokens, last sync dates per record type
│   │   ├── ConflictResolver.swift             # Merge conflict strategies
│   │   ├── CloudKitErrorHandler.swift         # Retry logic, quota, network errors
│   │   └── Models/
│   │       ├── CKRecordConvertible.swift      # Protocol: local model <-> CKRecord
│   │       ├── CKTransactionAdapter.swift     # Transaction <-> CKRecord
│   │       ├── CKBudgetAdapter.swift          # Budget <-> CKRecord
│   │       ├── CKBudgetAllocationAdapter.swift # BudgetAllocation <-> CKRecord
│   │       ├── CKCreditCardAdapter.swift      # CreditCard <-> CKRecord
│   │       ├── CKCreditCardStatementAdapter.swift # Statement <-> CKRecord
│   │       └── CKBudgetGroupAdapter.swift     # BudgetGroup <-> CKRecord (shared zone)
│   ├── Models/
│   │   ├── BudgetGroup.swift                  # Group model (id, name, owner, members, permissions)
│   │   ├── GroupMember.swift                  # Member model (userId, name, email, role, permissions, lastActive)
│   │   └── GroupPermission.swift              # Permission enum/flags
│   ├── Services/
│   │   ├── BudgetGroupService.swift           # Group CRUD, invitation logic
│   │   └── GroupNotificationService.swift     # Push notification dispatch for group events
│   ├── Repositories/
│   │   └── BudgetGroupRepository.swift        # Local SQLite storage for groups
│   └── Utils/
│       └── GroupNotificationManager.swift     # Handle incoming group push notifications
├── Scenes/
│   ├── BudgetGroups/
│   │   ├── BudgetGroupsViewController.swift
│   │   ├── BudgetGroupsViewModel.swift
│   │   ├── BudgetGroupsView.swift
│   │   ├── BudgetGroupsViewDelegate.swift
│   │   ├── BudgetGroupsFlowDelegate.swift
│   │   └── Views/
│   │       ├── BudgetGroupCell.swift
│   │       └── EmptyGroupsView.swift
│   ├── GroupDetails/
│   │   ├── GroupDetailsViewController.swift
│   │   ├── GroupDetailsViewModel.swift
│   │   ├── GroupDetailsView.swift
│   │   ├── GroupDetailsViewDelegate.swift
│   │   ├── GroupDetailsFlowDelegate.swift
│   │   └── Views/
│   │       ├── GroupMemberCell.swift
│   │       ├── GroupMemberAvatarStack.swift
│   │       └── GroupActivityCell.swift
│   ├── InviteMember/
│   │   ├── InviteMemberViewController.swift
│   │   ├── InviteMemberViewModel.swift
│   │   ├── InviteMemberView.swift
│   │   ├── InviteMemberViewDelegate.swift
│   │   └── InviteMemberFlowDelegate.swift
│   ├── MemberPermissions/
│   │   ├── MemberPermissionsViewController.swift
│   │   ├── MemberPermissionsViewModel.swift
│   │   ├── MemberPermissionsView.swift
│   │   ├── MemberPermissionsViewDelegate.swift
│   │   └── MemberPermissionsFlowDelegate.swift
│   └── GroupInvitation/
│       ├── GroupInvitationViewController.swift  # Shown when user receives invite
│       ├── GroupInvitationViewModel.swift
│       ├── GroupInvitationView.swift
│       └── GroupInvitationFlowDelegate.swift
└── Core/
    ├── Components/
    │   ├── GroupAvatarStack.swift              # Overlapping circular avatars component
    │   ├── PermissionToggleRow.swift           # Reusable permission toggle row
    │   ├── SyncStatusIndicator.swift           # Cloud sync status icon (syncing/synced/error)
    │   └── MemberBadge.swift                   # Small badge showing member role (owner/member)
    └── Extensions/
        └── CKRecord+Ext.swift                 # Convenience accessors for CKRecord fields
```

---

## Database Schema Changes

### New SQLite Tables

```sql
-- Budget Groups (local cache of CloudKit shared data)
CREATE TABLE IF NOT EXISTS BudgetGroups (
    id                TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    owner_id          TEXT NOT NULL,
    owner_name        TEXT NOT NULL,
    owner_email       TEXT NOT NULL,
    currency          TEXT NOT NULL DEFAULT 'BRL',  -- Group-wide currency (ISO 4217)
    ck_record_id      TEXT,
    ck_share_url      TEXT,
    created_at        INTEGER NOT NULL,
    updated_at        INTEGER NOT NULL,
    is_deleted        INTEGER NOT NULL DEFAULT 0
);

-- Group Members
CREATE TABLE IF NOT EXISTS GroupMembers (
    id                TEXT PRIMARY KEY,
    group_id          TEXT NOT NULL,
    user_id           TEXT NOT NULL,
    name              TEXT NOT NULL,
    email             TEXT NOT NULL,
    role              TEXT NOT NULL DEFAULT 'member',  -- 'owner' or 'member'
    permissions       TEXT NOT NULL DEFAULT '{}',      -- JSON blob of permission flags
    last_active       INTEGER,
    joined_at         INTEGER NOT NULL,
    is_removed        INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (group_id) REFERENCES BudgetGroups(id)
);

-- Group Invitations
CREATE TABLE IF NOT EXISTS GroupInvitations (
    id                TEXT PRIMARY KEY,
    group_id          TEXT NOT NULL,
    group_name        TEXT NOT NULL,
    inviter_name      TEXT NOT NULL,
    inviter_email     TEXT NOT NULL,
    invitee_email     TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'accepted', 'declined'
    ck_share_url      TEXT,
    created_at        INTEGER NOT NULL,
    responded_at      INTEGER,
    FOREIGN KEY (group_id) REFERENCES BudgetGroups(id)
);

-- Sync metadata tracking
CREATE TABLE IF NOT EXISTS SyncMetadata (
    record_type       TEXT PRIMARY KEY,
    change_token      BLOB,
    last_sync_date    INTEGER NOT NULL,
    sync_status       TEXT NOT NULL DEFAULT 'idle'  -- 'idle', 'syncing', 'error'
);

-- Migrations: Add sync + sharing columns to ALL existing tables
--
-- Transactions table:
-- ALTER TABLE Transactions ADD COLUMN ck_record_id TEXT;
-- ALTER TABLE Transactions ADD COLUMN ck_modified_at INTEGER;
-- ALTER TABLE Transactions ADD COLUMN sync_status TEXT DEFAULT 'pending';
-- ALTER TABLE Transactions ADD COLUMN shared_group_id TEXT;
--
-- Budgets table:
-- ALTER TABLE Budgets ADD COLUMN ck_record_id TEXT;
-- ALTER TABLE Budgets ADD COLUMN sync_status TEXT DEFAULT 'pending';
-- ALTER TABLE Budgets ADD COLUMN shared_group_id TEXT;
--
-- BudgetAllocations table:
-- ALTER TABLE BudgetAllocations ADD COLUMN ck_record_id TEXT;
-- ALTER TABLE BudgetAllocations ADD COLUMN sync_status TEXT DEFAULT 'pending';
-- ALTER TABLE BudgetAllocations ADD COLUMN shared_group_id TEXT;
--
-- CreditCards table:
-- ALTER TABLE CreditCards ADD COLUMN ck_record_id TEXT;
-- ALTER TABLE CreditCards ADD COLUMN sync_status TEXT DEFAULT 'pending';
-- ALTER TABLE CreditCards ADD COLUMN shared_group_id TEXT;   -- NULL = personal, non-NULL = shared with group
--
-- CreditCardStatements table:
-- ALTER TABLE CreditCardStatements ADD COLUMN ck_record_id TEXT;
-- ALTER TABLE CreditCardStatements ADD COLUMN sync_status TEXT DEFAULT 'pending';
-- (shared_group_id is inherited from the parent CreditCard — no need to duplicate)
```

---

## CloudKit Container Structure

```
iCloud.com.arthurrios.Finova
├── Private Database (per user)
│   ├── Zone: "FinovaPrivateZone"
│   │   ├── RecordType: "Transaction"    (syncs with local Transactions table)
│   │   ├── RecordType: "Budget"         (syncs with local Budgets table)
│   │   ├── RecordType: "BudgetAllocation"
│   │   ├── RecordType: "CreditCard"
│   │   ├── RecordType: "CreditCardStatement"
│   │   └── RecordType: "UserPreferences"
│   └── Subscriptions:
│       └── CKDatabaseSubscription (notifies on any private DB change)
│
└── Shared Database (for groups)
    ├── Zone: "Group-{groupId}" (one CKRecordZone per group, shared via CKShare)
    │   ├── RecordType: "BudgetGroup"
    │   ├── RecordType: "Transaction"      (shared transactions linked to group)
    │   ├── RecordType: "Budget"           (shared monthly budget)
    │   ├── RecordType: "BudgetAllocation" (shared category allocations)
    │   ├── RecordType: "CreditCard"       (cards shared with the group)
    │   ├── RecordType: "CreditCardStatement" (follows shared cards)
    │   ├── RecordType: "GroupMember"
    │   └── RecordType: "GroupActivity"    (activity log for notifications)
    └── Subscriptions:
        └── CKDatabaseSubscription (notifies on any shared DB change)
```

---

## Permission Flags

```swift
struct GroupPermissions: Codable, Equatable {
    var canCreateTransactions: Bool = true
    var canEditTransactions: Bool = false
    var canDeleteTransactions: Bool = false
    var canEditBudgets: Bool = false
    var canEditAllocations: Bool = false
    var canViewCreditCards: Bool = false
    var canManageCreditCards: Bool = false
    var canInviteMembers: Bool = false

    static let memberDefault = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: false,
        canDeleteTransactions: false,
        canEditBudgets: false,
        canEditAllocations: false,
        canViewCreditCards: false,
        canManageCreditCards: false,
        canInviteMembers: false
    )

    static let fullAccess = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: true,
        canDeleteTransactions: true,
        canEditBudgets: true,
        canEditAllocations: true,
        canViewCreditCards: true,
        canManageCreditCards: true,
        canInviteMembers: true
    )
}
```

---

# BUILD PHASES

---

## PHASE 1: CloudKit Foundation & Sync Infrastructure
**Estimated scope: Logic-heavy — no visible UI yet**

### 1.1 — Xcode Project Setup

**Steps:**
1. Enable **iCloud** capability in Xcode → Signing & Capabilities → + Capability → iCloud
2. Check **CloudKit** checkbox
3. Set container identifier: `iCloud.com.arthurrios.Finova`
4. Enable **Push Notifications** capability (required for CK subscriptions)
5. Enable **Background Modes** → check **Remote notifications**
6. Open CloudKit Dashboard (https://icloud.developer.apple.com) and verify the container exists

**Xcode entitlements file will auto-generate:**
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.arthurrios.Finova</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

### 1.2 — CloudKitManager (Core Singleton)

```swift
// Finova/Sources/Core/CloudKit/CloudKitManager.swift

import CloudKit
import UIKit

enum CloudKitAccountStatus {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}

protocol CloudKitManagerDelegate: AnyObject {
    func cloudKitAccountStatusDidChange(_ status: CloudKitAccountStatus)
    func cloudKitDidReceiveRemoteNotification(for recordZoneIDs: [CKRecordZone.ID])
}

final class CloudKitManager {
    static let shared = CloudKitManager()

    let container: CKContainer
    let privateDatabase: CKDatabase
    let sharedDatabase: CKDatabase

    private(set) var accountStatus: CloudKitAccountStatus = .couldNotDetermine
    private(set) var isCloudKitAvailable: Bool = false

    weak var delegate: CloudKitManagerDelegate?

    static let privateZoneID = CKRecordZone.ID(
        zoneName: "FinovaPrivateZone",
        ownerName: CKCurrentUserDefaultName
    )

    private init() {
        container = CKContainer(identifier: "iCloud.com.arthurrios.Finova")
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
    }

    // MARK: - Account Status

    func checkAccountStatus(completion: @escaping (CloudKitAccountStatus) -> Void) {
        container.accountStatus { [weak self] status, error in
            guard let self = self else { return }

            if let error = error {
                logError("CloudKit account status error: \(error.localizedDescription)")
                self.accountStatus = .couldNotDetermine
                DispatchQueue.main.async { completion(.couldNotDetermine) }
                return
            }

            let mapped: CloudKitAccountStatus
            switch status {
            case .available:
                mapped = .available
                self.isCloudKitAvailable = true
            case .noAccount:
                mapped = .noAccount
            case .restricted:
                mapped = .restricted
            case .couldNotDetermine:
                mapped = .couldNotDetermine
            case .temporarilyUnavailable:
                mapped = .temporarilyUnavailable
            @unknown default:
                mapped = .couldNotDetermine
            }

            self.accountStatus = mapped
            DispatchQueue.main.async {
                self.delegate?.cloudKitAccountStatusDidChange(mapped)
                completion(mapped)
            }
        }
    }

    // MARK: - Zone Creation

    func createPrivateZoneIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        let zone = CKRecordZone(zoneID: CloudKitManager.privateZoneID)
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: [zone],
            recordZoneIDsToDelete: nil
        )
        operation.modifyRecordZonesResultBlock = { result in
            switch result {
            case .success:
                logInfo("CloudKit private zone created/verified")
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let error):
                logError("CloudKit zone creation failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        operation.qualityOfService = .userInitiated
        privateDatabase.add(operation)
    }

    // MARK: - Subscriptions

    func setupPrivateDatabaseSubscription(completion: @escaping (Result<Void, Error>) -> Void) {
        let subscriptionID = "finova-private-changes"
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // silent push
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: nil
        )
        operation.modifySubscriptionsResultBlock = { result in
            switch result {
            case .success:
                logInfo("CloudKit private subscription set up")
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let error):
                // Subscription already exists is OK
                if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    logError("CloudKit subscription failed: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
        operation.qualityOfService = .utility
        privateDatabase.add(operation)
    }

    func setupSharedDatabaseSubscription(completion: @escaping (Result<Void, Error>) -> Void) {
        let subscriptionID = "finova-shared-changes"
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: nil
        )
        operation.modifySubscriptionsResultBlock = { result in
            switch result {
            case .success:
                logInfo("CloudKit shared subscription set up")
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
        operation.qualityOfService = .utility
        sharedDatabase.add(operation)
    }

    // MARK: - Remote Notification Handling

    func handleRemoteNotification(
        userInfo: [AnyHashable: Any],
        completion: @escaping () -> Void
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)

        guard let _ = notification else {
            completion()
            return
        }

        // Trigger sync for changed zones
        // The SyncEngine will fetch changes from the appropriate database
        NotificationCenter.default.post(name: .cloudKitRemoteNotificationReceived, object: nil)
        completion()
    }

    // MARK: - User Record ID

    func fetchCurrentUserRecordID(completion: @escaping (Result<CKRecord.ID, Error>) -> Void) {
        container.fetchUserRecordID { recordID, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
            } else if let recordID = recordID {
                DispatchQueue.main.async { completion(.success(recordID)) }
            }
        }
    }
}
```

### 1.3 — CKRecordConvertible Protocol

```swift
// Finova/Sources/Core/CloudKit/Models/CKRecordConvertible.swift

import CloudKit

protocol CKRecordConvertible {
    static var recordType: String { get }
    var ckRecordID: CKRecord.ID? { get }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord
    static func fromCKRecord(_ record: CKRecord) -> Self?
}
```

### 1.4 — CKTransactionAdapter

```swift
// Finova/Sources/Core/CloudKit/Models/CKTransactionAdapter.swift

import CloudKit

extension Transaction: CKRecordConvertible {
    static var recordType: String { "Transaction" }

    var ckRecordID: CKRecord.ID? {
        guard let syncRecordName = self.ckRecordName else { return nil }
        return CKRecord.ID(recordName: syncRecordName, zoneID: CloudKitManager.privateZoneID)
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID: CKRecord.ID
        if let existingID = ckRecordID {
            recordID = existingID
        } else {
            recordID = CKRecord.ID(
                recordName: "transaction-\(id)",
                zoneID: zoneID
            )
        }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["localId"] = id as CKRecordValue
        record["title"] = title as CKRecordValue
        record["amount"] = amount as CKRecordValue
        record["type"] = type.rawValue as CKRecordValue
        record["category"] = category.rawValue as CKRecordValue
        record["date"] = date as CKRecordValue
        record["isRecurring"] = (isRecurring ? 1 : 0) as CKRecordValue
        record["recurringFrequency"] = recurringFrequency?.rawValue as CKRecordValue?
        record["creditCardId"] = creditCardId as CKRecordValue?
        record["isDeleted"] = (isDeleted ? 1 : 0) as CKRecordValue
        record["userId"] = userId as CKRecordValue?
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> Transaction? {
        guard
            let localId = record["localId"] as? Int,
            let title = record["title"] as? String,
            let amount = record["amount"] as? Int,
            let typeRaw = record["type"] as? String,
            let type = TransactionType(rawValue: typeRaw),
            let categoryRaw = record["category"] as? String,
            let category = TransactionCategory(rawValue: categoryRaw),
            let date = record["date"] as? Date
        else { return nil }

        var transaction = Transaction(
            id: localId,
            title: title,
            amount: amount,
            type: type,
            category: category,
            date: date
        )
        transaction.ckRecordName = record.recordID.recordName
        transaction.isRecurring = (record["isRecurring"] as? Int) == 1
        transaction.creditCardId = record["creditCardId"] as? Int
        transaction.isDeleted = (record["isDeleted"] as? Int) == 1
        return transaction
    }
}
```

> **Note**: `CKBudgetAdapter.swift` and `CKBudgetAllocationAdapter.swift` follow the same pattern.

### 1.4b — CKCreditCardAdapter (Shared Cards)

Credit cards can be shared with a group. When `shared_group_id` is set, the card
syncs to the group's shared CKRecordZone instead of the private zone.

```swift
// Finova/Sources/Core/CloudKit/Models/CKCreditCardAdapter.swift

import CloudKit

extension CreditCard: CKRecordConvertible {
    static var recordType: String { "CreditCard" }

    var ckRecordID: CKRecord.ID? {
        guard let syncRecordName = self.ckRecordName else { return nil }
        let zoneID = targetZoneID
        return CKRecord.ID(recordName: syncRecordName, zoneID: zoneID)
    }

    /// If the card is shared, it goes to the group's zone. Otherwise, private zone.
    var targetZoneID: CKRecordZone.ID {
        if let groupId = sharedGroupId {
            return CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
        }
        return CloudKitManager.privateZoneID
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID: CKRecord.ID
        if let existingID = ckRecordID {
            recordID = existingID
        } else {
            recordID = CKRecord.ID(
                recordName: "creditCard-\(id ?? 0)",
                zoneID: targetZoneID // Use the shared zone if card is shared
            )
        }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["localId"] = (id ?? 0) as CKRecordValue
        record["name"] = name as CKRecordValue
        record["lastFourDigits"] = lastFourDigits as CKRecordValue
        record["cardBrand"] = cardBrand.rawValue as CKRecordValue
        record["closingDay"] = closingDay as CKRecordValue
        record["dueDay"] = dueDay as CKRecordValue
        record["creditLimit"] = (creditLimit ?? 0) as CKRecordValue
        record["cardColor"] = cardColor.rawValue as CKRecordValue
        record["userId"] = userId as CKRecordValue
        record["sharedGroupId"] = sharedGroupId as CKRecordValue?
        record["isDeleted"] = (isDeleted ? 1 : 0) as CKRecordValue
        record["isDefault"] = (isDefault ? 1 : 0) as CKRecordValue
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> CreditCard? {
        guard let name = record["name"] as? String,
              let lastFour = record["lastFourDigits"] as? String,
              let brandRaw = record["cardBrand"] as? String,
              let brand = CardBrand(rawValue: brandRaw),
              let closingDay = record["closingDay"] as? Int,
              let dueDay = record["dueDay"] as? Int,
              let colorRaw = record["cardColor"] as? String,
              let color = CardColor(rawValue: colorRaw),
              let userId = record["userId"] as? String
        else { return nil }

        var card = CreditCard(
            id: record["localId"] as? Int,
            name: name,
            lastFourDigits: lastFour,
            cardBrand: brand,
            closingDay: closingDay,
            dueDay: dueDay,
            creditLimit: record["creditLimit"] as? Int,
            cardColor: color,
            userId: userId,
            isDeleted: (record["isDeleted"] as? Int) == 1,
            isDefault: (record["isDefault"] as? Int) == 1,
            createdAt: record.creationDate ?? Date(),
            updatedAt: record.modificationDate ?? Date()
        )
        card.ckRecordName = record.recordID.recordName
        card.sharedGroupId = record["sharedGroupId"] as? String
        return card
    }
}
```

### 1.4c — CKCreditCardStatementAdapter

Statements follow their parent card's sharing context. If a card is shared,
its statements automatically belong to the same shared zone.

```swift
// Finova/Sources/Core/CloudKit/Models/CKCreditCardStatementAdapter.swift

import CloudKit

extension CreditCardStatement: CKRecordConvertible {
    static var recordType: String { "CreditCardStatement" }

    var ckRecordID: CKRecord.ID? {
        guard let syncRecordName = self.ckRecordName else { return nil }
        return CKRecord.ID(recordName: syncRecordName, zoneID: targetZoneID(for: creditCardId))
    }

    /// Look up the parent card to determine zone
    func targetZoneID(for cardId: Int) -> CKRecordZone.ID {
        if let card = CreditCardRepository().fetchCard(byId: cardId),
           let groupId = card.sharedGroupId {
            return CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
        }
        return CloudKitManager.privateZoneID
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let actualZone = targetZoneID(for: creditCardId)
        let recordID = CKRecord.ID(
            recordName: ckRecordName ?? "statement-\(id ?? 0)",
            zoneID: actualZone
        )
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["localId"] = (id ?? 0) as CKRecordValue
        record["creditCardId"] = creditCardId as CKRecordValue
        record["closingDate"] = closingDate as CKRecordValue
        record["dueDate"] = dueDate as CKRecordValue
        record["totalAmount"] = totalAmount as CKRecordValue
        record["isPaid"] = (isPaid ? 1 : 0) as CKRecordValue
        record["paidDate"] = paidDate as CKRecordValue?
        record["paidAmount"] = (paidAmount ?? 0) as CKRecordValue
        record["userId"] = userId as CKRecordValue
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> CreditCardStatement? {
        guard let creditCardId = record["creditCardId"] as? Int,
              let closingDate = record["closingDate"] as? Date,
              let dueDate = record["dueDate"] as? Date,
              let totalAmount = record["totalAmount"] as? Int,
              let userId = record["userId"] as? String
        else { return nil }

        var statement = CreditCardStatement(
            id: record["localId"] as? Int,
            creditCardId: creditCardId,
            closingDate: closingDate,
            dueDate: dueDate,
            totalAmount: totalAmount,
            isPaid: (record["isPaid"] as? Int) == 1,
            paidDate: record["paidDate"] as? Date,
            paidAmount: record["paidAmount"] as? Int,
            isDatesOverridden: false,
            userId: userId,
            createdAt: record.creationDate ?? Date(),
            updatedAt: record.modificationDate ?? Date()
        )
        statement.ckRecordName = record.recordID.recordName
        return statement
    }
}
```

### 1.4d — Shared Card Statement Recalculation

When a transaction is added to a shared card, the statement total must be
recalculated from ALL group members' transactions, not just the current user's.

This requires a change to `CreditCardService`:

```swift
// Add to CreditCardService.swift:

/// Recalculates statement total for a shared card by summing ALL members' transactions
func recalculateSharedStatementTotal(statementId: Int, creditCardId: Int) {
    let repo = TransactionRepository()
    let statementRepo = StatementRepository()

    // Fetch the card to check if shared
    guard let card = CreditCardRepository().fetchCard(byId: creditCardId),
          card.sharedGroupId != nil else { return }

    // Fetch ALL transactions for this statement (no userId filter for shared cards)
    let allTransactions = repo.fetchTransactionsForStatement(
        statementId: statementId,
        includeAllUsers: true  // New parameter — skips userId WHERE clause
    )

    let total = allTransactions.reduce(0) { $0 + $1.amount }
    statementRepo.updateStatementTotal(id: statementId, amount: total)
}
```

### 1.5 — SyncStateManager

```swift
// Finova/Sources/Core/CloudKit/SyncStateManager.swift

import CloudKit
import Foundation

final class SyncStateManager {
    static let shared = SyncStateManager()

    private let defaults = UserDefaults.standard
    private let tokenKeyPrefix = "ck_changeToken_"
    private let lastSyncKeyPrefix = "ck_lastSync_"

    func changeToken(for recordType: String, database: String = "private") -> CKServerChangeToken? {
        let key = tokenKeyPrefix + database + "_" + recordType
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func saveChangeToken(_ token: CKServerChangeToken?, for recordType: String, database: String = "private") {
        let key = tokenKeyPrefix + database + "_" + recordType
        if let token = token,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func lastSyncDate(for recordType: String) -> Date? {
        let key = lastSyncKeyPrefix + recordType
        let interval = defaults.double(forKey: key)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    func updateLastSyncDate(for recordType: String) {
        let key = lastSyncKeyPrefix + recordType
        defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    func resetAllTokens() {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(tokenKeyPrefix) || key.hasPrefix(lastSyncKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
```

### 1.6 — SyncEngine

```swift
// Finova/Sources/Core/CloudKit/SyncEngine.swift

import CloudKit
import Foundation

enum SyncStatus {
    case idle
    case syncing
    case synced
    case error(Error)
}

protocol SyncEngineDelegate: AnyObject {
    func syncEngineDidChangeStatus(_ status: SyncStatus)
    func syncEngineDidUpdateData()
}

final class SyncEngine {
    static let shared = SyncEngine()

    weak var delegate: SyncEngineDelegate?
    private(set) var status: SyncStatus = .idle {
        didSet {
            DispatchQueue.main.async {
                self.delegate?.syncEngineDidChangeStatus(self.status)
                NotificationCenter.default.post(name: .syncStatusDidChange, object: self.status)
            }
        }
    }

    private let cloudKit = CloudKitManager.shared
    private let stateManager = SyncStateManager.shared
    private let syncQueue = DispatchQueue(label: "com.finova.syncengine", qos: .utility)
    private var isSyncing = false

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteNotification),
            name: .cloudKitRemoteNotificationReceived,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocalDataChange),
            name: .transactionDataChanged,
            object: nil
        )
    }

    // MARK: - Public API

    func performFullSync() {
        syncQueue.async { [weak self] in
            self?.executeSyncCycle()
        }
    }

    @objc private func handleRemoteNotification() {
        performFullSync()
    }

    @objc private func handleLocalDataChange() {
        // Debounce: wait 2 seconds after last local change before pushing
        syncQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.pushLocalChanges()
        }
    }

    // MARK: - Sync Cycle

    private func executeSyncCycle() {
        guard !isSyncing else { return }
        guard cloudKit.isCloudKitAvailable else { return }

        isSyncing = true
        status = .syncing

        // Step 1: Pull remote changes
        fetchPrivateDatabaseChanges { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // Step 2: Push local changes
                self.pushLocalChanges { pushResult in
                    switch pushResult {
                    case .success:
                        self.status = .synced
                    case .failure(let error):
                        self.status = .error(error)
                    }
                    self.isSyncing = false
                }
            case .failure(let error):
                self.status = .error(error)
                self.isSyncing = false
            }
        }
    }

    // MARK: - Fetch Changes (Pull)

    private func fetchPrivateDatabaseChanges(completion: @escaping (Result<Void, Error>) -> Void) {
        let token = stateManager.changeToken(for: "privateDB", database: "private")

        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)
        var changedZoneIDs: [CKRecordZone.ID] = []

        operation.recordZoneWithIDChangedBlock = { zoneID in
            changedZoneIDs.append(zoneID)
        }

        operation.fetchDatabaseChangesResultBlock = { [weak self] result in
            switch result {
            case .success(let (token, _)):
                self?.stateManager.saveChangeToken(token, for: "privateDB", database: "private")
                if changedZoneIDs.isEmpty {
                    completion(.success(()))
                } else {
                    self?.fetchZoneChanges(zoneIDs: changedZoneIDs, database: .private, completion: completion)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }

        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    private func fetchZoneChanges(
        zoneIDs: [CKRecordZone.ID],
        database: CKDatabase.Scope,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for zoneID in zoneIDs {
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = stateManager.changeToken(for: zoneID.zoneName, database: database == .private ? "private" : "shared")
            configurations[zoneID] = config
        }

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: zoneIDs,
            configurationsByRecordZoneID: configurations
        )

        operation.recordWasChangedBlock = { [weak self] recordID, result in
            switch result {
            case .success(let record):
                self?.processIncomingRecord(record)
            case .failure(let error):
                logError("Failed to fetch record \(recordID): \(error)")
            }
        }

        operation.recordWithIDWasDeletedBlock = { [weak self] recordID, recordType in
            self?.processDeletedRecord(recordID: recordID, recordType: recordType)
        }

        operation.recordZoneFetchResultBlock = { [weak self] zoneID, result in
            switch result {
            case .success(let (token, _, _)):
                let dbKey = database == .private ? "private" : "shared"
                self?.stateManager.saveChangeToken(token, for: zoneID.zoneName, database: dbKey)
            case .failure(let error):
                logError("Zone fetch failed for \(zoneID.zoneName): \(error)")
            }
        }

        operation.fetchRecordZoneChangesResultBlock = { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }

        let db = database == .private ? cloudKit.privateDatabase : cloudKit.sharedDatabase
        operation.qualityOfService = .userInitiated
        db.add(operation)
    }

    // MARK: - Push Local Changes

    private func pushLocalChanges(completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Query local DB for records with sync_status = 'pending'
        let transactionRepo = TransactionRepository()
        let pendingTransactions = transactionRepo.fetchPendingSync()

        guard !pendingTransactions.isEmpty else {
            completion?(.success(()))
            return
        }

        let records = pendingTransactions.map {
            $0.toCKRecord(in: CloudKitManager.privateZoneID)
        }

        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.isAtomic = false // Allow partial success

        operation.perRecordSaveBlock = { recordID, result in
            switch result {
            case .success:
                // Mark as synced in local DB
                TransactionRepository().markAsSynced(ckRecordName: recordID.recordName)
            case .failure(let error):
                logError("Failed to push record \(recordID): \(error)")
            }
        }

        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                completion?(.success(()))
            case .failure(let error):
                completion?(.failure(error))
            }
        }

        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    // MARK: - Process Incoming Records

    private func processIncomingRecord(_ record: CKRecord) {
        switch record.recordType {
        case "Transaction":
            guard let transaction = Transaction.fromCKRecord(record) else { return }
            ConflictResolver.shared.resolveTransaction(remote: transaction, ckRecord: record)
        case "Budget":
            // Similar pattern
            break
        case "CreditCard":
            // Similar pattern
            break
        case "GroupActivity":
            // Process group activity for notifications
            processGroupActivity(record)
            break
        default:
            logWarning("Unknown record type received: \(record.recordType)")
        }
    }

    private func processDeletedRecord(recordID: CKRecord.ID, recordType: String) {
        // Soft-delete the local record matching this CK record
        switch recordType {
        case "Transaction":
            TransactionRepository().softDeleteByCKRecordName(recordID.recordName)
        default:
            break
        }
    }

    private func processGroupActivity(_ record: CKRecord) {
        // Dispatch to GroupNotificationManager for user-facing notification
        GroupNotificationManager.shared.handleIncomingActivity(record)
    }
}
```

### 1.7 — ConflictResolver

```swift
// Finova/Sources/Core/CloudKit/ConflictResolver.swift

import CloudKit
import Foundation

final class ConflictResolver {
    static let shared = ConflictResolver()

    private init() {}

    func resolveTransaction(remote: Transaction, ckRecord: CKRecord) {
        let repo = TransactionRepository()

        // Check if we have a local version
        guard let local = repo.fetchTransaction(byId: remote.id) else {
            // New record from cloud — insert locally
            repo.insertFromCloud(remote, ckRecordName: ckRecord.recordID.recordName)
            return
        }

        // Compare modification dates — last writer wins
        let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
        let localModDate = repo.lastModifiedDate(for: local.id) ?? Date.distantPast

        if remoteModDate > localModDate {
            // Remote wins — update local
            repo.updateFromCloud(remote, ckRecordName: ckRecord.recordID.recordName)
        } else {
            // Local wins — mark for push
            repo.markSyncPending(for: local.id)
        }
    }
}
```

### 1.8 — Notification Names Extension Update

```swift
// Add to Notification+Ext.swift:
static let cloudKitRemoteNotificationReceived = Notification.Name("cloudKitRemoteNotificationReceived")
static let syncStatusDidChange = Notification.Name("syncStatusDidChange")
static let budgetGroupDataChanged = Notification.Name("budgetGroupDataChanged")
static let groupInvitationReceived = Notification.Name("groupInvitationReceived")
static let groupMemberActionOccurred = Notification.Name("groupMemberActionOccurred")
```

### 1.9 — Database Migrations

Add to `DBHelper.swift` in `initializeDatabase()`:
```swift
try createBudgetGroupsTable()
try createGroupMembersTable()
try createGroupInvitationsTable()
try createSyncMetadataTable()
try migrateExistingTablesForSync()  // Adds ck_record_id, sync_status columns
```

### 1.10 — AppDelegate / SceneDelegate Integration

Add to `SceneDelegate` or `AppDelegate`:
```swift
// In application(_:didReceiveRemoteNotification:fetchCompletionHandler:)
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    CloudKitManager.shared.handleRemoteNotification(userInfo: userInfo) {
        completionHandler(.newData)
    }
}
```

**BUILD & TEST**: At this point, the app compiles with CloudKit infrastructure. Run on device, check CloudKit Dashboard to verify zone creation and subscription. No visible UI changes yet.

---

## PHASE 2: Sync Status UI & Settings Entry Point
**Estimated scope: UI-visible — 3 build checkpoints**

### 2.1 — SyncStatusIndicator Component (BUILD checkpoint 1)

```swift
// Finova/Sources/Core/Components/SyncStatusIndicator.swift

import UIKit

final class SyncStatusIndicator: UIView {
    enum Status {
        case idle
        case syncing
        case synced
        case error
        case offline
    }

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Colors.gray400        // ← gray400 for inactive icons
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font       // ← textXS for small indicators
        label.textColor = Colors.gray400      // ← gray400 default
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),  // Smaller than inputIconSize (20) — inline indicator
            iconView.heightAnchor.constraint(equalToConstant: 14),

            statusLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.spacing1),  // ← spacing1 (4)
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 18)  // Same as badge height
        ])
    }

    func updateStatus(_ status: Status) {
        stopSpinning()

        switch status {
        case .idle:
            iconView.image = UIImage(systemName: "cloud")
            iconView.tintColor = Colors.gray400
            statusLabel.text = "sync.status.idle".localized
            statusLabel.textColor = Colors.gray400
        case .syncing:
            iconView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            iconView.tintColor = Colors.mainMagenta
            statusLabel.text = "sync.status.syncing".localized
            statusLabel.textColor = Colors.mainMagenta
            startSpinning()
        case .synced:
            iconView.image = UIImage(systemName: "checkmark.icloud")
            iconView.tintColor = Colors.mainGreen
            statusLabel.text = "sync.status.synced".localized
            statusLabel.textColor = Colors.mainGreen
        case .error:
            iconView.image = UIImage(systemName: "exclamationmark.icloud")
            iconView.tintColor = Colors.mainRed
            statusLabel.text = "sync.status.error".localized
            statusLabel.textColor = Colors.mainRed
        case .offline:
            iconView.image = UIImage(systemName: "icloud.slash")
            iconView.tintColor = Colors.gray400
            statusLabel.text = "sync.status.offline".localized
            statusLabel.textColor = Colors.gray400
        }
    }

    private func startSpinning() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.toValue = NSNumber(value: Double.pi * 2)
        rotation.duration = 1.5
        rotation.repeatCount = .infinity
        rotation.isCumulative = true
        iconView.layer.add(rotation, forKey: "rotationAnimation")
    }

    private func stopSpinning() {
        iconView.layer.removeAnimation(forKey: "rotationAnimation")
    }
}
```

**BUILD**: Create the component file. Add it temporarily to DashboardView below the subtitle label to see it on screen. Verify the icon and label render. Remove the temporary placement after verifying.

### 2.2 — Add Sync Status to Dashboard Header (BUILD checkpoint 2)

Modify `DashboardView.swift` — add the sync indicator next to the welcome subtitle:

```swift
// Add property
let syncStatusIndicator = SyncStatusIndicator()

// In setupView(), after adding welcomeSubtitleLabel:
headerItemsView.addSubview(syncStatusIndicator)

// In setupLayout(), add constraints:
syncStatusIndicator.leadingAnchor.constraint(equalTo: welcomeSubtitleLabel.trailingAnchor, constant: Metrics.spacing2),
syncStatusIndicator.centerYAnchor.constraint(equalTo: welcomeSubtitleLabel.centerYAnchor),
syncStatusIndicator.trailingAnchor.constraint(lessThanOrEqualTo: notificationButton.leadingAnchor, constant: -Metrics.spacing2),
```

In `DashboardViewController`, observe sync status:
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleSyncStatusChange(_:)),
    name: .syncStatusDidChange,
    object: nil
)

@objc private func handleSyncStatusChange(_ notification: Notification) {
    guard let status = notification.object as? SyncStatus else { return }
    switch status {
    case .idle: contentView.syncStatusIndicator.updateStatus(.idle)
    case .syncing: contentView.syncStatusIndicator.updateStatus(.syncing)
    case .synced: contentView.syncStatusIndicator.updateStatus(.synced)
    case .error: contentView.syncStatusIndicator.updateStatus(.error)
    }
}
```

**BUILD**: Run the app. The dashboard header should now show a small cloud icon with "Synced" text next to the welcome subtitle. It will show "Offline" if no iCloud account.

### 2.3 — Add "Sharing" Section to Settings + Budget Groups to Profile (BUILD checkpoint 3)

**Budget Groups** is added to `ProfileView.swift` in the **Financial** section (alongside Credit Cards) for better discoverability. Only **iCloud Sync** remains in Settings.

Add to `ProfileView.swift` — new row in the Financial section after Credit Cards:
```swift
// New properties
private let budgetGroupsContainer: UIView = {
    let container = createSettingContainer()
    container.isUserInteractionEnabled = true
    return container
}()
private let budgetGroupsIconView = createIconView(imageName: "person.3")
private let budgetGroupsLabel = createSettingLabel(text: "settings.budgetGroups.title".localized)
private let budgetGroupsChevron = createChevronView()
```

Add in `setupSections()` after creditCardsContainer:
```swift
setupBudgetGroupsContainer()
contentStackView.addArrangedSubview(budgetGroupsContainer)
```

Update `ProfileViewDelegate`:
```swift
func didTapBudgetGroups()
```

Update `ProfileFlowDelegate`:
```swift
func navigateToBudgetGroups()
```

Add to `SettingsView.swift` — a "Sharing" section with only iCloud Sync:

```swift
private let sharingHeaderView = createSectionHeader(title: "settings.section.sharing".localized)

private let syncSettingsContainer: UIView = {
    let container = createSettingContainer()
    container.isUserInteractionEnabled = true
    return container
}()
private let syncSettingsIconView = createIconView(imageName: "icloud")
private let syncSettingsLabel = createSettingLabel(text: "settings.sync.title".localized)
let syncStatusDetailLabel = createDetailLabel(text: "")
private let syncSettingsChevron = createChevronView()
```

Update `SettingsFlowDelegate`:
```swift
public protocol SettingsFlowDelegate: AnyObject {
    func dismissSettings()
    func logout()
    func navigateToNotificationSettings()
    func navigateToSyncSettings()     // NEW
}
```

**BUILD**: Run the app. Navigate to Profile → see Budget Groups row in Financial section. Navigate to Settings → see "Sharing" section with iCloud Sync row.

---

## PHASE 3: Models & Local Storage for Groups
**Estimated scope: Logic-heavy — builds on Phase 1 DB schema**

### 3.1 — BudgetGroup Model

```swift
// Finova/Sources/Core/Models/BudgetGroup.swift

import Foundation

struct BudgetGroup: Codable, Equatable {
    let id: String
    var name: String
    let ownerId: String
    let ownerName: String
    let ownerEmail: String
    var currency: String       // ISO 4217 code — enforced group-wide
    var ckRecordId: String?
    var ckShareUrl: String?
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    var members: [GroupMember] = []
    var sharedCards: [CreditCard] = [] // Cards shared with this group

    init(
        id: String = UUID().uuidString,
        name: String,
        ownerId: String,
        ownerName: String,
        ownerEmail: String,
        currency: String = "BRL",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.ownerEmail = ownerEmail
        self.currency = currency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    var isOwner: Bool {
        guard let currentUser = AuthenticationManager.shared.currentUser else { return false }
        return ownerId == currentUser.firebaseUID
    }
}
```

### 3.2 — GroupMember Model

```swift
// Finova/Sources/Core/Models/GroupMember.swift

import Foundation

enum GroupRole: String, Codable {
    case owner
    case member
}

struct GroupMember: Codable, Equatable {
    let id: String
    let groupId: String
    let userId: String
    var name: String
    var email: String
    var role: GroupRole
    var permissions: GroupPermissions
    var lastActive: Date?
    let joinedAt: Date
    var isRemoved: Bool

    init(
        id: String = UUID().uuidString,
        groupId: String,
        userId: String,
        name: String,
        email: String,
        role: GroupRole = .member,
        permissions: GroupPermissions = .memberDefault,
        lastActive: Date? = nil,
        joinedAt: Date = Date(),
        isRemoved: Bool = false
    ) {
        self.id = id
        self.groupId = groupId
        self.userId = userId
        self.name = name
        self.email = email
        self.role = role
        self.permissions = permissions
        self.lastActive = lastActive
        self.joinedAt = joinedAt
        self.isRemoved = isRemoved
    }

    var lastActiveDescription: String {
        guard let lastActive = lastActive else {
            return "sharing.member.neverActive".localized
        }
        let interval = Date().timeIntervalSince(lastActive)
        if interval < 60 {
            return "sharing.member.activeNow".localized
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(format: "sharing.member.activeMinutesAgo".localized, minutes)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(format: "sharing.member.activeHoursAgo".localized, hours)
        } else {
            let days = Int(interval / 86400)
            return String(format: "sharing.member.activeDaysAgo".localized, days)
        }
    }
}
```

### 3.3 — GroupPermission Model

```swift
// Finova/Sources/Core/Models/GroupPermission.swift

import Foundation

struct GroupPermissions: Codable, Equatable {
    var canCreateTransactions: Bool
    var canEditTransactions: Bool
    var canDeleteTransactions: Bool
    var canEditBudgets: Bool
    var canEditAllocations: Bool
    var canViewCreditCards: Bool
    var canManageCreditCards: Bool
    var canInviteMembers: Bool

    static let memberDefault = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: false,
        canDeleteTransactions: false,
        canEditBudgets: false,
        canEditAllocations: false,
        canViewCreditCards: false,
        canManageCreditCards: false,
        canInviteMembers: false
    )

    static let fullAccess = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: true,
        canDeleteTransactions: true,
        canEditBudgets: true,
        canEditAllocations: true,
        canViewCreditCards: true,
        canManageCreditCards: true,
        canInviteMembers: true
    )

    var asJSON: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    static func fromJSON(_ json: String) -> GroupPermissions {
        guard let data = json.data(using: .utf8),
              let permissions = try? JSONDecoder().decode(GroupPermissions.self, from: data)
        else { return .memberDefault }
        return permissions
    }

    var allPermissions: [(key: String, label: String, isEnabled: Bool)] {
        return [
            ("canCreateTransactions", "permission.createTransactions".localized, canCreateTransactions),
            ("canEditTransactions", "permission.editTransactions".localized, canEditTransactions),
            ("canDeleteTransactions", "permission.deleteTransactions".localized, canDeleteTransactions),
            ("canEditBudgets", "permission.editBudgets".localized, canEditBudgets),
            ("canEditAllocations", "permission.editAllocations".localized, canEditAllocations),
            ("canViewCreditCards", "permission.viewCreditCards".localized, canViewCreditCards),
            ("canManageCreditCards", "permission.manageCreditCards".localized, canManageCreditCards),
            ("canInviteMembers", "permission.inviteMembers".localized, canInviteMembers),
        ]
    }

    mutating func setPermission(key: String, value: Bool) {
        switch key {
        case "canCreateTransactions": canCreateTransactions = value
        case "canEditTransactions": canEditTransactions = value
        case "canDeleteTransactions": canDeleteTransactions = value
        case "canEditBudgets": canEditBudgets = value
        case "canEditAllocations": canEditAllocations = value
        case "canViewCreditCards": canViewCreditCards = value
        case "canManageCreditCards": canManageCreditCards = value
        case "canInviteMembers": canInviteMembers = value
        default: break
        }
    }
}
```

### 3.4 — BudgetGroupRepository

```swift
// Finova/Sources/Core/Repositories/BudgetGroupRepository.swift

import Foundation
import SQLite3

final class BudgetGroupRepository {
    private let db = DBHelper.shared

    func insertGroup(_ group: BudgetGroup) { /* INSERT INTO BudgetGroups ... */ }
    func fetchAllGroups() -> [BudgetGroup] { /* SELECT * FROM BudgetGroups WHERE is_deleted = 0 */ }
    func fetchGroup(byId id: String) -> BudgetGroup? { /* SELECT ... WHERE id = ? */ }
    func updateGroup(_ group: BudgetGroup) { /* UPDATE BudgetGroups SET ... WHERE id = ? */ }
    func softDeleteGroup(id: String) { /* UPDATE BudgetGroups SET is_deleted = 1 WHERE id = ? */ }

    func insertMember(_ member: GroupMember) { /* INSERT INTO GroupMembers ... */ }
    func fetchMembers(forGroupId groupId: String) -> [GroupMember] { /* SELECT ... */ }
    func updateMember(_ member: GroupMember) { /* UPDATE GroupMembers SET ... */ }
    func removeMember(id: String) { /* UPDATE GroupMembers SET is_removed = 1 WHERE id = ? */ }
    func updateMemberLastActive(userId: String, date: Date) { /* UPDATE ... */ }

    func insertInvitation(_ invitation: GroupInvitation) { /* INSERT INTO GroupInvitations ... */ }
    func fetchPendingInvitations(forEmail email: String) -> [GroupInvitation] { /* SELECT ... status = 'pending' */ }
    func updateInvitationStatus(id: String, status: String) { /* UPDATE ... */ }
}
```

### 3.5 — BudgetGroupService

```swift
// Finova/Sources/Core/Services/BudgetGroupService.swift

import CloudKit
import Foundation

final class BudgetGroupService {
    static let shared = BudgetGroupService()

    private let repository = BudgetGroupRepository()
    private let cloudKit = CloudKitManager.shared

    func createGroup(name: String, completion: @escaping (Result<BudgetGroup, Error>) -> Void) {
        guard let user = AuthenticationManager.shared.currentUser,
              let userId = user.firebaseUID else {
            completion(.failure(NSError(domain: "BudgetGroupService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }

        let group = BudgetGroup(
            name: name,
            ownerId: userId,
            ownerName: user.displayName,
            ownerEmail: user.email
        )

        // Save locally
        repository.insertGroup(group)

        // Create owner as first member
        let ownerMember = GroupMember(
            groupId: group.id,
            userId: userId,
            name: user.displayName,
            email: user.email,
            role: .owner,
            permissions: .fullAccess,
            lastActive: Date()
        )
        repository.insertMember(ownerMember)

        // Create CKShare for this group
        createCloudKitShare(for: group) { result in
            switch result {
            case .success(let updatedGroup):
                completion(.success(updatedGroup))
            case .failure(let error):
                // Group exists locally, sync will retry later
                logError("CKShare creation failed: \(error)")
                completion(.success(group))
            }
        }
    }

    func inviteMember(
        email: String,
        toGroup group: BudgetGroup,
        permissions: GroupPermissions = .memberDefault,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard group.isOwner || currentUserCan(.canInviteMembers, in: group) else {
            completion(.failure(NSError(domain: "BudgetGroupService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No permission to invite members"])))
            return
        }

        guard let user = AuthenticationManager.shared.currentUser else { return }

        // Create invitation record
        let invitation = GroupInvitation(
            groupId: group.id,
            groupName: group.name,
            inviterName: user.displayName,
            inviterEmail: user.email,
            inviteeEmail: email
        )
        repository.insertInvitation(invitation)

        // Push invitation via CloudKit
        pushInvitationToCloud(invitation, group: group, completion: completion)
    }

    func currentUserCan(_ permission: WritableKeyPath<GroupPermissions, Bool>, in group: BudgetGroup) -> Bool {
        guard let user = AuthenticationManager.shared.currentUser,
              let userId = user.firebaseUID else { return false }

        if group.ownerId == userId { return true }

        let members = repository.fetchMembers(forGroupId: group.id)
        guard let member = members.first(where: { $0.userId == userId }) else { return false }
        return member.permissions[keyPath: permission]
    }

    // MARK: - CloudKit Share

    private func createCloudKitShare(
        for group: BudgetGroup,
        completion: @escaping (Result<BudgetGroup, Error>) -> Void
    ) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        // Create zone first
        let zoneOp = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        zoneOp.modifyRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.createShareRecord(for: group, in: zoneID, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
        zoneOp.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(zoneOp)
    }

    private func createShareRecord(
        for group: BudgetGroup,
        in zoneID: CKRecordZone.ID,
        completion: @escaping (Result<BudgetGroup, Error>) -> Void
    ) {
        // Create the root record for the group
        let recordID = CKRecord.ID(recordName: "budgetGroup-\(group.id)", zoneID: zoneID)
        let record = CKRecord(recordType: "BudgetGroup", recordID: recordID)
        record["name"] = group.name as CKRecordValue
        record["ownerId"] = group.ownerId as CKRecordValue
        record["ownerName"] = group.ownerName as CKRecordValue

        // Create a CKShare rooted on this record
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
        share.publicPermission = .none // Only explicit participants

        let operation = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                var updatedGroup = group
                updatedGroup.ckRecordId = recordID.recordName
                updatedGroup.ckShareUrl = share.url?.absoluteString
                self.repository.updateGroup(updatedGroup)
                completion(.success(updatedGroup))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    private func pushInvitationToCloud(
        _ invitation: GroupInvitation,
        group: BudgetGroup,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Use CKShare to add participant by email lookup
        guard let shareURLString = group.ckShareUrl,
              let shareURL = URL(string: shareURLString) else {
            completion(.failure(NSError(domain: "BudgetGroupService", code: 3, userInfo: nil)))
            return
        }

        // Fetch the share, add participant
        cloudKit.container.fetchShareMetadata(with: shareURL) { [weak self] metadata, error in
            guard let self = self, let metadata = metadata else {
                completion(.failure(error ?? NSError(domain: "BudgetGroupService", code: 4, userInfo: nil)))
                return
            }

            // Look up the user by email
            self.cloudKit.container.fetchShareParticipant(
                withEmailAddress: invitation.inviteeEmail
            ) { participant, error in
                guard let participant = participant else {
                    completion(.failure(error ?? NSError(domain: "BudgetGroupService", code: 5, userInfo: nil)))
                    return
                }

                participant.permission = .readWrite

                // Fetch the share record, add participant, save
                self.addParticipantToShare(participant, shareURL: shareURL, completion: completion)
            }
        }
    }

    private func addParticipantToShare(
        _ participant: CKShare.Participant,
        shareURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Fetch share by URL, modify it, save back
        let fetchOp = CKFetchShareMetadataOperation(shareURLs: [shareURL])
        fetchOp.shouldFetchRootRecord = true

        fetchOp.perShareMetadataResultBlock = { url, result in
            switch result {
            case .success(let metadata):
                guard let shareRecordID = metadata.share.recordID as CKRecord.ID? else { return }
                // Fetch and modify the share
                self.cloudKit.privateDatabase.fetch(withRecordID: shareRecordID) { record, error in
                    guard let share = record as? CKShare else { return }
                    share.addParticipant(participant)

                    let saveOp = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
                    saveOp.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            completion(.success(()))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                    self.cloudKit.privateDatabase.add(saveOp)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }

        cloudKit.container.add(fetchOp)
    }
}

// MARK: - GroupInvitation helper

struct GroupInvitation: Codable {
    let id: String
    let groupId: String
    let groupName: String
    let inviterName: String
    let inviterEmail: String
    let inviteeEmail: String
    var status: String
    var ckShareUrl: String?
    let createdAt: Date
    var respondedAt: Date?

    init(
        id: String = UUID().uuidString,
        groupId: String,
        groupName: String,
        inviterName: String,
        inviterEmail: String,
        inviteeEmail: String,
        status: String = "pending",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.groupId = groupId
        self.groupName = groupName
        self.inviterName = inviterName
        self.inviterEmail = inviterEmail
        self.inviteeEmail = inviteeEmail
        self.status = status
        self.createdAt = createdAt
    }
}
```

**BUILD & TEST**: All model and repository code compiles. No UI changes in this phase. Run unit tests to verify insert/fetch cycles on BudgetGroupRepository.

---

## PHASE 4: Budget Groups List Screen
**Estimated scope: UI-focused — 4 build checkpoints**

### 4.1 — Empty State & Root View (BUILD checkpoint 1)

Create the root view, view controller, flow delegate, and view delegate. Wire it into the factory and flow controller.

**BudgetGroupsFlowDelegate.swift:**
```swift
protocol BudgetGroupsFlowDelegate: AnyObject {
    func dismissBudgetGroups()
    func navigateToGroupDetails(group: BudgetGroup)
    func openCreateGroupModal()
}
```

**BudgetGroupsViewDelegate.swift:**
```swift
protocol BudgetGroupsViewDelegate: AnyObject {
    func handleDidTapBackButton()
    func didTapCreateGroup()
    func didSelectGroup(_ group: BudgetGroup)
}
```

**BudgetGroupsView.swift** — follows exact header pattern from SettingsView/TransactionDetailsView:
```swift
final class BudgetGroupsView: UIView {
    weak var delegate: BudgetGroupsViewDelegate?

    // MARK: - Header (exact same pattern as SettingsView)
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
        return view
    }()

    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            button.tintColor = Colors.gray700
        } else {
            button.tintColor = Colors.gray500
        }
        return button
    }()

    private lazy var backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM           // ← titleSM for all header titles
        label.text = "budgetGroups.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700           // ← gray700 for primary text
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Content
    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear             // ← inherits gray200 from parent
        table.separatorStyle = .none               // ← always .none, separators are manual
        table.showsVerticalScrollIndicator = false
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    let emptyView: EmptyGroupsView = {
        let view = EmptyGroupsView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // FAB: matches Dashboard addTransactionButton pattern exactly
    private let createGroupButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "plus")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            btn.tintColor = Colors.mainMagenta
            btn.backgroundColor = .clear
        } else {
            btn.tintColor = Colors.gray100
            btn.backgroundColor = Colors.gray700
            btn.layer.shadowColor = UIColor.black.cgColor
            btn.layer.shadowOffset = CGSize(width: 0, height: 4)
            btn.layer.shadowOpacity = 0.25
            btn.layer.shadowRadius = 4
        }
        return btn
    }()

    private lazy var createGroupButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray200           // ← ALWAYS gray200 for screen root
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        headerItemsView.addSubview(headerTitleLabel)

        addSubview(tableView)
        addSubview(emptyView)
        addSubview(createGroupButtonGlassContainer)
        createGroupButtonGlassContainer.addSubview(createGroupButton)

        // Glass effect on back button (iOS 26+)
        if #available(iOS 26.0, *) {
            let backGlass = UIGlassEffect(style: .clear)
            backGlass.isInteractive = true
            let backGlassView = UIVisualEffectView(effect: backGlass)
            backGlassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(backGlassView, at: 0)
            backGlassView.pinToEdges(of: backButtonGlassContainer)
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true

            // Glass on FAB
            let fabGlass = UIGlassEffect(style: .clear)
            fabGlass.isInteractive = true
            let fabGlassView = UIVisualEffectView(effect: fabGlass)
            fabGlassView.translatesAutoresizingMaskIntoConstraints = false
            createGroupButtonGlassContainer.insertSubview(fabGlassView, at: 0)
            fabGlassView.pinToEdges(of: createGroupButtonGlassContainer)
            createGroupButtonGlassContainer.layer.cornerRadius = Metrics.addButtonSize / 2
            createGroupButtonGlassContainer.clipsToBounds = true
        } else {
            createGroupButtonGlassContainer.layer.cornerRadius = Metrics.addButtonSize / 2
            createGroupButtonGlassContainer.clipsToBounds = true
        }

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        createGroupButton.addTarget(self, action: #selector(createGroupTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            // Header
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            // Back button: 36x36 glass container
            backButtonGlassContainer.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.bottomAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.bottomAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.centerXAnchor.constraint(equalTo: backButtonGlassContainer.centerXAnchor),
            backButton.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: Metrics.backButtonSize),
            backButton.heightAnchor.constraint(equalToConstant: Metrics.backButtonSize),

            // Title: left of back button
            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            headerTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: headerItemsView.layoutMarginsGuide.trailingAnchor),

            // Table
            tableView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Empty state: centered in table area
            emptyView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),

            // FAB: centered bottom, Metrics.addButtonSize (48x48)
            createGroupButtonGlassContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            createGroupButtonGlassContainer.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing4),
            createGroupButtonGlassContainer.widthAnchor.constraint(equalToConstant: Metrics.addButtonSize),
            createGroupButtonGlassContainer.heightAnchor.constraint(equalToConstant: Metrics.addButtonSize),

            createGroupButton.centerXAnchor.constraint(equalTo: createGroupButtonGlassContainer.centerXAnchor),
            createGroupButton.centerYAnchor.constraint(equalTo: createGroupButtonGlassContainer.centerYAnchor),
            createGroupButton.widthAnchor.constraint(equalToConstant: Metrics.addButtonSize),
            createGroupButton.heightAnchor.constraint(equalToConstant: Metrics.addButtonSize),
        ])
    }

    func updateEmptyState(isEmpty: Bool) {
        emptyView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    @objc private func backTapped() { delegate?.handleDidTapBackButton() }
    @objc private func createGroupTapped() { delegate?.didTapCreateGroup() }
}
```

**EmptyGroupsView.swift** — follows empty state pattern:
```swift
final class EmptyGroupsView: UIView {
    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.3")
        iv.tintColor = Colors.gray400              // ← gray400 for empty state icons
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM            // ← titleSM for empty state title
        label.text = "budgetGroups.empty.title".localized
        label.applyStyle()
        label.textColor = Colors.gray500           // ← gray500 for empty state title (not gray600)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font             // ← textSM for descriptions
        label.text = "budgetGroups.empty.subtitle".localized
        label.textColor = Colors.gray400            // ← gray400 for empty state subtitle
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing3,
            alignment: .center, arrangedSubviews: [iconView, titleLabel, subtitleLabel])
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 48),  // ← 48x48 for large empty state icon
            iconView.heightAnchor.constraint(equalToConstant: 48),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing8),
        ])
    }
}
```

**Wire into ViewControllersFactory and AppFlowController.**

**BUILD**: Navigate Profile → Budget Groups. See the empty state with person.3 icon, title, subtitle.

### 4.2 — BudgetGroupCell (BUILD checkpoint 2)

```swift
// Finova/Sources/Scenes/BudgetGroups/Views/BudgetGroupCell.swift

final class BudgetGroupCell: UITableViewCell {
    static let identifier = "BudgetGroupCell"

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.large
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let groupIconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.3.fill")
        iv.tintColor = Colors.mainMagenta
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let memberCountLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let avatarStack = GroupAvatarStack() // Component from Phase 4.3

    private let ownerBadge = MemberBadge()

    private let chevronView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "chevron.right")
        iv.tintColor = Colors.gray400
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        contentView.addSubview(containerView)
        containerView.addSubview(groupIconView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(memberCountLabel)
        containerView.addSubview(avatarStack)
        containerView.addSubview(ownerBadge)
        containerView.addSubview(chevronView)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            // Container: full width with vertical spacing between cells
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing1),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing1),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            // Group icon: leading, centered vertically
            groupIconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Metrics.spacing4),
            groupIconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 32),
            groupIconView.heightAnchor.constraint(equalToConstant: 32),

            // Name: after icon, top-biased
            nameLabel.leadingAnchor.constraint(equalTo: groupIconView.trailingAnchor, constant: Metrics.spacing3),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Metrics.spacing4),

            // Member count: below name
            memberCountLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            memberCountLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            // Owner badge: after name, same baseline
            ownerBadge.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: Metrics.spacing2),
            ownerBadge.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            // Avatar stack: trailing, centered
            avatarStack.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -Metrics.spacing3),
            avatarStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            // Constrain name to not overlap avatar stack
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: avatarStack.leadingAnchor, constant: -Metrics.spacing3),

            // Chevron: trailing edge
            chevronView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Metrics.spacing4),
            chevronView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    func configure(with group: BudgetGroup) {
        nameLabel.text = group.name
        memberCountLabel.text = String(
            format: "budgetGroups.cell.memberCount".localized,
            group.members.count
        )
        ownerBadge.isHidden = !group.isOwner
        ownerBadge.configure(role: group.isOwner ? .owner : .member)
        avatarStack.configure(with: group.members.prefix(3).map { $0.name })
    }
}
```

**BUILD**: Add mock data to the ViewModel. See group cells in the table with name, member count, and chevron.

### 4.3 — GroupAvatarStack Component (BUILD checkpoint 3)

```swift
// Finova/Sources/Core/Components/GroupAvatarStack.swift

final class GroupAvatarStack: UIView {
    private let maxVisible = 3
    private let avatarSize: CGFloat = 28
    private let overlap: CGFloat = 8

    private var avatarViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with names: [String]) {
        avatarViews.forEach { $0.removeFromSuperview() }
        avatarViews.removeAll()

        let visibleNames = Array(names.prefix(maxVisible))

        for (index, name) in visibleNames.enumerated() {
            let avatarView = createAvatarView(initial: String(name.prefix(1)).uppercased())
            let xOffset = CGFloat(index) * (avatarSize - overlap)
            avatarView.frame = CGRect(x: xOffset, y: 0, width: avatarSize, height: avatarSize)
            avatarView.layer.cornerRadius = avatarSize / 2
            avatarView.layer.borderWidth = 2
            avatarView.layer.borderColor = Colors.gray100.cgColor
            addSubview(avatarView)
            avatarViews.append(avatarView)
        }

        let totalWidth = CGFloat(visibleNames.count) * avatarSize - CGFloat(max(0, visibleNames.count - 1)) * overlap
        widthAnchor.constraint(equalToConstant: totalWidth).isActive = true
        heightAnchor.constraint(equalToConstant: avatarSize).isActive = true
    }

    private func createAvatarView(initial: String) -> UIView {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta.withAlphaComponent(0.2)
        view.clipsToBounds = true

        let label = UILabel()
        label.text = initial
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Colors.mainMagenta
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }
}
```

**BUILD**: See overlapping circular avatar initials in each group cell.

### 4.4 — ViewModel with Data Loading (BUILD checkpoint 4)

```swift
// Finova/Sources/Scenes/BudgetGroups/BudgetGroupsViewModel.swift

final class BudgetGroupsViewModel {
    private let groupService = BudgetGroupService.shared
    private let repository = BudgetGroupRepository()

    private(set) var groups: [BudgetGroup] = []
    var onGroupsUpdated: (() -> Void)?
    var onError: ((String) -> Void)?

    var isEmpty: Bool { groups.isEmpty }

    func loadGroups() {
        groups = repository.fetchAllGroups()
        // Load members for each group
        for i in groups.indices {
            groups[i].members = repository.fetchMembers(forGroupId: groups[i].id)
        }
        onGroupsUpdated?()
    }

    func createGroup(name: String) {
        groupService.createGroup(name: name) { [weak self] result in
            switch result {
            case .success:
                self?.loadGroups()
            case .failure(let error):
                self?.onError?(error.localizedDescription)
            }
        }
    }

    func deleteGroup(at index: Int) {
        guard index < groups.count else { return }
        let group = groups[index]
        guard group.isOwner else {
            onError?("sharing.error.onlyOwnerCanDelete".localized)
            return
        }
        repository.softDeleteGroup(id: group.id)
        loadGroups()
    }
}
```

**BUILD**: Full Budget Groups list screen functional. Create a test group via debug, see it appear in the list.

---

## PHASE 5: Group Details Screen
**Estimated scope: UI-focused — 4 build checkpoints**

### 5.1 — Root View with Group Header (BUILD checkpoint 1)

**GroupDetailsView.swift** — Shows group name, owner badge, member count at top. Large header card with group icon.

**GroupDetailsFlowDelegate.swift:**
```swift
protocol GroupDetailsFlowDelegate: AnyObject {
    func dismissGroupDetails()
    func navigateToMemberPermissions(member: GroupMember, group: BudgetGroup)
    func openInviteMemberModal(group: BudgetGroup)
}
```

**GroupDetailsViewDelegate.swift:**
```swift
protocol GroupDetailsViewDelegate: AnyObject {
    func handleDidTapBackButton()
    func didTapInvite()
    func didTapLeaveGroup()
    func didTapDeleteGroup()
    func didTapRenameGroup()
    func didSelectMember(_ member: GroupMember)
}
```

**InviteMemberViewDelegate.swift:**
```swift
protocol InviteMemberViewDelegate: AnyObject {
    func didTapClose()
    func didTapSendInvitation()
}
```

**MemberPermissionsViewDelegate.swift:**
```swift
protocol MemberPermissionsViewDelegate: AnyObject {
    func handleDidTapBackButton()
    func didTapRemoveMember()
}
```

**GroupInvitationFlowDelegate.swift:**
```swift
protocol GroupInvitationFlowDelegate: AnyObject {
    func didAcceptInvitation()
    func didDeclineInvitation()
}
```

**GroupDetailsView.swift:**
```swift
// Finova/Sources/Scenes/GroupDetails/GroupDetailsView.swift

final class GroupDetailsView: UIView {
    weak var delegate: GroupDetailsViewDelegate?

    // MARK: - Header (exact same pattern as SettingsView / BudgetGroupsView)
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
        return view
    }()

    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            button.tintColor = Colors.gray700
        } else {
            button.tintColor = Colors.gray500
        }
        return button
    }()

    private lazy var backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "groupDetails.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Scroll Content
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing4               // ← 16px between sections
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Group Info Card (CardHeader + content card pattern)
    private let groupInfoHeaderView = CardHeader(
        headerTitle: "groupDetails.info.header.title".localized)

    private lazy var groupInfoContentView: UIStackView = {
        let stackView = UIStackView(
            axis: .vertical, spacing: Metrics.spacing4,
            arrangedSubviews: [groupNameRow, ownerRow, createdDateRow, currencyRow])
        stackView.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing5, left: Metrics.spacing5,
            bottom: Metrics.spacing5, right: Metrics.spacing5)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.backgroundColor = Colors.gray100
        stackView.layer.borderWidth = 1
        stackView.layer.borderColor = Colors.gray300.cgColor
        stackView.layer.cornerRadius = CornerRadius.extraLarge
        stackView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        stackView.clipsToBounds = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    // Detail rows (TransactionDetails createDetailRow pattern)
    private lazy var groupNameRow: UIView = createDetailRow(
        title: "groupDetails.name.label".localized, value: "")
    private lazy var ownerRow: UIView = createDetailRow(
        title: "groupDetails.owner.label".localized, value: "")
    private lazy var createdDateRow: UIView = createDetailRow(
        title: "groupDetails.created.label".localized, value: "")
    private lazy var currencyRow: UIView = createDetailRow(
        title: "groupDetails.currency.title".localized, value: "")

    // MARK: - Members Section
    private let membersSectionHeaderView: UIView = {
        // Custom header with "Invite" button on the right
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let label = UILabel()
        label.text = "groupDetails.members.title".localized.uppercased()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing2),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }()

    let inviteButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("groupDetails.invite.button".localized, for: .normal)
        btn.titleLabel?.font = Fonts.buttonSM.font
        btn.setTitleColor(Colors.mainMagenta, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    let membersTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.isScrollEnabled = false                  // ← embedded in scrollView
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    // MARK: - Shared Cards Section (added in Phase 10.0b)
    private let sharedCardsSectionHeaderView = createSectionHeader(
        title: "groupDetails.sharedCards.title".localized)

    let sharedCardsTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.isScrollEnabled = false
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    // MARK: - Danger Zone
    private let dangerSectionHeaderView = createSectionHeader(title: "groupDetails.dangerZone.title".localized)

    private let leaveGroupContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()

    private let leaveGroupIconView = createIconView(imageName: "rectangle.portrait.and.arrow.right", tintColor: Colors.mainRed)
    private let leaveGroupLabel: UILabel = {
        let label = createSettingLabel(text: "groupDetails.leave.button".localized)
        label.textColor = Colors.mainRed                // ← red for destructive actions
        return label
    }()

    private let deleteGroupContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()

    private let deleteGroupIconView = createIconView(imageName: "trash", tintColor: Colors.mainRed)
    private let deleteGroupLabel: UILabel = {
        let label = createSettingLabel(text: "groupDetails.delete.button".localized)
        label.textColor = Colors.mainRed
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray200
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        headerItemsView.addSubview(headerTitleLabel)

        addSubview(scrollView)
        scrollView.addSubview(contentStackView)

        // Info card
        contentStackView.addArrangedSubview(groupInfoHeaderView)
        contentStackView.addArrangedSubview(groupInfoContentView)
        contentStackView.setCustomSpacing(0, after: groupInfoHeaderView)

        // Members section
        contentStackView.addArrangedSubview(membersSectionHeaderView)
        membersSectionHeaderView.addSubview(inviteButton)
        contentStackView.addArrangedSubview(membersTableView)

        // Shared cards section
        contentStackView.addArrangedSubview(sharedCardsSectionHeaderView)
        contentStackView.addArrangedSubview(sharedCardsTableView)

        // Danger zone
        contentStackView.addArrangedSubview(dangerSectionHeaderView)
        setupLeaveGroupContainer()
        contentStackView.addArrangedSubview(leaveGroupContainer)
        setupDeleteGroupContainer()
        contentStackView.addArrangedSubview(deleteGroupContainer)

        // Glass effect on back button
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .clear)
            glassEffect.isInteractive = true
            let glassView = UIVisualEffectView(effect: glassEffect)
            glassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(glassView, at: 0)
            glassView.pinToEdges(of: backButtonGlassContainer)
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true
        }

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        inviteButton.addTarget(self, action: #selector(inviteTapped), for: .touchUpInside)

        let leaveTap = UITapGestureRecognizer(target: self, action: #selector(leaveGroupTapped))
        leaveGroupContainer.addGestureRecognizer(leaveTap)

        let deleteTap = UITapGestureRecognizer(target: self, action: #selector(deleteGroupTapped))
        deleteGroupContainer.addGestureRecognizer(deleteTap)
    }

    private func setupLeaveGroupContainer() {
        leaveGroupContainer.addSubview(leaveGroupIconView)
        leaveGroupContainer.addSubview(leaveGroupLabel)

        NSLayoutConstraint.activate([
            leaveGroupIconView.leadingAnchor.constraint(equalTo: leaveGroupContainer.leadingAnchor, constant: Metrics.spacing4),
            leaveGroupIconView.centerYAnchor.constraint(equalTo: leaveGroupContainer.centerYAnchor),
            leaveGroupIconView.widthAnchor.constraint(equalToConstant: 20),
            leaveGroupIconView.heightAnchor.constraint(equalToConstant: 20),

            leaveGroupLabel.leadingAnchor.constraint(equalTo: leaveGroupIconView.trailingAnchor, constant: Metrics.spacing3),
            leaveGroupLabel.centerYAnchor.constraint(equalTo: leaveGroupContainer.centerYAnchor),
        ])
    }

    private func setupDeleteGroupContainer() {
        deleteGroupContainer.addSubview(deleteGroupIconView)
        deleteGroupContainer.addSubview(deleteGroupLabel)

        NSLayoutConstraint.activate([
            deleteGroupIconView.leadingAnchor.constraint(equalTo: deleteGroupContainer.leadingAnchor, constant: Metrics.spacing4),
            deleteGroupIconView.centerYAnchor.constraint(equalTo: deleteGroupContainer.centerYAnchor),
            deleteGroupIconView.widthAnchor.constraint(equalToConstant: 20),
            deleteGroupIconView.heightAnchor.constraint(equalToConstant: 20),

            deleteGroupLabel.leadingAnchor.constraint(equalTo: deleteGroupIconView.trailingAnchor, constant: Metrics.spacing3),
            deleteGroupLabel.centerYAnchor.constraint(equalTo: deleteGroupContainer.centerYAnchor),
        ])
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            // Header
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.bottomAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.bottomAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.centerXAnchor.constraint(equalTo: backButtonGlassContainer.centerXAnchor),
            backButton.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: Metrics.backButtonSize),
            backButton.heightAnchor.constraint(equalToConstant: Metrics.backButtonSize),

            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            headerTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: headerItemsView.layoutMarginsGuide.trailingAnchor),

            // Scroll content
            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(
                equalTo: scrollView.topAnchor, constant: Metrics.spacing4),
            contentStackView.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            contentStackView.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            contentStackView.bottomAnchor.constraint(
                equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
            contentStackView.widthAnchor.constraint(
                equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4),

            // Invite button (trailing in members section header)
            inviteButton.trailingAnchor.constraint(
                equalTo: membersSectionHeaderView.trailingAnchor, constant: -Metrics.spacing2),
            inviteButton.centerYAnchor.constraint(equalTo: membersSectionHeaderView.centerYAnchor),
        ])
    }

    // MARK: - Factory Methods (same as SettingsView)

    private static func createSettingContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = Colors.gray100
        container.layer.cornerRadius = CornerRadius.large
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 56).isActive = true
        return container
    }

    private static func createIconView(imageName: String, tintColor: UIColor = Colors.gray600) -> UIImageView {
        let iv = UIImageView()
        iv.image = UIImage(systemName: imageName)?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = tintColor
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return iv
    }

    private static func createSettingLabel(text: String) -> UILabel {
        let label = UILabel()
        label.font = Fonts.titleSM.font                // ← .font (no uppercase for setting labels)
        label.textColor = Colors.gray700
        label.text = text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func createSectionHeader(title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title.uppercased()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing2),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 24),
        ])
        return container
    }

    // MARK: - Detail Row (same as TransactionDetailsView)

    private func createDetailRow(title: String, value: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray600
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = Fonts.textSM.font
        valueLabel.textColor = Colors.gray700
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Metrics.spacing3),

            container.heightAnchor.constraint(equalToConstant: 24),
        ])
        return container
    }

    // MARK: - Configuration

    func configure(with group: BudgetGroup) {
        headerTitleLabel.text = group.name
        headerTitleLabel.applyStyle()
        headerTitleLabel.textColor = Colors.gray700

        // Update detail rows
        updateDetailRowValue(groupNameRow, value: group.name)
        updateDetailRowValue(ownerRow, value: group.ownerName)
        updateDetailRowValue(currencyRow, value: group.currency)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        updateDetailRowValue(createdDateRow, value: formatter.string(from: group.createdAt))

        // Show/hide danger zone based on ownership
        leaveGroupContainer.isHidden = group.isOwner     // Owner can't leave, only delete
        deleteGroupContainer.isHidden = !group.isOwner   // Only owner can delete
    }

    private func updateDetailRowValue(_ row: UIView, value: String) {
        if let valueLabel = row.subviews.last as? UILabel {
            valueLabel.text = value
        }
    }

    // MARK: - Actions

    @objc private func backTapped() { delegate?.handleDidTapBackButton() }
    @objc private func inviteTapped() { delegate?.didTapInvite() }
    @objc private func leaveGroupTapped() { delegate?.didTapLeaveGroup() }
    @objc private func deleteGroupTapped() { delegate?.didTapDeleteGroup() }
}
```

**BUILD**: Navigate from Budget Groups list → Group Details. See header with group name and back button. Info card with detail rows. Danger zone with red leave/delete buttons.

### 5.2 — GroupMemberCell (BUILD checkpoint 2)

```swift
// Finova/Sources/Scenes/GroupDetails/Views/GroupMemberCell.swift

final class GroupMemberCell: UITableViewCell {
    static let identifier = "GroupMemberCell"

    // Container: same setting container pattern (gray100, cornerRadius large, 72dp height for more content)
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.large
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // Avatar initial circle (like GroupAvatarStack but standalone, 40x40)
    private let avatarView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta.withAlphaComponent(0.2)
        view.layer.cornerRadius = Metrics.profileImageSize / 2  // ← 20 (40/2)
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Colors.mainMagenta
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Name + email stack
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font             // ← textSMBold for cell primary text
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let emailLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font                 // ← textXS for secondary info
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Role badge + last active
    let roleBadge = MemberBadge()

    private let lastActiveLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray400               // ← gray400 for tertiary info
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Chevron (visible only for owner viewing a member)
    private let chevronView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "chevron.right")
        iv.tintColor = Colors.gray400
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        contentView.addSubview(containerView)
        containerView.addSubview(avatarView)
        avatarView.addSubview(avatarLabel)

        let textStack = UIStackView(axis: .vertical, spacing: 2,
            arrangedSubviews: [nameLabel, emailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(textStack)

        let trailingStack = UIStackView(axis: .vertical, spacing: Metrics.spacing1,
            alignment: .trailing, arrangedSubviews: [roleBadge, lastActiveLabel])
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(trailingStack)

        containerView.addSubview(chevronView)

        NSLayoutConstraint.activate([
            avatarLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
        ])

        self.textStack = textStack
        self.trailingStack = trailingStack
    }

    private var textStack: UIStackView!
    private var trailingStack: UIStackView!

    private func setupLayout() {
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing1),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing1),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            avatarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Metrics.spacing4),
            avatarView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: Metrics.profileImageSize),
            avatarView.heightAnchor.constraint(equalToConstant: Metrics.profileImageSize),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: Metrics.spacing3),
            textStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            trailingStack.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -Metrics.spacing2),
            trailingStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -Metrics.spacing3),

            chevronView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Metrics.spacing4),
            chevronView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    func configure(with member: GroupMember, isCurrentUserOwner: Bool) {
        nameLabel.text = member.name
        emailLabel.text = member.email
        avatarLabel.text = String(member.name.prefix(1)).uppercased()
        roleBadge.configure(role: member.role)
        lastActiveLabel.text = member.lastActiveDescription
        chevronView.isHidden = !isCurrentUserOwner || member.role == .owner
    }
}
```

**BUILD**: See member list with avatar initials, names, emails, role badges, "Active 2h ago" labels, and chevrons.

### 5.3 — MemberBadge & PermissionToggleRow Components (BUILD checkpoint 3)

```swift
// Finova/Sources/Core/Components/MemberBadge.swift
// Follows status badge pattern: small pill with tinted bg + text
final class MemberBadge: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font             // ← textXS for badge text
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = CornerRadius.small    // ← small (4) for status badges
        clipsToBounds = true
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing1),     // ← spacing1 vertical padding
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.spacing1),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing2),  // ← spacing2 horizontal padding
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing2),
        ])
    }

    func configure(role: GroupRole) {
        switch role {
        case .owner:
            label.text = "sharing.role.owner".localized
            backgroundColor = Colors.lowMagenta    // ← lowMagenta (5% alpha) like outlined button bg
            label.textColor = Colors.mainMagenta
        case .member:
            label.text = "sharing.role.member".localized
            backgroundColor = Colors.gray300       // ← gray300 for neutral badges
            label.textColor = Colors.gray600       // ← gray600 for neutral text
        }
    }
}

// Finova/Sources/Core/Components/PermissionToggleRow.swift
// Follows setting row pattern: gray100 container, 56dp height, icon + label + toggle
final class PermissionToggleRow: UIView {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font            // ← titleSM.font (not fontStyle — no uppercase for settings labels)
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font             // ← textXS for descriptions
        label.textColor = Colors.gray500            // ← gray500 for secondary text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let toggle: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = Colors.mainMagenta    // ← mainMagenta for all switches
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()

    var onToggleChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = Colors.gray100           // ← gray100 for setting row bg
        layer.cornerRadius = CornerRadius.large    // ← large (8) for setting rows
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 56).isActive = true  // ← 56dp setting row height

        let textStack = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [titleLabel, descriptionLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        addSubview(toggle)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),  // ← spacing4 (16) horizontal padding
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),

            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -Metrics.spacing3),
        ])

        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
    }

    @objc private func toggleChanged() {
        onToggleChanged?(toggle.isOn)
    }

    func configure(title: String, description: String, isOn: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        toggle.isOn = isOn
    }
}
```

**BUILD**: Components render correctly in the Group Details member cells and in the Permissions screen.

### 5.4 — Group Actions: Leave, Delete, Rename (BUILD checkpoint 4)

The danger zone is already built into `GroupDetailsView` above (Phase 5.1) using the exact
SettingsView pattern: `createSettingContainer()` with red icon + red label, 56dp height.

Additional action for this checkpoint — **inline rename**:

```swift
// In GroupDetailsView, add to the groupInfoContentView stack:

private let renameButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.setImage(UIImage(systemName: "pencil")?.withConfiguration(
        UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)), for: .normal)
    btn.tintColor = Colors.gray500
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
    btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
    return btn
}()

// Tap handler shows UIAlertController with text field:
@objc private func renameTapped() {
    delegate?.didTapRenameGroup()
}
```

In `GroupDetailsViewController`:
```swift
func didTapRenameGroup() {
    let alert = UIAlertController(
        title: "groupDetails.rename.title".localized,
        message: nil,
        preferredStyle: .alert)
    alert.addTextField { textField in
        textField.text = self.viewModel.group.name
        textField.font = Fonts.input.font
    }
    alert.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
    alert.addAction(UIAlertAction(title: "common.save".localized, style: .default) { [weak self] _ in
        guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
        self?.viewModel.renameGroup(to: name)
    })
    present(alert, animated: true)
}
```

Confirmation alerts for leave/delete use standard `UIAlertController`:
```swift
func didTapLeaveGroup() {
    let alert = UIAlertController(
        title: "groupDetails.leave.button".localized,
        message: "groupDetails.leave.confirm".localized,
        preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
    alert.addAction(UIAlertAction(title: "groupDetails.leave.button".localized, style: .destructive) { [weak self] _ in
        self?.viewModel.leaveGroup()
        self?.flowDelegate?.dismissGroupDetails()
    })
    present(alert, animated: true)
}
```

**BUILD**: Full Group Details screen operational. Tap pencil → rename alert. Tap leave/delete → confirmation alerts with destructive styling.

---

## PHASE 6: Invite Member Flow
**Estimated scope: UI-focused — 3 build checkpoints**

### 6.1 — InviteMemberView Root (BUILD checkpoint 1)

Modal presentation (bottom sheet style, matching existing AddTransaction modal pattern).

```swift
// Finova/Sources/Scenes/InviteMember/InviteMemberView.swift

final class InviteMemberView: UIView {
    weak var delegate: InviteMemberViewDelegate?

    // MARK: - Modal header (same as AddTransactionModalView)
    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleXS              // ← titleXS for modal titles (12pt bold UPPERCASE)
        label.text = "invite.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let closeIconButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "xmark"), for: .normal)
        btn.tintColor = Colors.gray500               // ← gray500 for close button
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Content (modal uses gray100 bg)
    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing7              // ← spacing7 (28) between major sections
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing10,                   // ← spacing10 (40) modal top padding
            leading: Metrics.spacing8,                // ← spacing8 (32) modal horizontal padding
            bottom: Metrics.spacing4,                 // ← spacing4 (16) modal bottom padding
            trailing: Metrics.spacing8)
        return stack
    }()

    // MARK: - Email Input
    private let emailSectionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font               // ← textSM for section labels in modals
        label.textColor = Colors.gray400              // ← gray400 for section labels
        label.text = "invite.email.section".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let emailInput = Input(
        type: .email,
        placeholder: "invite.email.placeholder".localized,
        leftIcon: UIImage(systemName: "envelope")
    )

    // MARK: - Permission Presets
    private let presetSectionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "invite.preset.section".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let presetSegmentedControl: InputSegmentedControl = {
        let control = InputSegmentedControl(
            items: [
                "invite.preset.viewOnly".localized,
                "invite.preset.canAdd".localized,
                "invite.preset.fullAccess".localized,
                "invite.preset.custom".localized
            ])
        return control
    }()

    // MARK: - Custom Permissions (hidden by default, shown when "Custom" selected)
    let customPermissionsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing3              // ← spacing3 (12) between toggle rows
        stack.isHidden = true                         // ← hidden until "Custom" selected
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Separator + Send Button
    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }()

    let sendButton = Button(variant: .base, label: "invite.send.button".localized)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray100             // ← gray100 for modals (not gray200)
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(contentStackView)

        // Header row
        let headerStack = UIStackView(arrangedSubviews: [headerTitleLabel, UIView(), closeIconButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        closeIconButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeIconButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        contentStackView.addArrangedSubview(headerStack)

        // Email section
        let emailGroup = UIStackView(axis: .vertical, spacing: Metrics.spacing3,
            arrangedSubviews: [emailSectionLabel, emailInput])
        contentStackView.addArrangedSubview(emailGroup)

        // Preset section
        let presetGroup = UIStackView(axis: .vertical, spacing: Metrics.spacing3,
            arrangedSubviews: [presetSectionLabel, presetSegmentedControl])
        contentStackView.addArrangedSubview(presetGroup)

        // Custom permissions (collapsible)
        contentStackView.addArrangedSubview(customPermissionsStack)
        setupPermissionToggles()

        // Separator + button
        contentStackView.addArrangedSubview(separatorView)
        contentStackView.addArrangedSubview(sendButton)

        closeIconButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        contentStackView.pinToEdges(of: self)
    }

    private func setupPermissionToggles() {
        let permissions = GroupPermissions.memberDefault.allPermissions
        for perm in permissions {
            let row = PermissionToggleRow()
            row.configure(
                title: perm.label,
                description: "",
                isOn: perm.isEnabled
            )
            row.accessibilityIdentifier = perm.key
            customPermissionsStack.addArrangedSubview(row)
        }
    }

    func showCustomPermissions(_ show: Bool) {
        UIView.animate(withDuration: 0.3) {
            self.customPermissionsStack.isHidden = !show
            self.customPermissionsStack.alpha = show ? 1 : 0
        }
    }

    @objc private func closeTapped() { delegate?.didTapClose() }
    @objc private func sendTapped() { delegate?.didTapSendInvitation() }
}
```

**Presentation (in GroupDetailsViewController):**
```swift
func didTapInvite() {
    let vc = factory.makeInviteMemberViewController(group: viewModel.group)
    vc.modalPresentationStyle = .pageSheet
    if let sheet = vc.sheetPresentationController {
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberHandle = true
        sheet.preferredCornerRadius = CornerRadius.bottomSheet  // ← 20
    }
    present(vc, animated: true)
}
```

**BUILD**: Tap "Invite" on Group Details → modal slides up with email input and permission presets.

### 6.2 — Custom Permissions Expandable Section (BUILD checkpoint 2)

In `InviteMemberViewController`, handle segment changes:

```swift
// In viewDidLoad:
contentView.presetSegmentedControl.addTarget(
    self, action: #selector(presetChanged), for: .valueChanged)

@objc private func presetChanged() {
    let selectedIndex = contentView.presetSegmentedControl.selectedSegmentIndex
    let isCustom = selectedIndex == 3  // "Custom" is index 3

    contentView.showCustomPermissions(isCustom)

    // Apply preset permissions
    switch selectedIndex {
    case 0: viewModel.applyPreset(.viewOnly)
    case 1: viewModel.applyPreset(.canAdd)
    case 2: viewModel.applyPreset(.fullAccess)
    default: break  // Custom — user toggles manually
    }
}
```

**BUILD**: Toggle between presets. Select "Custom" → see all 8 permission toggles animate into view with smooth expand.

### 6.3 — Send Invitation Logic & Confirmation (BUILD checkpoint 3)

Wire ViewModel to `BudgetGroupService.inviteMember()`. Show success toast or error alert.

```swift
// InviteMemberViewModel:
func sendInvitation(completion: @escaping (Result<Void, Error>) -> Void) {
    guard !email.isEmpty else {
        completion(.failure(NSError(domain: "", code: 0,
            userInfo: [NSLocalizedDescriptionKey: "invite.error.emptyEmail".localized])))
        return
    }

    groupService.inviteMember(
        email: email,
        toGroup: group,
        permissions: currentPermissions
    ) { result in
        DispatchQueue.main.async { completion(result) }
    }
}
```

**BUILD**: Enter an email, select permissions, tap Send. See success toast. Invitation appears in CloudKit Dashboard.

---

## PHASE 7: Member Permissions Screen
**Estimated scope: UI-focused — 2 build checkpoints**

### 7.1 — Root View with All Permission Toggles (BUILD checkpoint 1)

```swift
// Finova/Sources/Scenes/MemberPermissions/MemberPermissionsView.swift

final class MemberPermissionsView: UIView {
    weak var delegate: MemberPermissionsViewDelegate?

    // MARK: - Header (same compact header pattern)
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
        return view
    }()

    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            button.tintColor = Colors.gray700
        } else {
            button.tintColor = Colors.gray500
        }
        return button
    }()

    private lazy var backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "permissions.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Member Info (top card)
    private let memberAvatarView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta.withAlphaComponent(0.2)
        view.layer.cornerRadius = Metrics.profileImageSize / 2
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let memberAvatarLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Colors.mainMagenta
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let memberNameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let memberEmailLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Scroll Content
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing3               // ← spacing3 (12) between toggle rows
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Permission Sections
    // Each section: section header + toggle rows

    // Transactions section
    private let transactionsSectionHeader = createSectionHeader(title: "permissions.section.transactions".localized)
    let canCreateToggle = PermissionToggleRow()
    let canEditToggle = PermissionToggleRow()
    let canDeleteToggle = PermissionToggleRow()

    // Budgets section
    private let budgetsSectionHeader = createSectionHeader(title: "permissions.section.budgets".localized)
    let canEditBudgetsToggle = PermissionToggleRow()
    let canEditAllocationsToggle = PermissionToggleRow()

    // Credit Cards section
    private let creditCardsSectionHeader = createSectionHeader(title: "permissions.section.creditCards".localized)
    let canViewCardsToggle = PermissionToggleRow()
    let canManageCardsToggle = PermissionToggleRow()

    // Group section
    private let groupSectionHeader = createSectionHeader(title: "permissions.section.group".localized)
    let canInviteToggle = PermissionToggleRow()

    // MARK: - Footer (Remove Member button — danger action)
    private let footerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let footerBorderView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let removeMemberButton = Button(variant: .outlined, label: "permissions.removeMember.button".localized)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray200
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        // Header
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        headerItemsView.addSubview(headerTitleLabel)

        // Member info card
        let memberInfoCard = UIView()
        memberInfoCard.backgroundColor = Colors.gray100
        memberInfoCard.layer.cornerRadius = CornerRadius.large
        memberInfoCard.translatesAutoresizingMaskIntoConstraints = false

        memberInfoCard.addSubview(memberAvatarView)
        memberAvatarView.addSubview(memberAvatarLabel)

        let nameStack = UIStackView(axis: .vertical, spacing: 2,
            arrangedSubviews: [memberNameLabel, memberEmailLabel])
        nameStack.translatesAutoresizingMaskIntoConstraints = false
        memberInfoCard.addSubview(nameStack)

        NSLayoutConstraint.activate([
            memberInfoCard.heightAnchor.constraint(equalToConstant: 72),
            memberAvatarView.leadingAnchor.constraint(equalTo: memberInfoCard.leadingAnchor, constant: Metrics.spacing4),
            memberAvatarView.centerYAnchor.constraint(equalTo: memberInfoCard.centerYAnchor),
            memberAvatarView.widthAnchor.constraint(equalToConstant: Metrics.profileImageSize),
            memberAvatarView.heightAnchor.constraint(equalToConstant: Metrics.profileImageSize),
            memberAvatarLabel.centerXAnchor.constraint(equalTo: memberAvatarView.centerXAnchor),
            memberAvatarLabel.centerYAnchor.constraint(equalTo: memberAvatarView.centerYAnchor),
            nameStack.leadingAnchor.constraint(equalTo: memberAvatarView.trailingAnchor, constant: Metrics.spacing3),
            nameStack.centerYAnchor.constraint(equalTo: memberInfoCard.centerYAnchor),
            nameStack.trailingAnchor.constraint(lessThanOrEqualTo: memberInfoCard.trailingAnchor, constant: -Metrics.spacing4),
        ])

        // Scroll content
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(memberInfoCard)

        // Transaction permissions
        contentStackView.addArrangedSubview(transactionsSectionHeader)
        canCreateToggle.configure(title: "permission.createTransactions".localized, description: "", isOn: true)
        contentStackView.addArrangedSubview(canCreateToggle)
        canEditToggle.configure(title: "permission.editTransactions".localized, description: "", isOn: false)
        contentStackView.addArrangedSubview(canEditToggle)
        canDeleteToggle.configure(title: "permission.deleteTransactions".localized, description: "", isOn: false)
        contentStackView.addArrangedSubview(canDeleteToggle)

        // Budget permissions
        contentStackView.addArrangedSubview(budgetsSectionHeader)
        canEditBudgetsToggle.configure(title: "permission.editBudgets".localized, description: "", isOn: false)
        contentStackView.addArrangedSubview(canEditBudgetsToggle)
        canEditAllocationsToggle.configure(title: "permission.editAllocations".localized, description: "", isOn: false)
        contentStackView.addArrangedSubview(canEditAllocationsToggle)

        // Credit Card permissions
        contentStackView.addArrangedSubview(creditCardsSectionHeader)
        canViewCardsToggle.configure(title: "permission.viewCreditCards".localized, description: "", isOn: false)
        contentStackView.addArrangedSubview(canViewCardsToggle)
        canManageCardsToggle.configure(title: "permission.manageCreditCards".localized, description: "", isOn: false)
        contentStackView.addArrangedSubview(canManageCardsToggle)

        // Group permissions
        contentStackView.addArrangedSubview(groupSectionHeader)
        canInviteToggle.configure(title: "permission.inviteMembers".localized, description: "", isOn: false)
        contentStackView.addArrangedSubview(canInviteToggle)

        // Footer
        addSubview(footerView)
        footerView.addSubview(footerBorderView)
        footerView.addSubview(removeMemberButton)

        // Glass on back button
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .clear)
            glassEffect.isInteractive = true
            let glassView = UIVisualEffectView(effect: glassEffect)
            glassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(glassView, at: 0)
            glassView.pinToEdges(of: backButtonGlassContainer)
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true
        }

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        removeMemberButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            // Header
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.bottomAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.bottomAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.centerXAnchor.constraint(equalTo: backButtonGlassContainer.centerXAnchor),
            backButton.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: Metrics.backButtonSize),
            backButton.heightAnchor.constraint(equalToConstant: Metrics.backButtonSize),

            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

            // Scroll content
            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Metrics.spacing4),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4),

            // Footer (same pattern as TransactionDetailsView action buttons)
            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            footerBorderView.topAnchor.constraint(equalTo: footerView.topAnchor),
            footerBorderView.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            footerBorderView.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            footerBorderView.heightAnchor.constraint(equalToConstant: 1),

            removeMemberButton.topAnchor.constraint(equalTo: footerBorderView.bottomAnchor, constant: Metrics.spacing4),
            removeMemberButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: Metrics.spacing4),
            removeMemberButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -Metrics.spacing4),
            removeMemberButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing4),
        ])
    }

    private static func createSectionHeader(title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title.uppercased()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing2),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 24),
        ])
        return container
    }

    // MARK: - Configuration

    func configure(with member: GroupMember) {
        memberAvatarLabel.text = String(member.name.prefix(1)).uppercased()
        memberNameLabel.text = member.name
        memberEmailLabel.text = member.email

        let perms = member.permissions
        canCreateToggle.configure(title: "permission.createTransactions".localized, description: "", isOn: perms.canCreateTransactions)
        canEditToggle.configure(title: "permission.editTransactions".localized, description: "", isOn: perms.canEditTransactions)
        canDeleteToggle.configure(title: "permission.deleteTransactions".localized, description: "", isOn: perms.canDeleteTransactions)
        canEditBudgetsToggle.configure(title: "permission.editBudgets".localized, description: "", isOn: perms.canEditBudgets)
        canEditAllocationsToggle.configure(title: "permission.editAllocations".localized, description: "", isOn: perms.canEditAllocations)
        canViewCardsToggle.configure(title: "permission.viewCreditCards".localized, description: "", isOn: perms.canViewCreditCards)
        canManageCardsToggle.configure(title: "permission.manageCreditCards".localized, description: "", isOn: perms.canManageCreditCards)
        canInviteToggle.configure(title: "permission.inviteMembers".localized, description: "", isOn: perms.canInviteMembers)
    }

    @objc private func backTapped() { delegate?.handleDidTapBackButton() }
    @objc private func removeTapped() { delegate?.didTapRemoveMember() }
}
```

**BUILD**: Tap a member in Group Details → see permissions screen with header, member info card, grouped toggles, and red Remove button at bottom.

### 7.2 — Save Permissions & Remove Member (BUILD checkpoint 2)

```swift
// MemberPermissionsViewController:

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // Auto-save permissions when navigating back
    viewModel.savePermissions()
}

// In ViewModel:
func savePermissions() {
    var perms = member.permissions
    // Read toggle states from view (via delegate callbacks or direct property access)
    // ... update each permission flag ...
    member.permissions = perms
    repository.updateMember(member)

    // Push to CloudKit
    SyncEngine.shared.performFullSync()

    // Log activity
    GroupNotificationService.shared.logActivity(
        action: .permissionsChanged,
        groupId: member.groupId,
        detail: member.name
    )
}

func removeMember() {
    repository.removeMember(id: member.id)
    GroupNotificationService.shared.logActivity(
        action: .memberRemoved,
        groupId: member.groupId,
        detail: member.name
    )
    SyncEngine.shared.performFullSync()
}
```

Wire remove button to confirmation alert in ViewController:
```swift
func didTapRemoveMember() {
    let alert = UIAlertController(
        title: "permissions.removeMember.confirm.title".localized,
        message: String(format: "permissions.removeMember.confirm.message".localized, viewModel.member.name),
        preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
    alert.addAction(UIAlertAction(title: "permissions.removeMember.button".localized, style: .destructive) { [weak self] _ in
        self?.viewModel.removeMember()
        self?.navigationController?.popViewController(animated: true)
    })
    present(alert, animated: true)
}
```

**BUILD**: Toggle permissions, go back. Re-enter → permissions persisted. Remove member → confirmation alert → member disappears from list.

---

## PHASE 8: Group Invitation Receiving
**Estimated scope: UI-focused — 2 build checkpoints**

### 8.1 — GroupInvitationView (BUILD checkpoint 1)

Shown as a modal when app receives a CloudKit share acceptance or when checking pending invitations on launch.

```swift
// Finova/Sources/Scenes/GroupInvitation/GroupInvitationView.swift

final class GroupInvitationView: UIView {
    weak var delegate: GroupInvitationFlowDelegate?

    // MARK: - Modal header (same as InviteMemberView)
    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleXS
        label.text = "invitation.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let closeIconButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "xmark"), for: .normal)
        btn.tintColor = Colors.gray500
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Invitation Card (CardHeader + content pattern)
    private let invitationCardHeader = CardHeader(
        headerTitle: "invitation.card.header".localized)

    private lazy var invitationCardContent: UIStackView = {
        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing4,
            arrangedSubviews: [groupInfoStack, separatorLine, permissionsSummaryStack])
        stack.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing5, left: Metrics.spacing5,
            bottom: Metrics.spacing5, right: Metrics.spacing5)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = Colors.gray100
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Colors.gray300.cgColor
        stack.layer.cornerRadius = CornerRadius.extraLarge
        stack.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // Group info section (icon + name + inviter)
    private let groupIconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.3.fill")
        iv.tintColor = Colors.mainMagenta
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let groupNameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let inviterLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var groupInfoStack: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(groupIconView)
        let textStack = UIStackView(axis: .vertical, spacing: 2,
            arrangedSubviews: [groupNameLabel, inviterLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            groupIconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            groupIconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 32),
            groupIconView.heightAnchor.constraint(equalToConstant: 32),

            textStack.leadingAnchor.constraint(equalTo: groupIconView.trailingAnchor, constant: Metrics.spacing3),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            container.heightAnchor.constraint(equalToConstant: 48),
        ])
        return container
    }()

    private let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }()

    // Permissions summary section
    private let permissionsTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "invitation.permissions.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let permissionsListLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var permissionsSummaryStack: UIStackView = {
        return UIStackView(axis: .vertical, spacing: Metrics.spacing2,
            arrangedSubviews: [permissionsTitleLabel, permissionsListLabel])
    }()

    // MARK: - Action Buttons
    let acceptButton = Button(variant: .base, label: "invitation.accept.button".localized)

    private let declineButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("invitation.decline.button".localized, for: .normal)
        btn.titleLabel?.font = Fonts.buttonSM.font
        btn.setTitleColor(Colors.gray500, for: .normal)  // ← gray500 for secondary/text-only button
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight).isActive = true
        return btn
    }()

    // MARK: - Content Stack
    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing7
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing10,
            leading: Metrics.spacing8,
            bottom: Metrics.spacing4,
            trailing: Metrics.spacing8)
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray100             // ← gray100 for modals
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(contentStackView)

        // Header row
        let headerStack = UIStackView(arrangedSubviews: [headerTitleLabel, UIView(), closeIconButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        closeIconButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeIconButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        contentStackView.addArrangedSubview(headerStack)

        // Invitation card
        contentStackView.addArrangedSubview(invitationCardHeader)
        contentStackView.addArrangedSubview(invitationCardContent)
        contentStackView.setCustomSpacing(0, after: invitationCardHeader)

        // Buttons
        let buttonStack = UIStackView(axis: .vertical, spacing: Metrics.spacing3,
            arrangedSubviews: [acceptButton, declineButton])
        contentStackView.addArrangedSubview(buttonStack)

        closeIconButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        contentStackView.pinToEdges(of: self)
    }

    // MARK: - Configuration

    func configure(with invitation: GroupInvitation, permissions: GroupPermissions) {
        groupNameLabel.text = invitation.groupName
        inviterLabel.text = String(format: "invitation.invitedBy".localized, invitation.inviterName)

        // Build permissions summary
        let enabledPerms = permissions.allPermissions
            .filter { $0.isEnabled }
            .map { "• \($0.label)" }
            .joined(separator: "\n")
        permissionsListLabel.text = enabledPerms.isEmpty
            ? "invitation.permissions.viewOnly".localized
            : enabledPerms
    }

    @objc private func acceptTapped() { delegate?.didAcceptInvitation() }
    @objc private func declineTapped() { delegate?.didDeclineInvitation() }
}
```

**Presentation:**
```swift
// Shown as a modal from AppFlowController when pending invitation detected:
func presentGroupInvitation(_ invitation: GroupInvitation) {
    let vc = factory.makeGroupInvitationViewController(invitation: invitation)
    vc.modalPresentationStyle = .pageSheet
    if let sheet = vc.sheetPresentationController {
        sheet.detents = [.medium()]
        sheet.prefersGrabberHandle = true
        sheet.preferredCornerRadius = CornerRadius.bottomSheet
    }
    topViewController?.present(vc, animated: true)
}
```

**BUILD**: Simulate an invitation. See the invitation card with group name, inviter, permissions summary, and accept/decline buttons.

### 8.2 — Accept/Decline Logic (BUILD checkpoint 2)

```swift
// GroupInvitationViewModel:

func acceptInvitation(completion: @escaping (Result<BudgetGroup, Error>) -> Void) {
    guard let shareURL = invitation.ckShareUrl,
          let url = URL(string: shareURL) else {
        completion(.failure(NSError(domain: "GroupInvitation", code: 1, userInfo: nil)))
        return
    }

    // Accept the CKShare
    CloudKitManager.shared.container.fetchShareMetadata(with: url) { metadata, error in
        guard let metadata = metadata else {
            completion(.failure(error ?? NSError(domain: "GroupInvitation", code: 2, userInfo: nil)))
            return
        }

        CloudKitManager.shared.container.accept(metadata) { [weak self] share, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            // Insert group and member locally
            let group = BudgetGroup(
                id: self.invitation.groupId,
                name: self.invitation.groupName,
                ownerId: "",  // Will be populated from CK sync
                ownerName: self.invitation.inviterName,
                ownerEmail: self.invitation.inviterEmail
            )
            self.repository.insertGroup(group)

            // Update invitation status
            self.repository.updateInvitationStatus(id: self.invitation.id, status: "accepted")

            // Trigger sync to pull all group data
            SyncEngine.shared.performFullSync()

            DispatchQueue.main.async { completion(.success(group)) }
        }
    }
}

func declineInvitation() {
    repository.updateInvitationStatus(id: invitation.id, status: "declined")
}
```

Add pending invitation badge to the Budget Groups row in Profile:
```swift
// In ProfileView, add badge to budgetGroupsContainer:
let invitationBadge: UIView = {
    let badge = UIView()
    badge.backgroundColor = Colors.mainMagenta
    badge.layer.cornerRadius = 9  // 18/2
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.isHidden = true
    // 18x18, border 2px gray100 (same as notification badge)
    badge.layer.borderWidth = 2
    badge.layer.borderColor = Colors.gray100.cgColor
    badge.widthAnchor.constraint(equalToConstant: 18).isActive = true
    badge.heightAnchor.constraint(equalToConstant: 18).isActive = true
    return badge
}()
// Position: trailing edge of budgetGroupsContainer, offset by -spacing2
```

**BUILD**: Accept an invitation → group appears in Budget Groups list. Badge shows on Profile row when pending invitations exist.

---

## PHASE 9: Group Push Notifications
**Estimated scope: Logic + light UI — 2 build checkpoints**

### 9.1 — GroupNotificationService

```swift
// Finova/Sources/Core/Services/GroupNotificationService.swift

final class GroupNotificationService {
    static let shared = GroupNotificationService()

    enum GroupAction: String {
        case transactionCreated = "transaction_created"
        case transactionEdited = "transaction_edited"
        case transactionDeleted = "transaction_deleted"
        case budgetEdited = "budget_edited"
        case allocationEdited = "allocation_edited"
        case memberJoined = "member_joined"
        case memberLeft = "member_left"
        case memberRemoved = "member_removed"
        case permissionsChanged = "permissions_changed"
        case groupRenamed = "group_renamed"
    }

    func logActivity(
        action: GroupAction,
        groupId: String,
        detail: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        // Create a GroupActivity CKRecord in the shared zone
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "activity-\(UUID().uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "GroupActivity", recordID: recordID)

        guard let user = AuthenticationManager.shared.currentUser else { return }

        record["action"] = action.rawValue as CKRecordValue
        record["actorName"] = user.displayName as CKRecordValue
        record["actorId"] = (user.firebaseUID ?? "") as CKRecordValue
        record["detail"] = detail as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                completion?(.success(()))
            case .failure(let error):
                completion?(.failure(error))
            }
        }
        operation.qualityOfService = .utility
        CloudKitManager.shared.privateDatabase.add(operation)
    }
}
```

### 9.2 — GroupNotificationManager (local notification display)

```swift
// Finova/Sources/Core/Utils/GroupNotificationManager.swift

import CloudKit
import UserNotifications

final class GroupNotificationManager {
    static let shared = GroupNotificationManager()

    func handleIncomingActivity(_ record: CKRecord) {
        guard let action = record["action"] as? String,
              let actorName = record["actorName"] as? String,
              let detail = record["detail"] as? String,
              let actorId = record["actorId"] as? String else { return }

        // Don't notify for own actions
        guard actorId != AuthenticationManager.shared.currentUser?.firebaseUID else { return }

        let content = UNMutableNotificationContent()
        content.title = actorName
        content.body = notificationBody(for: action, detail: detail)
        content.sound = .default
        content.categoryIdentifier = "GROUP_ACTIVITY"

        let request = UNNotificationRequest(
            identifier: record.recordID.recordName,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)

        // Also post to in-app notification history
        NotificationCenter.default.post(name: .groupMemberActionOccurred, object: nil, userInfo: [
            "action": action,
            "actorName": actorName,
            "detail": detail
        ])
    }

    private func notificationBody(for action: String, detail: String) -> String {
        switch GroupNotificationService.GroupAction(rawValue: action) {
        case .transactionCreated:
            return String(format: "notification.group.transactionCreated".localized, detail)
        case .transactionEdited:
            return String(format: "notification.group.transactionEdited".localized, detail)
        case .transactionDeleted:
            return String(format: "notification.group.transactionDeleted".localized, detail)
        case .budgetEdited:
            return String(format: "notification.group.budgetEdited".localized, detail)
        case .memberJoined:
            return String(format: "notification.group.memberJoined".localized, detail)
        case .memberLeft:
            return String(format: "notification.group.memberLeft".localized, detail)
        default:
            return detail
        }
    }
}
```

**BUILD checkpoint 1**: Trigger a group action → see local push notification on device. Verify it appears in notification center.

**BUILD checkpoint 2**: Check in-app notification history shows group activity entries. Verify own actions don't generate notifications.

---

## PHASE 10: Integration — Permission Checks, Shared Data & Service Updates
**Estimated scope: Logic integration — 4 build checkpoints**

### 10.0 — Group-Aware Services (Critical — Statement & Ledger Updates)

These changes are essential for correct financial calculations in group context.

**TransactionLedgerService — group-aware variant:**
```swift
// Add to TransactionLedgerService.swift:

/// Fetches transactions for group context — includes ALL members' transactions
private func fetchGroupTransactionsIncludingStatements(groupId: String) -> [Transaction] {
    // Fetch all transactions with shared_group_id = groupId (no userId filter)
    var transactions = transactionRepo.fetchTransactionsForGroup(groupId: groupId)

    // For shared credit cards in this group, generate statement transactions
    let sharedCards = CreditCardRepository().fetchCardsForGroup(groupId: groupId)
    for card in sharedCards {
        let statementTxs = creditCardService.generateStatementTransactions(
            forCard: card,
            includeAllUsers: true // Sum all members' charges
        )
        transactions.append(contentsOf: statementTxs)
    }
    return transactions
}

/// Group-aware monthly data calculation
func calculateMonthlyDataForGroup(
    groupId: String,
    for monthRange: ClosedRange<Int>,
    referenceDate: Date = Date()
) -> [MonthBudgetCardType] {
    let allTransactions = fetchGroupTransactionsIncludingStatements(groupId: groupId)
    let budgetsByAnchor = budgetRepo.fetchBudgetsForGroup(groupId: groupId)
        .reduce(into: [:]) { acc, entry in acc[entry.monthDate] = entry.amount }

    // Same calculation logic as personal, but with group-aggregated data
    // ...
}
```

**TransactionRepository — new group query methods:**
```swift
// Add to TransactionRepository:

/// Fetch all transactions for a group (all members, no userId filter)
func fetchTransactionsForGroup(groupId: String) -> [Transaction] {
    // SELECT * FROM Transactions WHERE shared_group_id = ? AND is_deleted = 0
}

/// Fetch transactions for a statement across all users (shared card)
func fetchTransactionsForStatement(statementId: Int, includeAllUsers: Bool) -> [Transaction] {
    if includeAllUsers {
        // SELECT * FROM Transactions WHERE statement_id = ? AND is_deleted = 0
        // (no userId filter)
    } else {
        // existing behavior with userId filter
    }
}
```

**BudgetRepository — new group query methods:**
```swift
// Add to BudgetRepository:

func fetchBudgetsForGroup(groupId: String) -> [BudgetModel] {
    // SELECT * FROM Budgets WHERE shared_group_id = ?
}
```

**BudgetAllocationService — group-aware usedAmount:**
```swift
// Modify usedAmount calculation:

func calculateUsedAmount(
    for allocation: BudgetAllocation,
    groupId: String? = nil
) -> Int {
    if let groupId = groupId {
        // Sum ALL members' transactions for this category in this month
        let transactions = transactionRepo.fetchTransactionsForGroup(groupId: groupId)
        return transactions
            .filter { $0.category == allocation.category && $0.budgetMonthDate == allocation.monthDate }
            .reduce(0) { $0 + $1.amount }
    } else {
        // Existing personal calculation
    }
}
```

**CreditCardRepository — new group query methods:**
```swift
// Add to CreditCardRepository:

/// Share a card with a group
func shareCard(cardId: Int, withGroupId groupId: String) {
    // UPDATE CreditCards SET shared_group_id = ? WHERE id = ?
}

/// Unshare a card
func unshareCard(cardId: Int) {
    // UPDATE CreditCards SET shared_group_id = NULL WHERE id = ?
}

/// Fetch all cards shared with a group
func fetchCardsForGroup(groupId: String) -> [CreditCard] {
    // SELECT * FROM CreditCards WHERE shared_group_id = ? AND is_deleted = 0
}
```

### 10.0b — Share Card UI in Group Details (BUILD checkpoint)

Add a "Shared Cards" section to GroupDetailsView showing which credit cards
the owner has shared with the group. Owner can tap "Share a Card" to pick
from their personal cards.

```swift
// In GroupDetailsView, add after Members section:

// Shared Cards section header
private let sharedCardsHeaderView = createSectionHeader(title: "groupDetails.sharedCards.title".localized)

// Shared cards table (reuse CreditCardCell pattern)
let sharedCardsTableView: UITableView = {
    let table = UITableView(frame: .zero, style: .plain)
    table.backgroundColor = .clear
    table.separatorStyle = .none
    table.translatesAutoresizingMaskIntoConstraints = false
    return table
}()

// "Share a Card" button (only visible to owner)
private let shareCardButton: UIButton = { /* ... "+ Share a Card" with person.3 icon */ }()
```

When owner taps "Share a Card":
1. Show action sheet listing their personal (unshared) credit cards
2. On selection, call `CreditCardRepository().shareCard(cardId:withGroupId:)`
3. Card appears in the Shared Cards section
4. CloudKit pushes the card + its statements to the group's shared zone
5. Other members receive the card data on next sync

**BUILD**: In Group Details, see "Shared Cards" section. Owner taps "Share a Card" →
picks a card → card appears in the section with brand icon and last 4 digits.

### 10.0c — "Move to Group / Move to Personal" in Transaction Details (BUILD checkpoint)

Users need a way to reassign an existing transaction between personal and group contexts.
This is accessed from the Transaction Details screen.

```swift
// Add to TransactionDetailsView — new action row:

private let moveToGroupContainer: UIView = {
    let container = UIView()
    container.backgroundColor = Colors.gray100
    container.layer.cornerRadius = CornerRadius.large
    container.isUserInteractionEnabled = true
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
}()

private let moveToGroupIcon: UIImageView = {
    let iv = UIImageView()
    iv.image = UIImage(systemName: "arrow.right.arrow.left")
    iv.tintColor = Colors.gray600
    iv.contentMode = .scaleAspectFit
    iv.translatesAutoresizingMaskIntoConstraints = false
    return iv
}()

private let moveToGroupLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.titleSM.font
    label.textColor = Colors.gray700
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}()
```

Logic:
- If transaction is personal (`shared_group_id = NULL`):
  - Show "Move to Group" → action sheet lists available groups
  - On selection: `UPDATE Transactions SET shared_group_id = ? WHERE id = ?`
  - Push to CloudKit shared zone, log group activity
- If transaction is in a group:
  - Show "Move to Personal" → confirmation alert
  - On confirm: `UPDATE Transactions SET shared_group_id = NULL WHERE id = ?`
  - Remove from shared zone, keep in private zone

```swift
// TransactionDetailsViewModel:

func moveTransactionToGroup(_ groupId: String) {
    guard let txId = transaction.id else { return }
    transactionRepo.updateSharedGroupId(transactionId: txId, groupId: groupId)

    GroupNotificationService.shared.logActivity(
        action: .transactionCreated,
        groupId: groupId,
        detail: transaction.title
    )
}

func moveTransactionToPersonal() {
    guard let txId = transaction.id else { return }
    if let groupId = transaction.sharedGroupId {
        GroupNotificationService.shared.logActivity(
            action: .transactionDeleted,
            groupId: groupId,
            detail: transaction.title
        )
    }
    transactionRepo.updateSharedGroupId(transactionId: txId, groupId: nil)
}
```

**BUILD**: Open a personal transaction → see "Move to Group" row → tap → pick group →
transaction disappears from personal view, appears in group view. And vice-versa.

### 10.1 — Guard Existing Actions with Permission Checks

Wrap existing actions in permission checks when operating within a shared group context:

**AddTransactionModalViewModel:**
```swift
func canAddTransaction(in group: BudgetGroup?) -> Bool {
    guard let group = group else { return true } // Personal = always allowed
    return BudgetGroupService.shared.currentUserCan(\.canCreateTransactions, in: group)
}
```

**TransactionDetailsViewModel:**
```swift
func canEditTransaction(in group: BudgetGroup?) -> Bool {
    guard let group = group else { return true }
    return BudgetGroupService.shared.currentUserCan(\.canEditTransactions, in: group)
}

func canDeleteTransaction(in group: BudgetGroup?) -> Bool {
    guard let group = group else { return true }
    return BudgetGroupService.shared.currentUserCan(\.canDeleteTransactions, in: group)
}
```

Disable buttons / show "No Permission" state when permission is denied.

**BUILD checkpoint 1**: Join a group with limited permissions. Verify disabled UI states (grayed out delete button, hidden edit option).

### 10.2 — Log Group Activities on Existing Actions

Hook into existing repositories to post group activity when data changes in a shared context:

```swift
// In TransactionRepository, after successful insert:
if let groupId = transaction.sharedGroupId {
    GroupNotificationService.shared.logActivity(
        action: .transactionCreated,
        groupId: groupId,
        detail: transaction.title
    )
}
```

Same pattern for edit, delete on transactions, budgets, allocations.

**BUILD checkpoint 2**: Create a transaction in a shared group → other group members receive notification.

---

## PHASE 11: Dashboard Group Context & Data Context Switching
**Estimated scope: UI-focused — 3 build checkpoints**

### 11.1 — Group Switcher on Dashboard Header (BUILD checkpoint 1)

Add a small pill/chip below the welcome subtitle showing current context.
This replaces the static `welcomeSubtitleLabel` area when groups exist.

```swift
// In DashboardView, add:
let groupContextChip: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.mainMagenta.withAlphaComponent(0.1)
    view.layer.cornerRadius = CornerRadius.medium
    view.clipsToBounds = true
    view.isUserInteractionEnabled = true
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()

private let groupContextIcon: UIImageView = {
    let iv = UIImageView()
    iv.image = UIImage(systemName: "person.crop.circle")
    iv.tintColor = Colors.mainMagenta
    iv.contentMode = .scaleAspectFit
    iv.translatesAutoresizingMaskIntoConstraints = false
    return iv
}()

let groupContextLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.mainMagenta
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}()

private let groupContextChevron: UIImageView = {
    let iv = UIImageView()
    iv.image = UIImage(systemName: "chevron.down")
    iv.tintColor = Colors.mainMagenta
    iv.contentMode = .scaleAspectFit
    iv.translatesAutoresizingMaskIntoConstraints = false
    return iv
}()
```

Layout: chip sits where `welcomeSubtitleLabel` is. When user has no groups,
the subtitle stays as-is ("Here are your finances"). When user has at least
one group, it becomes the context chip.

```swift
func configureContextChip(currentContext: DataContext) {
    switch currentContext {
    case .personal:
        groupContextIcon.image = UIImage(systemName: "person.crop.circle")
        groupContextLabel.text = "dashboard.context.personal".localized
    case .group(let group):
        groupContextIcon.image = UIImage(systemName: "person.3.fill")
        groupContextLabel.text = group.name
    }
}
```

Tap opens an action sheet:
```
┌────────────────────────┐
│   Switch Context       │
├────────────────────────┤
│ ● Personal             │  ← checkmark on current
│   Family Budget        │
│   Roommates            │
├────────────────────────┤
│   Cancel               │
└────────────────────────┘
```

**BUILD**: See context chip on dashboard. Tap → action sheet with Personal + group names.

### 11.2 — DataContext Model & ViewModel Integration (BUILD checkpoint 2)

```swift
// Finova/Sources/Core/Models/DataContext.swift

enum DataContext: Equatable {
    case personal
    case group(BudgetGroup)

    var groupId: String? {
        switch self {
        case .personal: return nil
        case .group(let group): return group.id
        }
    }

    var displayName: String {
        switch self {
        case .personal: return "dashboard.context.personal".localized
        case .group(let group): return group.name
        }
    }
}
```

Update `DashboardViewModel` to hold and filter by context:

```swift
// Add to DashboardViewModel:

/// Current viewing context — defaults to personal
var currentContext: DataContext = .personal

func loadMonthlyCards() -> [MonthBudgetCardType] {
    switch currentContext {
    case .personal:
        // Existing logic — fetches transactions WHERE shared_group_id IS NULL
        return transactionLedger.calculateMonthlyData(for: monthRange)
    case .group(let group):
        // Group-aware — fetches ALL members' transactions for this group
        return transactionLedger.calculateMonthlyDataForGroup(
            groupId: group.id, for: monthRange
        )
    }
}

func switchContext(to context: DataContext) {
    currentContext = context
    onDataNeedsRefresh?()
}
```

**Key filter changes in repositories:**
```swift
// TransactionRepository:
func fetchAllTransactions() now adds:
//   WHERE shared_group_id IS NULL  (personal context)
// New: fetchTransactionsForGroup(groupId:) adds:
//   WHERE shared_group_id = ?      (group context)

// BudgetRepository:
func fetchBudgets() now adds:
//   WHERE shared_group_id IS NULL  (personal)
// New: fetchBudgetsForGroup(groupId:)

// CreditCardRepository:
func fetchAllCards() now adds:
//   WHERE shared_group_id IS NULL  (personal cards)
// fetchCardsForGroup(groupId:) fetches shared cards
```

**BUILD**: Switch to group context → dashboard reloads with group data.
Switch back to personal → original data appears unchanged.

### 11.3 — Context-Aware Transaction Creation (BUILD checkpoint 3)

When user taps "+" to add a transaction, the current context determines
where the transaction goes:

```swift
// AddTransactionModalViewModel — add context:

var activeContext: DataContext = .personal

func addTransaction(
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    isRecurring: Bool? = nil,
    creditCardId: Int? = nil
) -> Result<Void, Error> {
    // ... existing validation ...

    let model = TransactionModel(
        title: title,
        category: categoryKey,
        amount: amount,
        type: typeRaw,
        dateTimestamp: timestamp,
        budgetMonthDate: monthAnchor,
        isRecurring: isRecurring,
        creditCardId: creditCardId
    )

    // Insert with group context
    transactionRepo.insertTransaction(model, sharedGroupId: activeContext.groupId)

    // If in group context, log activity for notifications
    if let groupId = activeContext.groupId {
        GroupNotificationService.shared.logActivity(
            action: .transactionCreated,
            groupId: groupId,
            detail: title
        )
    }

    return .success(())
}
```

The "+" button creates a transaction in whatever context the dashboard is showing.
The Add Transaction modal shows a small context indicator at the top:
- Personal context: no extra indicator (default behavior, no clutter)
- Group context: small banner `"Adding to: Family Budget"` with group icon

**Payment method in group context:**
When in a group context, the credit card picker shows:
- Shared cards from the group (the ones the owner shared)
- NOT the user's personal cards (unless also shared)

```swift
func availableCreditCards(for context: DataContext) -> [CreditCard] {
    switch context {
    case .personal:
        return creditCardRepo.fetchAllCards() // personal cards
    case .group(let group):
        return creditCardRepo.fetchCardsForGroup(groupId: group.id) // shared cards only
    }
}
```

**BUILD**: While in group context, tap "+". See "Adding to: Family Budget" banner.
Credit card picker shows only shared cards. Save → transaction appears in group view.
Switch to personal → the new transaction is NOT visible (it's in the group).

---

## PHASE 12: Sync Trigger Points & Polish
**Estimated scope: Logic + polish — 2 build checkpoints**

### 12.1 — Automatic Sync Triggers

Add sync triggers to:
- App launch (in `SplashViewController.decideNavigationFlow()`)
- App foreground (in `SceneDelegate.sceneWillEnterForeground()`)
- Pull-to-refresh on Dashboard
- After any local data mutation

```swift
// SceneDelegate.swift, in sceneWillEnterForeground:
SyncEngine.shared.performFullSync()
```

### 12.2 — Error Handling & Retry

```swift
// Finova/Sources/Core/CloudKit/CloudKitErrorHandler.swift

final class CloudKitErrorHandler {
    static func shouldRetry(_ error: Error) -> (Bool, TimeInterval?) {
        guard let ckError = error as? CKError else { return (false, nil) }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return (true, 5.0)
        case .serviceUnavailable, .requestRateLimited:
            let retryAfter = ckError.retryAfterSeconds ?? 10.0
            return (true, retryAfter)
        case .zoneBusy:
            return (true, 3.0)
        case .quotaExceeded:
            return (false, nil) // User needs to free iCloud space
        default:
            return (false, nil)
        }
    }
}
```

**BUILD**: Turn airplane mode on → see "Offline" indicator. Turn off → watch sync indicator cycle to "Synced".

---

## Localization Keys

Add to `Localizable.strings`:

```
// Sync
"sync.status.idle" = "iCloud";
"sync.status.syncing" = "Syncing...";
"sync.status.synced" = "Synced";
"sync.status.error" = "Sync Error";
"sync.status.offline" = "Offline";

// Settings
"settings.section.sharing" = "Sharing";
"settings.budgetGroups.title" = "Budget Groups";
"settings.sync.title" = "iCloud Sync";

// Budget Groups
"budgetGroups.header.title" = "Budget Groups";
"budgetGroups.empty.title" = "No Groups Yet";
"budgetGroups.empty.subtitle" = "Create a group to share your finances with family or partners.";
"budgetGroups.cell.memberCount" = "%d members";
"budgetGroups.create.title" = "New Group";
"budgetGroups.create.namePlaceholder" = "Group name";

// Group Details
"groupDetails.header.title" = "Group Details";
"groupDetails.members.title" = "Members";
"groupDetails.invite.button" = "Invite";
"groupDetails.leave.button" = "Leave Group";
"groupDetails.delete.button" = "Delete Group";
"groupDetails.leave.confirm" = "Are you sure you want to leave this group?";
"groupDetails.delete.confirm" = "This will remove all members and delete the group permanently.";
"groupDetails.sharedCards.title" = "Shared Cards";
"groupDetails.sharedCards.share" = "Share a Card";
"groupDetails.sharedCards.unshare" = "Unshare";
"groupDetails.sharedCards.empty" = "No cards shared with this group yet.";
"groupDetails.currency.title" = "Group Currency";

// Sharing Roles
"sharing.role.owner" = "Owner";
"sharing.role.member" = "Member";
"sharing.member.activeNow" = "Active now";
"sharing.member.activeMinutesAgo" = "Active %d min ago";
"sharing.member.activeHoursAgo" = "Active %dh ago";
"sharing.member.activeDaysAgo" = "Active %dd ago";
"sharing.member.neverActive" = "Never active";

// Permissions
"permission.createTransactions" = "Create Transactions";
"permission.editTransactions" = "Edit Transactions";
"permission.deleteTransactions" = "Delete Transactions";
"permission.editBudgets" = "Edit Budgets";
"permission.editAllocations" = "Edit Allocations";
"permission.viewCreditCards" = "View Credit Cards";
"permission.manageCreditCards" = "Manage Credit Cards";
"permission.inviteMembers" = "Invite Members";

// Invite
"invite.header.title" = "Invite Member";
"invite.email.placeholder" = "Email address";
"invite.preset.viewOnly" = "View Only";
"invite.preset.canAdd" = "Can Add";
"invite.preset.fullAccess" = "Full Access";
"invite.preset.custom" = "Custom";
"invite.send.button" = "Send Invitation";
"invite.success" = "Invitation sent!";

// Group Notifications
"notification.group.transactionCreated" = "Created a transaction: %@";
"notification.group.transactionEdited" = "Edited a transaction: %@";
"notification.group.transactionDeleted" = "Deleted a transaction: %@";
"notification.group.budgetEdited" = "Updated the budget: %@";
"notification.group.memberJoined" = "%@ joined the group";
"notification.group.memberLeft" = "%@ left the group";

// Dashboard Context
"dashboard.context.personal" = "Personal";
"dashboard.context.switch" = "Switch Context";
"dashboard.context.addingTo" = "Adding to: %@";

// Transaction Details - Move
"transactionDetails.moveToGroup" = "Move to Group";
"transactionDetails.moveToPersonal" = "Move to Personal";
"transactionDetails.moveToGroup.confirm" = "This transaction will be visible to all group members.";
"transactionDetails.moveToPersonal.confirm" = "This transaction will be removed from the group and only visible to you.";

// Group Details (additional)
"groupDetails.info.header.title" = "Group Info";
"groupDetails.name.label" = "Name";
"groupDetails.owner.label" = "Owner";
"groupDetails.created.label" = "Created";
"groupDetails.dangerZone.title" = "Danger Zone";
"groupDetails.rename.title" = "Rename Group";

// Common
"common.cancel" = "Cancel";
"common.save" = "Save";

// Invite (additional)
"invite.email.section" = "Member email";
"invite.preset.section" = "Permission level";
"invite.error.emptyEmail" = "Please enter an email address.";

// Permissions
"permissions.header.title" = "Permissions";
"permissions.section.transactions" = "Transactions";
"permissions.section.budgets" = "Budgets";
"permissions.section.creditCards" = "Credit Cards";
"permissions.section.group" = "Group";
"permissions.removeMember.button" = "Remove Member";
"permissions.removeMember.confirm.title" = "Remove Member";
"permissions.removeMember.confirm.message" = "Are you sure you want to remove %@ from this group?";

// Group Invitation
"invitation.header.title" = "Group Invitation";
"invitation.card.header" = "Invitation Details";
"invitation.invitedBy" = "Invited by %@";
"invitation.permissions.title" = "You will be able to:";
"invitation.permissions.viewOnly" = "View group transactions and budgets";
"invitation.accept.button" = "Accept Invitation";
"invitation.decline.button" = "Decline";

// Errors
"sharing.error.onlyOwnerCanDelete" = "Only the group owner can delete this group.";
"sharing.error.noPermission" = "You don't have permission to do this.";
```

---

## Summary of Build Checkpoints (30 total)

| Phase | Checkpoint | What You See |
|-------|-----------|--------------|
| 1 | — | CloudKit infrastructure compiles, zone visible in CK Dashboard |
| 2.1 | 1 | SyncStatusIndicator component renders with all states |
| 2.2 | 2 | Dashboard header shows cloud sync status |
| 2.3 | 3 | Settings has new "Sharing" section with 2 rows |
| 4.1 | 4 | Budget Groups empty state screen |
| 4.2 | 5 | Group cells with name, count, chevron |
| 4.3 | 6 | Overlapping avatar initials in cells |
| 4.4 | 7 | Full groups list with real data |
| 5.1 | 8 | Group Details header and back navigation |
| 5.2 | 9 | Member list with roles and last active |
| 5.3 | 10 | MemberBadge and PermissionToggleRow components |
| 5.4 | 11 | Leave/Delete/Rename group actions |
| 6.1 | 12 | Invite modal with email input and presets |
| 6.2 | 13 | Custom permissions expandable toggles |
| 6.3 | 14 | Send invitation end-to-end |
| 7.1 | 15 | Member permissions screen with all toggles |
| 7.2 | 16 | Save permissions + remove member |
| 8.1 | 17 | Invitation received card UI |
| 8.2 | 18 | Accept/decline invitation flow |
| 9 | 19-20 | Push notifications for group actions |
| 10.0 | 21 | Group-aware services (ledger, statements, allocations) compile |
| 10.0b | 22 | Shared Cards section in Group Details |
| 10.0c | 23 | "Move to Group / Move to Personal" in Transaction Details |
| 10.1-2 | 24-25 | Permission guards + activity logging in existing flows |
| 11.1 | 26 | Group context switcher chip on dashboard |
| 11.2 | 27 | Dashboard filters data by context |
| 11.3 | 28 | Context-aware transaction creation (+ card picker) |
| 12 | 29-30 | Auto-sync triggers + offline/retry handling |

---

## Testing Checklist

### Group Lifecycle
- [ ] Create group → appears in list → syncs to CloudKit
- [ ] Invite member by email → they receive CKShare invitation
- [ ] Accept invitation → group appears in invitee's list
- [ ] Leave group → group disappears from member's list
- [ ] Delete group (owner) → all members lose access

### Permissions
- [ ] Member with `canCreateTransactions=false` sees disabled Add button
- [ ] Member with `canViewCreditCards=false` does NOT see shared cards
- [ ] Member with `canEditBudgets=false` cannot modify group budget
- [ ] Owner always has full access regardless of permission flags

### Shared Credit Cards
- [ ] Owner shares a card → member sees it after sync
- [ ] Member adds transaction to shared card → statement total updates for BOTH users
- [ ] Statement total reflects ALL members' charges, not just one user's
- [ ] Owner unshares a card → member no longer sees it
- [ ] Shared card's recurring transactions generate instances visible to all members
- [ ] Installment transaction on shared card: all 12 installments visible to all members

### Shared Budgets & Allocations
- [ ] Group budget reflects ALL members' spending in the group context
- [ ] Budget allocation `usedAmount` sums ALL members' transactions in that category
- [ ] Allocation status (underBudget/nearLimit/overBudget) uses combined spending

### Sync & Conflict
- [ ] App on iPhone creates data → same account on iPad sees it after sync
- [ ] Create transaction in group → other member sees notification
- [ ] Delete transaction → syncs to other devices within seconds
- [ ] Airplane mode → "Offline" indicator → reconnect → auto-sync
- [ ] Conflict: edit same transaction on 2 devices → last-writer-wins resolves
- [ ] Background push → app wakes, fetches changes, updates UI

### Data Isolation & Context Switching
- [ ] Existing user with 200 transactions joins group → all 200 stay personal, untouched
- [ ] Switch to group context → dashboard shows ONLY group's shared data
- [ ] Switch back to personal → all original personal data appears, no group data leaks in
- [ ] Create transaction in group context → does NOT appear in personal view
- [ ] Create transaction in personal context → does NOT appear in group view
- [ ] "Move to Group" on personal transaction → disappears from personal, appears in group
- [ ] "Move to Personal" on group transaction → disappears from group, appears in personal
- [ ] User in 2 groups → switching between them shows correct isolated data
- [ ] User leaves a group → personal data completely unaffected
- [ ] Credit card picker in group context shows only shared cards, not personal cards
- [ ] Group currency is enforced — amounts display in group's currency

### Notifications
- [ ] Member creates transaction → all OTHER members get push notification
- [ ] Own actions do NOT generate notifications for yourself
- [ ] Notification tap navigates to the relevant transaction/screen
