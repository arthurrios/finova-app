# Budget Allocation Feature - Implementation Guide

## FinoVa v1.4.0

This guide follows a **visual-first development approach** - you'll see components on screen as you build them, starting with scaffolding and progressively adding functionality.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Programming Concepts Explained](#3-programming-concepts-explained) ⭐ *Start here if you're new to Swift*
4. [Phase 1: Scaffolding & Navigation](#phase-1-scaffolding--navigation)
5. [Phase 2: Data Models & Constants](#phase-2-data-models--constants)
6. [Phase 3: UI Components with Mock Data](#phase-3-ui-components-with-mock-data)
7. [Phase 4: Data Layer (Repository & Service)](#phase-4-data-layer-repository--service)
8. [Phase 5: Connect Data to UI](#phase-5-connect-data-to-ui)
9. [Phase 6: Modal & Creation Flow](#phase-6-modal--creation-flow)
10. [Phase 7: Polish & Edge Cases](#phase-7-polish--edge-cases)
11. [Testing Checklist](#testing-checklist)
12. [Localization Keys](#localization-keys)
13. [Quick Reference: Swift Concepts](#quick-reference-swift-concepts-used-in-this-guide)
14. [Further Learning](#further-learning)

---

## 1. Overview

### Feature Summary

The Budget Allocation feature extends the existing budget system to allow users to:
- Partition their main monthly budget into category-based allocations
- Track spending against each allocation with visual indicators
- View budget breakdowns via an interactive donut chart
- Create recurring allocations that apply to future months
- Filter transactions by tapping allocation chart segments
- View allocation details and edit/delete allocations

### Key Terminology

| Term | Description |
|------|-------------|
| **Budget** | The main monthly spending limit (existing) |
| **Allocation** | A portion of the budget assigned to a specific category |
| **Unallocated** | Budget amount not assigned to any allocation |
| **Ceiling** | The allocated amount for a category |
| **Usage** | Actual spending in a category for a month |

### Design Decisions

- **Category-only**: Allocations are tied to `TransactionCategory` enum values only
- **Soft validation**: Sum of allocations can exceed budget (warning shown)
- **Unallocated tracking**: Expenses in categories without allocations are tracked separately
- **Lazy generation**: Recurring allocations use lazy generation (same as transactions)

---

## 2. Architecture

### File Structure

```
Finova/Sources/
├── Core/
│   ├── Constants/
│   │   └── Colors.swift                             # Add warningAmber color
│   ├── Models/
│   │   └── Enums/
│   │       └── AllocationStatus.swift               # New enum
│   ├── Repositories/
│   │   └── BudgetAllocationRepository/
│   │       ├── BudgetAllocationModel.swift
│   │       └── BudgetAllocationRepository.swift
│   └── Services/
│       └── BudgetAllocationService.swift
├── Scenes/
│   ├── Dashboard/
│   │   ├── DashboardViewModel.swift                 # Add allocation methods
│   │   └── DashboardCarousel/
│   │       └── MonthCarousel/
│   │           ├── MonthCardFlipDelegate.swift      # New protocol
│   │           ├── MonthCarouselCell.swift          # Add flip logic
│   │           ├── MonthBudgetCard/
│   │           │   └── MonthBudgetCard.swift        # Add flip toggle
│   │           └── BudgetCard/
│   │               ├── BudgetCard.swift
│   │               └── AllocationCell.swift
│   ├── BudgetAllocationDetails/
│   │   ├── View/
│   │   │   ├── BudgetAllocationDetailsViewController.swift
│   │   │   ├── BudgetAllocationDetailsView.swift
│   │   │   └── BudgetAllocationDetailsFlowDelegate.swift
│   │   ├── ViewModel/
│   │   │   └── BudgetAllocationDetailsViewModel.swift
│   │   └── Components/
│   │       └── CircularProgressView.swift
│   └── AddTransaction/
│       ├── AddTransactionModalView.swift            # Add segmented control
│       └── AddTransactionModalViewModel.swift       # Add allocation mode
└── SwiftUI/
    └── Charts/
        └── BudgetDonutChartView.swift
```

---

## 3. Programming Concepts Explained

This section explains Swift fundamentals and iOS patterns for new developers. **Read this entire section before implementing** - it will make the code much easier to understand.

---

### 3.0 Swift Fundamentals (Start Here!)

Before diving into iOS-specific patterns, let's cover the Swift basics you'll see everywhere.

#### 3.0.1 Variables: `let` vs `var`

```swift
let name = "Arthur"      // CONSTANT - cannot change
var age = 25             // VARIABLE - can change

name = "John"            // ❌ Error! Cannot assign to 'let'
age = 26                 // ✅ OK, 'var' can be changed
```

**Rule:** Always use `let` unless you need to change the value. This prevents bugs.

#### 3.0.2 Optionals: The `?` and `!` Symbols

**The Problem:** In many languages, any variable can be `null`, causing crashes.

**Swift's Solution:** Values that might be missing are marked with `?` (optional).

```swift
var budgetLimit: Int = 100       // ALWAYS has a value
var nickname: String? = nil      // MIGHT have a value (optional)

// You can't use an optional directly:
print(nickname.count)            // ❌ Error! nickname might be nil

// You must UNWRAP it first:
if let name = nickname {         // "if let" unwraps safely
    print(name.count)            // ✅ Only runs if nickname has a value
}

// Or use optional chaining:
print(nickname?.count)           // ✅ Returns nil if nickname is nil

// Or provide a default:
print(nickname ?? "No nickname") // ✅ Uses "No nickname" if nil
```

**The `!` (Force Unwrap) - Use with caution!**
```swift
let value: String? = nil
print(value!)                    // 💥 CRASH! Force unwrapping nil

// Only use ! when you're 100% sure it's not nil:
let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!
// This is common because we KNOW the cell exists (we registered it)
```

#### 3.0.3 Structs vs Classes

Both can hold data and methods, but they behave differently:

```swift
// STRUCT - Value type (copied when assigned)
struct Point {
    var x: Int
    var y: Int
}

var point1 = Point(x: 0, y: 0)
var point2 = point1              // point2 is a COPY
point2.x = 10
print(point1.x)                  // Still 0! point1 wasn't affected

// CLASS - Reference type (shared when assigned)
class Person {
    var name: String
    init(name: String) { self.name = name }
}

var person1 = Person(name: "Arthur")
var person2 = person1            // person2 points to SAME object
person2.name = "John"
print(person1.name)              // "John"! Both changed!
```

**When to use which:**
- **Struct:** Data that should be copied (models, coordinates, settings)
- **Class:** Objects with identity that should be shared (ViewControllers, Services)

**In this project:**
- `BudgetAllocation` is a **struct** (just data)
- `BudgetAllocationService` is a **class** (shared service)
- `BudgetCard` is a **class** (inherits from UIView)

#### 3.0.4 Enums (Enumerations)

Enums define a type with a fixed set of possible values:

```swift
enum AllocationStatus {
    case underBudget     // One possible value
    case nearLimit       // Another possible value
    case overBudget      // Another possible value
}

let status: AllocationStatus = .underBudget

// Using switch (must cover ALL cases)
switch status {
case .underBudget:
    print("You're doing great!")
case .nearLimit:
    print("Getting close...")
case .overBudget:
    print("Over budget!")
}
```

**Enums can have associated data:**
```swift
enum Result {
    case success(data: [BudgetAllocation])
    case failure(error: Error)
}
```

**Enums can have computed properties:**
```swift
enum AllocationStatus {
    case underBudget, nearLimit, overBudget

    var color: UIColor {
        switch self {
        case .underBudget: return .green
        case .nearLimit: return .orange
        case .overBudget: return .red
        }
    }
}

// Usage:
let status = AllocationStatus.overBudget
view.backgroundColor = status.color  // Returns red
```

#### 3.0.5 Closures (Blocks of Code)

A closure is a block of code you can store in a variable or pass to a function:

```swift
// Simple closure stored in a variable
let greet = { (name: String) -> String in
    return "Hello, \(name)!"
}
print(greet("Arthur"))  // "Hello, Arthur!"

// Closure passed to a function
let numbers = [3, 1, 4, 1, 5]
let sorted = numbers.sorted { (a, b) -> Bool in
    return a < b
}
// Shorthand (Swift infers types):
let sorted = numbers.sorted { $0 < $1 }
```

**Trailing closure syntax:**
```swift
// When closure is the last parameter, you can put it outside:
UIView.animate(withDuration: 0.3) {
    self.view.alpha = 0
}
// Instead of:
UIView.animate(withDuration: 0.3, animations: { self.view.alpha = 0 })
```

#### 3.0.6 What is `Codable`?

`Codable` lets Swift automatically convert objects to/from JSON or other formats.

```swift
// WITHOUT Codable - Manual and error-prone
func saveToDatabase(allocation: BudgetAllocation) {
    let data: [String: Any] = [
        "id": allocation.id ?? 0,
        "monthDate": allocation.monthDate,
        "categoryKey": allocation.category.key,
        // ... manually convert every property
    ]
}

// WITH Codable - Automatic!
struct BudgetAllocationModel: Codable {
    let id: Int?
    let monthDate: Int
    let categoryKey: String
    let allocatedAmount: Int
}

// Swift automatically knows how to:
let encoder = JSONEncoder()
let data = try encoder.encode(allocation)  // Object → JSON data

let decoder = JSONDecoder()
let allocation = try decoder.decode(BudgetAllocationModel.self, from: data)  // JSON → Object
```

**Why we use it:**
- Database libraries (like SQLite.swift) use Codable to save/load data
- API responses are JSON, and Codable parses them automatically
- No manual conversion = fewer bugs

**Important:** Property names must match the JSON keys exactly, or use `CodingKeys`:
```swift
struct User: Codable {
    let firstName: String

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"  // JSON uses snake_case
    }
}
```

#### 3.0.7 Type Aliases

Type aliases create a new name for an existing type:

```swift
typealias MonthAnchor = Int      // MonthAnchor is just an Int
typealias Completion = (Result<Void, Error>) -> Void

// Makes code more readable:
func deleteAllocation(completion: Completion) { ... }
// Instead of:
func deleteAllocation(completion: (Result<Void, Error>) -> Void) { ... }
```

---

### 3.1 Why Protocols? (Delegates & Communication)

**The Problem:** How does a child view tell its parent that something happened (like a button tap)?

**The Solution:** Protocols define a "contract" - a list of methods that someone promises to implement.

```swift
// This is a PROTOCOL - it's like a job description
// Anyone who "conforms" to this protocol MUST implement these methods
protocol MonthCardFlipDelegate: AnyObject {
    func didRequestFlip(isShowingBudgetView: Bool)
    func didSelectAllocationCategory(_ category: TransactionCategory)
    func didTapAllocation(_ allocation: BudgetAllocation)
}
```

**Why `AnyObject`?** This restricts the protocol to classes only (not structs). We need this because we'll use `weak` references to avoid memory leaks (explained below).

**How it works:**

```swift
// BudgetCard has a delegate property
class BudgetCard: UIView {
    weak var delegate: MonthCardFlipDelegate?  // Someone who will respond to events

    @objc private func flipBack() {
        // When button is tapped, TELL the delegate (don't do the work yourself)
        delegate?.didRequestFlip(isShowingBudgetView: false)
    }
}

// MonthCarouselCell CONFORMS to the protocol (promises to do the job)
extension MonthCarouselCell: MonthCardFlipDelegate {
    func didRequestFlip(isShowingBudgetView: Bool) {
        // Actually do the flip animation here
        if isShowingBudgetView {
            flipToBudgetView()
        } else {
            flipToTransactionView()
        }
    }
}

// Connect them
budgetCard.delegate = self  // "self" is MonthCarouselCell
```

**Why not just call the method directly?**
- BudgetCard doesn't know (and shouldn't know) about MonthCarouselCell
- This makes BudgetCard reusable - anyone can be its delegate
- It's like a waiter (BudgetCard) taking your order and giving it to the kitchen (delegate), without knowing who's cooking

### 3.2 Why `weak var delegate`? (Memory Management)

**The Problem:** Memory leaks. Objects stay in memory forever because they reference each other.

```swift
// BAD - Creates a "retain cycle" (memory leak)
class Parent {
    var child: Child?  // Parent holds Child
}

class Child {
    var parent: Parent?  // Child holds Parent
}
// Neither can be freed from memory because each holds the other!
```

**The Solution:** Make one reference `weak`:

```swift
class Child {
    weak var parent: Parent?  // Child has a WEAK reference to Parent
}
// Now when Parent is freed, Child's reference becomes nil automatically
```

**Rule of thumb:** Delegates are always `weak` because:
- The parent (MonthCarouselCell) owns the child (BudgetCard)
- The child should NOT own the parent
- `weak` means "I know about you, but I don't keep you alive"

### 3.3 Why `lazy var`? (Deferred Initialization)

**The Problem:** Creating UI components in `init()` can be:
1. Slow (you create everything upfront)
2. Problematic (you might need `self` which isn't available yet)

**The Solution:** `lazy var` delays creation until first use:

```swift
// This closure runs ONLY when backButton is first accessed
private lazy var backButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
    button.tintColor = Colors.gray100
    button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    return button
}()  // <-- The () at the end means "execute this closure"
```

**Why the closure `{ }()` syntax?**
- The `{ ... }` is a closure (a block of code)
- The `()` at the end immediately executes it
- This lets you write multiple lines of setup code
- Without the closure, you'd only be able to write: `lazy var button = UIButton()`

**When is it created?**
```swift
// backButton doesn't exist yet...
addSubview(backButton)  // NOW it's created (first access)
// From now on, it's a regular property
```

### 3.4 Why `static func mock()`? (Factory Methods)

**The Problem:** During development, you need fake data to test the UI before the database is ready.

**The Solution:** A `static` method that creates sample instances:

```swift
struct BudgetAllocation {
    // Regular properties...
    let category: TransactionCategory
    let allocatedAmount: Int

    // STATIC method - belongs to the TYPE, not an instance
    static func mock(
        category: TransactionCategory = .meals,
        allocated: Int = 50000
    ) -> BudgetAllocation {
        return BudgetAllocation(
            category: category,
            allocatedAmount: allocated
        )
    }
}
```

**Why `static`?**
- You call it on the TYPE: `BudgetAllocation.mock()`
- Not on an instance: `someAllocation.mock()` ❌
- You don't need an existing allocation to create a mock one
- It's like a "factory" that produces new allocations

**Why default parameter values?**
```swift
// All of these work:
BudgetAllocation.mock()                           // Uses all defaults
BudgetAllocation.mock(category: .transportation)       // Override one
BudgetAllocation.mock(allocated: 100000)          // Override another
BudgetAllocation.mock(category: .meals, allocated: 25000)  // Override both
```

### 3.5 Why Computed Properties vs Stored Properties?

**Stored Property:** Holds a value in memory

```swift
var usedAmount: Int = 0  // This value is stored
```

**Computed Property:** Calculates a value every time you access it

```swift
var remainingAmount: Int {
    return allocatedAmount - usedAmount  // Calculated on-the-fly
}

var status: AllocationStatus {
    let percentage = usagePercentage
    if percentage > 100 { return .overBudget }
    else if percentage >= 80 { return .nearLimit }
    else { return .underBudget }
}
```

**Why use computed properties?**
- The value depends on other values that might change
- You don't want stale data (if `usedAmount` changes, `remainingAmount` updates automatically)
- No need to remember to update multiple properties

**When to use stored vs computed:**
- **Stored:** Data that comes from outside (database, user input)
- **Computed:** Data derived from other properties

### 3.6 Why Separate Repository and Service?

**Repository:** Talks to the database. Only knows how to save/load data.

```swift
class BudgetAllocationRepository {
    func insert(_ allocation: BudgetAllocationModel) throws -> Int
    func fetchAllocations(forMonth: Int) -> [BudgetAllocation]
    func delete(id: Int) throws
}
```

**Service:** Contains business logic. Uses repositories to get data, then does calculations.

```swift
class BudgetAllocationService {
    private let allocationRepo: BudgetAllocationRepository
    private let transactionRepo: TransactionRepository

    func getAllocationsWithUsage(forMonth: Int) -> [BudgetAllocation] {
        // 1. Get allocations from repo
        var allocations = allocationRepo.fetchAllocations(forMonth: monthAnchor)

        // 2. Get transactions and calculate usage (BUSINESS LOGIC)
        let usage = calculateUsageByCategory(forMonth: monthAnchor)

        // 3. Combine the data
        for i in allocations.indices {
            allocations[i].setUsedAmount(usage[allocations[i].category.key] ?? 0)
        }

        return allocations
    }
}
```

**Why separate them?**
- **Single Responsibility:** Each class does one thing well
- **Testability:** You can test business logic without a real database
- **Flexibility:** Change how data is stored without changing business logic

### 3.7 Why View / ViewModel / ViewController?

This is the **MVVM pattern** (Model-View-ViewModel):

```
┌─────────────┐     ┌─────────────────┐     ┌──────────────┐
│    View     │────▶│  ViewController │────▶│  ViewModel   │
│  (UIView)   │     │                 │     │              │
│             │◀────│   (connects     │◀────│  (data +     │
│  (displays  │     │    them)        │     │   logic)     │
│   things)   │     │                 │     │              │
└─────────────┘     └─────────────────┘     └──────────────┘
```

**View (`BudgetAllocationDetailsView`):**
- Only knows how to display things
- Has UI components (labels, buttons, tables)
- Doesn't know WHERE the data comes from

```swift
class BudgetAllocationDetailsView: UIView {
    private lazy var categoryLabel: UILabel = { ... }()

    func configure(with allocation: BudgetAllocation) {
        categoryLabel.text = allocation.category.displayName  // Just display it
    }
}
```

**ViewModel (`BudgetAllocationDetailsViewModel`):**
- Holds the data
- Contains logic (calculations, formatting)
- Doesn't know about UIKit

```swift
class BudgetAllocationDetailsViewModel {
    private let allocation: BudgetAllocation

    var formattedAllocated: String {
        return allocatedAmount.currencyString  // Format for display
    }

    var isOverBudget: Bool {
        return remainingAmount < 0  // Business logic
    }
}
```

**ViewController (`BudgetAllocationDetailsViewController`):**
- Connects View and ViewModel
- Handles user actions
- Manages lifecycle

```swift
class BudgetAllocationDetailsViewController: UIViewController {
    private let mainView = BudgetAllocationDetailsView()
    private let viewModel: BudgetAllocationDetailsViewModel

    override func viewDidLoad() {
        mainView.configure(with: viewModel.budgetAllocation)  // Connect them
    }

    @objc private func deleteTapped() {
        viewModel.deleteAllocation { result in ... }  // Handle action
    }
}
```

**Why this separation?**
- **View** can be reused with different data
- **ViewModel** can be tested without UI
- **ViewController** stays small and focused

### 3.8 Why Extensions?

Extensions add functionality to existing types, organized by purpose:

```swift
// Main class definition
class BudgetCard: UIView {
    // Core properties and setup
}

// Extension for UITableViewDataSource
extension BudgetCard: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allocations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // ...
    }
}

// Extension for UITableViewDelegate
extension BudgetCard: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}
```

**Why use extensions?**
- **Organization:** Group related methods together
- **Protocol Conformance:** Each protocol in its own extension
- **Readability:** Easy to find all `UITableViewDataSource` methods in one place
- **File size:** Can even split extensions into separate files

### 3.9 Why `private` vs `internal` vs `public`?

**Access control** determines who can see and use your code:

```swift
class BudgetCard: UIView {
    // PRIVATE: Only this class can access
    private var allocations: [BudgetAllocation] = []
    private lazy var monthLabel: UILabel = { ... }()

    // PRIVATE(SET): Anyone can read, only this class can write
    private(set) lazy var backButton: UIButton = { ... }()

    // INTERNAL (default): Anyone in the same module can access
    var delegate: MonthCardFlipDelegate?

    // PUBLIC: Anyone, even other modules, can access
    public func configure(...) { ... }
}
```

**Rule of thumb:**
- Start with `private` for everything
- Only make things less private when needed
- Properties that Views expose to ViewControllers: `private(set)` (read-only from outside)

### 3.10 Why `guard` vs `if`?

Both check conditions, but `guard` is for early exits:

```swift
// WITH IF (pyramid of doom)
func processAllocation() {
    if let id = allocation.id {
        if let amount = parsedAmount {
            if amount > 0 {
                // Finally do the work
                saveAllocation(id: id, amount: amount)
            }
        }
    }
}

// WITH GUARD (flat and clear)
func processAllocation() {
    guard let id = allocation.id else {
        print("No ID")
        return
    }

    guard let amount = parsedAmount else {
        print("Invalid amount")
        return
    }

    guard amount > 0 else {
        print("Amount must be positive")
        return
    }

    // Happy path - do the work
    saveAllocation(id: id, amount: amount)
}
```

**Why `guard`?**
- Makes the "happy path" clear (not nested)
- Unwrapped values (`id`, `amount`) are available after the guard
- Forces you to exit (return, throw, break) if condition fails

### 3.11 Why Closures for Callbacks?

**The Problem:** A function does something async (like a network call or animation), and you need to run code when it's done.

**The Solution:** Pass a closure (a block of code) to be executed later:

```swift
func deleteAllocation(completion: @escaping (Result<Void, Error>) -> Void) {
    // Do the deletion...

    if success {
        completion(.success(()))  // Call the closure with success
    } else {
        completion(.failure(error))  // Call the closure with error
    }
}

// Using it:
viewModel.deleteAllocation { result in
    switch result {
    case .success:
        self.flowDelegate?.didDeleteAllocation()
    case .failure(let error):
        self.showError(error.localizedDescription)
    }
}
```

**Why `@escaping`?**
- The closure will be called AFTER the function returns
- Swift needs to know to keep the closure in memory
- Without `@escaping`, the closure would be destroyed when the function ends

### 3.12 Why `[weak self]` in Closures?

**The Problem:** Closures capture `self`, creating a retain cycle (memory leak):

```swift
// BAD - Creates retain cycle
viewModel.deleteAllocation { result in
    self.showResult(result)  // Closure holds strong reference to self
}
```

**The Solution:** Capture `self` weakly:

```swift
// GOOD - No retain cycle
viewModel.deleteAllocation { [weak self] result in
    self?.showResult(result)  // self is optional now
}

// Even better - safely unwrap
viewModel.deleteAllocation { [weak self] result in
    guard let self = self else { return }
    self.showResult(result)
}
```

**When do you need `[weak self]`?**
- When the closure is stored (escaping)
- When it might outlive `self`
- Not needed for non-escaping closures (like `array.map { }`)

---

## Phase 1: Scaffolding & Navigation

> **Goal**: Create empty screens and wire up navigation so you can tap through the app flow.

### Step 1.1: Add Colors (Required for UI)

**File:** `Finova/Sources/Core/Constants/Colors.swift`

Add to existing Colors struct:

```swift
// Add after mainRed
static let warningAmber = UIColor(hex: "#F59E0B")
static let lowAmber = UIColor(hex: "#F59E0B").withAlphaComponent(0.05)
```

### Step 1.2: Create MonthCardFlipDelegate Protocol

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/MonthCardFlipDelegate.swift`

> **Why a protocol?** BudgetCard needs to tell its parent (MonthCarouselCell) when the user taps something, but BudgetCard shouldn't know about MonthCarouselCell directly. The protocol creates a "contract" - BudgetCard says "I need someone who can do these things" and MonthCarouselCell says "I can do those things."

```swift
import UIKit

// AnyObject = only classes can conform (needed for weak references)
// See Section 3.1 and 3.2 for detailed explanation
protocol MonthCardFlipDelegate: AnyObject {

    // Called when user taps the flip button
    // The Bool tells the delegate WHAT state to flip TO
    func didRequestFlip(isShowingBudgetView: Bool)

    // Called when user taps a segment in the donut chart
    // Passes the category so the delegate can filter transactions
    func didSelectAllocationCategory(_ category: TransactionCategory)

    // Called when user taps an allocation row
    // Passes the full allocation so the delegate can navigate to details
    func didTapAllocation(_ allocation: BudgetAllocation)
}
```

### Step 1.3: Create BudgetAllocationDetailsFlowDelegate Protocol

**File:** `Finova/Sources/Scenes/BudgetAllocationDetails/View/BudgetAllocationDetailsFlowDelegate.swift`

```swift
import UIKit

protocol BudgetAllocationDetailsFlowDelegate: AnyObject {
    func dismissAllocationDetails()
    func navigateToTransactionDetails(transaction: Transaction)
    func didUpdateAllocation()
    func didDeleteAllocation()
}
```

### Step 1.4: Create Minimal BudgetAllocation Model (for compilation)

**File:** `Finova/Sources/Core/Repositories/BudgetAllocationRepository/BudgetAllocationModel.swift`

> **Why create models first?** The UI components need to know what data they'll display. Even though we don't have real data yet, we need the model's "shape" (properties and types) so the code compiles. We add `mock()` methods to create fake data for testing the UI.

```swift
import UIKit

// MARK: - Allocation Status Enum
// ═══════════════════════════════════════════════════════════════════
// WHY AN ENUM? Status is one of three fixed options - perfect for enum.
// Enums prevent bugs like typos ("under_budget" vs "underBudget").
// Each case can have associated data (colors, labels) in one place.
// ═══════════════════════════════════════════════════════════════════

enum AllocationStatus {
    case underBudget    // 0-79% used
    case nearLimit      // 80-99% used
    case overBudget     // 100%+ used

    // COMPUTED PROPERTY: Returns a different color based on which case this is.
    // Why here and not in the View? Because the status OWNS its color.
    // Any view displaying this status should use the same color.
    var color: UIColor {
        switch self {
        case .underBudget: return Colors.mainMagenta
        case .nearLimit: return Colors.warningAmber
        case .overBudget: return Colors.mainRed
        }
    }

    var localizedLabel: String {
        switch self {
        case .underBudget: return "allocation.status.under".localized
        case .nearLimit: return "allocation.status.near".localized
        case .overBudget: return "allocation.status.over".localized
        }
    }
}

// MARK: - Display Model (minimal for scaffolding)
// ═══════════════════════════════════════════════════════════════════
// WHY A STRUCT (not class)?
// - Structs are VALUE TYPES: when you pass them, you get a copy
// - This prevents accidental modifications from other parts of the code
// - Rule of thumb: use struct unless you need inheritance or identity
// ═══════════════════════════════════════════════════════════════════

struct BudgetAllocation {
    // ─────────────────────────────────────────────────────────────
    // STORED PROPERTIES: These hold actual values in memory
    // ─────────────────────────────────────────────────────────────
    let id: Int?                      // Optional (?) because NEW allocations don't have IDs yet
    let monthDate: Int                // Unix timestamp for the month
    let category: TransactionCategory
    let allocatedAmount: Int          // In cents (5000 = $50.00) - avoid floating point issues
    let isRecurring: Bool
    let parentAllocationId: Int?      // Links to parent if this is a recurring instance
    var usedAmount: Int = 0           // var (not let) because it's updated after creation

    // ─────────────────────────────────────────────────────────────
    // COMPUTED PROPERTIES: Calculated from other properties
    // No value stored - calculated fresh each time you access it
    // See Section 3.5 for why we use these
    // ─────────────────────────────────────────────────────────────
    var remainingAmount: Int { allocatedAmount - usedAmount }

    var usagePercentage: Double {
        // guard = early exit if condition fails (see Section 3.10)
        // Prevents division by zero crash
        guard allocatedAmount > 0 else { return 0 }
        return Double(usedAmount) / Double(allocatedAmount) * 100
    }

    // This computed property returns an ENUM based on the percentage
    // The business logic of "what is near limit?" lives here, not in the UI
    var status: AllocationStatus {
        let pct = usagePercentage
        if pct > 100 { return .overBudget }
        else if pct >= 80 { return .nearLimit }
        else { return .underBudget }
    }

    // ─────────────────────────────────────────────────────────────
    // STATIC METHOD: Called on the TYPE, not an instance
    // BudgetAllocation.mock() ✓    someAllocation.mock() ✗
    // See Section 3.4 for detailed explanation
    // ─────────────────────────────────────────────────────────────
    //
    // WHY DEFAULT PARAMETER VALUES? Flexibility. You can call:
    //   .mock()                                - all defaults (75% food)
    //   .mock(category: .transportation)            - override just category
    //   .mock(allocated: 100000, used: 50000)  - override amounts
    //   .mock(category: .entertainment, allocated: 20000, used: 25000)  // over budget!
    //
    static func mock(
        category: TransactionCategory = .meals,
        allocated: Int = 50000,    // $500.00
        used: Int = 37500          // $375.00 (75% usage = underBudget)
    ) -> BudgetAllocation {
        // We create the allocation then modify usedAmount because
        // usedAmount isn't in the main initializer (it defaults to 0)
        var allocation = BudgetAllocation(
            id: 1,
            monthDate: Int(Date().timeIntervalSince1970),
            category: category,
            allocatedAmount: allocated,
            isRecurring: false,
            parentAllocationId: nil
        )
        allocation.usedAmount = used
        return allocation
    }
}

// MARK: - Unallocated Summary (minimal)
// This tracks spending in categories that DON'T have allocations

struct UnallocatedBudgetSummary {
    let monthDate: Int
    let totalBudget: Int
    let totalAllocated: Int
    let totalUsedInUnallocatedCategories: Int

    // Computed: how much budget isn't assigned to any category
    var unallocatedAmount: Int { totalBudget - totalAllocated }

    static func mock() -> UnallocatedBudgetSummary {
        UnallocatedBudgetSummary(
            monthDate: Int(Date().timeIntervalSince1970),
            totalBudget: 200000,      // $2,000.00 total budget
            totalAllocated: 150000,   // $1,500.00 assigned to categories
            totalUsedInUnallocatedCategories: 25000  // $250.00 spent in unassigned categories
        )
    }
}
```

### Step 1.5: Create Empty BudgetAllocationDetailsView

**File:** `Finova/Sources/Scenes/BudgetAllocationDetails/View/BudgetAllocationDetailsView.swift`

> **Why a separate View class?** This follows the MVVM pattern (see Section 3.7). The View only knows HOW to display things - it doesn't know WHERE data comes from or WHAT happens when buttons are tapped. This separation makes it reusable and easy to test.

```swift
import UIKit

// ═══════════════════════════════════════════════════════════════════
// WHY `final class`?
// - `final` means no other class can inherit from this one
// - Improves performance (compiler can optimize method calls)
// - Use `final` unless you specifically need inheritance
//
// WHY extend UIView (not UIViewController)?
// - View = just the visual layout, no logic
// - ViewController = connects View to ViewModel, handles actions
// - Keeps each class focused on ONE job (Single Responsibility)
// ═══════════════════════════════════════════════════════════════════

final class BudgetAllocationDetailsView: UIView {

    // MARK: - UI Components (Minimal for scaffolding)
    // ─────────────────────────────────────────────────────────────
    // WHY `private lazy var`? (See Section 3.3)
    //
    // `private` = only THIS class can access it
    //   - Hides implementation details
    //   - Prevents other code from messing with internal UI
    //
    // `lazy` = created only when first accessed
    //   - Saves memory if never used
    //   - Lets us use `self` in the closure (for addTarget)
    //
    // The `{ }()` closure runs immediately when first accessed
    // ─────────────────────────────────────────────────────────────

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "allocation.details.title".localized  // Placeholder, will be replaced
        label.font = Fonts.titleMD.font
        label.textColor = Colors.gray100
        label.textAlignment = .center
        // translatesAutoresizingMaskIntoConstraints = false is REQUIRED
        // for AutoLayout to work. Without it, the system creates
        // automatic constraints that conflict with yours.
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // ─────────────────────────────────────────────────────────────
    // WHY `private(set)`? (See Section 3.9)
    //
    // private(set) = anyone can READ, only this class can WRITE
    //
    // The ViewController needs to READ this button to add a tap target:
    //   mainView.backButton.addTarget(self, ...)  ✓
    //
    // But only the View should be able to REPLACE the button:
    //   mainView.backButton = someOtherButton  ✗ (won't compile)
    // ─────────────────────────────────────────────────────────────

    private(set) lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = Colors.gray100
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
        // NOTE: We don't add the tap target here!
        // The ViewController will do that - the View doesn't know
        // what should happen when the button is tapped.
    }()

    // MARK: - Initialization
    // ─────────────────────────────────────────────────────────────
    // UIView has TWO initializers you must handle:
    //
    // init(frame:)  = called when created in CODE
    //   let view = MyView(frame: .zero)
    //
    // init(coder:)  = called when loaded from STORYBOARD/XIB
    //   (The system deserializes the view from the file)
    //
    // We use programmatic UI only, so init(coder:) crashes with
    // fatalError. This makes it obvious: don't use Storyboards!
    // ─────────────────────────────────────────────────────────────

    override init(frame: CGRect) {
        super.init(frame: frame)  // ALWAYS call super first
        setupUI()  // Then do our setup
    }

    required init?(coder: NSCoder) {
        // "required" because UIView declares this initializer
        // We crash because this View doesn't support Storyboards
        fatalError("init(coder:) has not been implemented")
    }

    // ─────────────────────────────────────────────────────────────
    // WHY a separate setupUI() method?
    //
    // 1. Keeps init() clean and short
    // 2. Groups all setup code in one findable place
    // 3. Can be called from multiple initializers if needed
    // ─────────────────────────────────────────────────────────────

    private func setupUI() {
        backgroundColor = Colors.gray700

        // Add subviews to the view hierarchy
        // ORDER MATTERS: later subviews appear ON TOP of earlier ones
        addSubview(backButton)
        addSubview(placeholderLabel)

        // ─────────────────────────────────────────────────────────
        // WHY NSLayoutConstraint.activate()?
        //
        // More efficient than setting isActive = true individually.
        // Also clearer - all constraints in one place.
        //
        // Each constraint says: "this anchor = that anchor + constant"
        // ─────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // backButton: top-left corner, 40x40 size
            backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: Metrics.spacing4),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),

            // placeholderLabel: centered in the view
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Configuration
    // ─────────────────────────────────────────────────────────────
    // WHY a configure() method?
    //
    // Views should be DUMB - they don't fetch their own data.
    // The ViewController calls configure() and GIVES the View data.
    //
    // This means:
    // - The View can be reused with different data sources
    // - The View can be tested with mock data
    // - The View doesn't depend on any specific ViewModel
    // ─────────────────────────────────────────────────────────────

    func configure(with allocation: BudgetAllocation) {
        placeholderLabel.text = String(
            format: "allocation.details.title.format".localized,
            allocation.category.displayName
        )
    }
}
```

### Step 1.6: Create Empty BudgetAllocationDetailsViewController

**File:** `Finova/Sources/Scenes/BudgetAllocationDetails/View/BudgetAllocationDetailsViewController.swift`

> **The ViewController's job:** Connect the View and ViewModel. It receives user actions from the View, calls methods on the ViewModel, and updates the View with results. Think of it as a "coordinator" between visual display and data/logic.

```swift
import UIKit

final class BudgetAllocationDetailsViewController: UIViewController {

    // MARK: - Properties
    // ─────────────────────────────────────────────────────────────
    // WHY `private let` for mainView?
    //
    // `private` = only this class can access it
    // `let` = can't be replaced after initialization
    //
    // The View is created ONCE and never replaced.
    // Other classes shouldn't access our internal View directly.
    // ─────────────────────────────────────────────────────────────

    private let mainView = BudgetAllocationDetailsView()
    private let allocation: BudgetAllocation

    // ─────────────────────────────────────────────────────────────
    // WHY `weak var` for delegate? (CRITICAL - See Section 3.2)
    //
    // Without `weak`, we create a RETAIN CYCLE (memory leak):
    //
    //   AppFlowController ──owns──▶ ViewController
    //        ▲                            │
    //        └───────────owns─────────────┘
    //
    // Both hold strong references = neither can be freed!
    //
    // With `weak`:
    //   AppFlowController ──owns──▶ ViewController
    //        ▲                            │
    //        └─────weak reference─────────┘
    //
    // When AppFlowController is freed, ViewController is freed too.
    //
    // WHY `var` not `let`?
    // - Weak references must be `var` (they can become nil)
    // - Also, we set it AFTER init (from outside the class)
    // ─────────────────────────────────────────────────────────────

    weak var flowDelegate: BudgetAllocationDetailsFlowDelegate?

    // MARK: - Initialization
    // ─────────────────────────────────────────────────────────────
    // CUSTOM INITIALIZER
    //
    // UIViewController's default init doesn't take parameters.
    // We create a custom init that REQUIRES an allocation.
    // This makes it impossible to create this VC without data.
    //
    // init(allocation:) is called like:
    //   let vc = BudgetAllocationDetailsViewController(allocation: myAllocation)
    // ─────────────────────────────────────────────────────────────

    init(allocation: BudgetAllocation) {
        self.allocation = allocation
        // nibName: nil, bundle: nil = we're not using a XIB/Storyboard
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    // ─────────────────────────────────────────────────────────────
    // WHY override loadView()?
    //
    // By default, UIViewController creates an empty UIView.
    // We override loadView() to use OUR custom View instead.
    //
    // RULE: In loadView(), set self.view = something
    //       Do NOT call super.loadView()
    //       Do NOT access self.view before setting it
    // ─────────────────────────────────────────────────────────────

    override func loadView() {
        view = mainView  // Our custom View becomes the VC's main view
    }

    // ─────────────────────────────────────────────────────────────
    // viewDidLoad() = called ONCE after the view is loaded
    //
    // This is where you:
    // - Configure the view with initial data
    // - Set up button actions
    // - Add observers
    //
    // DON'T put layout code here - the view's size isn't final yet
    // ─────────────────────────────────────────────────────────────

    override func viewDidLoad() {
        super.viewDidLoad()  // Always call super for lifecycle methods
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupActions()
        mainView.configure(with: allocation)
    }

    // ─────────────────────────────────────────────────────────────
    // WHY a separate setupActions() method?
    //
    // 1. Keeps viewDidLoad() clean
    // 2. All action wiring in one place
    // 3. Easy to find when debugging tap issues
    // ─────────────────────────────────────────────────────────────

    private func setupActions() {
        // Connect button tap to our method
        // #selector requires the method to be @objc
        mainView.backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    }

    // ─────────────────────────────────────────────────────────────
    // WHY @objc?
    //
    // `addTarget` uses Objective-C runtime to call the method.
    // Swift methods aren't visible to Obj-C by default.
    // `@objc` exposes the method to Objective-C.
    //
    // WHY delegate?.dismissAllocationDetails()?
    //
    // The VC doesn't know HOW to dismiss itself (pop? dismiss modal?)
    // It tells the delegate "I want to be dismissed" and the delegate
    // (AppFlowController) decides how to do it.
    //
    // The `?` is because delegate is Optional (might be nil).
    // If nil, nothing happens (no crash).
    // ─────────────────────────────────────────────────────────────

    @objc private func backTapped() {
        flowDelegate?.dismissAllocationDetails()
    }
}
```

### Step 1.7: Add Factory Method

**File:** `Finova/Sources/Scenes/ViewControllersFactory.swift`

Add to existing factory:

```swift
// MARK: - Budget Allocation Details

static func makeBudgetAllocationDetailsViewController(
    allocation: BudgetAllocation
) -> BudgetAllocationDetailsViewController {
    return BudgetAllocationDetailsViewController(allocation: allocation)
}
```

### Step 1.8: Update DashboardFlowDelegate

**File:** Add to existing `DashboardFlowDelegate` protocol:

```swift
func navigateToAllocationDetails(allocation: BudgetAllocation)
```

### Step 1.9: Implement Navigation in AppFlowController

**File:** `Finova/Sources/App/AppFlowController.swift`

Add to DashboardFlowDelegate extension:

```swift
func navigateToAllocationDetails(allocation: BudgetAllocation) {
    let viewController = ViewControllersFactory.makeBudgetAllocationDetailsViewController(
        allocation: allocation
    )
    viewController.flowDelegate = self
    navigationController?.pushViewController(viewController, animated: true)
}
```

Add BudgetAllocationDetailsFlowDelegate extension:

```swift
// MARK: - BudgetAllocationDetailsFlowDelegate

extension AppFlowController: BudgetAllocationDetailsFlowDelegate {

    func dismissAllocationDetails() {
        navigationController?.popViewController(animated: true)
    }

    // NOTE: navigateToTransactionDetails(transaction:) is already implemented
    // in the DashboardFlowDelegate extension, so we don't need to add it here.
    // Swift allows a single method to satisfy multiple protocol requirements.

    func didUpdateAllocation() {
        navigationController?.popViewController(animated: true)
    }

    func didDeleteAllocation() {
        navigationController?.popViewController(animated: true)
    }
}
```

### Step 1.10: Create Empty BudgetCard (Back of MonthCard)

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/BudgetCard/BudgetCard.swift`

```swift
import UIKit

final class BudgetCard: UIView {

    // MARK: - Properties

    weak var delegate: MonthCardFlipDelegate?

    // Use same gradient as MonthBudgetCard for visual consistency when flipping
    private let gradientLayer = Colors.gradientBlack

    // MARK: - UI Components

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "budget.allocations.title".localized
        label.font = Fonts.titleMD.font
        label.textColor = Colors.gray100
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var flipBackButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.setImage(UIImage(systemName: "creditcard.fill", withConfiguration: config), for: .normal)
        button.tintColor = Colors.gray100
        button.addTarget(self, action: #selector(flipBack), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Apply gradient background like MonthBudgetCard
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = CornerRadius.extraLarge
        clipsToBounds = true

        addSubview(flipBackButton)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            flipBackButton.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing6),
            flipBackButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    @objc private func flipBack() {
        delegate?.didRequestFlip(isShowingBudgetView: false)
    }

    // MARK: - Configuration (stub)

    func configure(
        month: String,
        year: String,
        allocations: [BudgetAllocation],
        unallocatedSummary: UnallocatedBudgetSummary
    ) {
        placeholderLabel.text = String(
            format: "budget.allocations.month.format".localized,
            month,
            allocations.count
        )
    }
}
```

### Step 1.11: Add Flip Toggle to MonthBudgetCard

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/MonthBudgetCard/MonthBudgetCard.swift`

Add to existing class:

```swift
// MARK: - Properties (add)

weak var flipDelegate: MonthCardFlipDelegate?
private var isShowingBudgetView = false

// MARK: - Computed Properties (add)
// These expose month/year from currentMonthData for the BudgetCard to use

var currentMonth: String {
    currentMonthData?.month ?? ""
}

var currentYear: String {
    guard let date = currentMonthData?.date else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy"
    return formatter.string(from: date)
}

// MARK: - UI Components (add to header)

private lazy var budgetViewToggleButton: UIButton = {
    let button = UIButton(type: .system)
    let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    button.setImage(UIImage(systemName: "chart.pie.fill", withConfiguration: config), for: .normal)
    button.tintColor = Colors.gray100
    button.addTarget(self, action: #selector(toggleBudgetView), for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

// MARK: - Actions (add)

@objc private func toggleBudgetView() {
    flipDelegate?.didRequestFlip(isShowingBudgetView: !isShowingBudgetView)
}

func setShowingBudgetView(_ showing: Bool) {
    isShowingBudgetView = showing
    let imageName = showing ? "creditcard.fill" : "chart.pie.fill"
    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
    budgetViewToggleButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
}
```

Add `budgetViewToggleButton` to header layout (between hideValuesButton and configButton).

In `setupUI()`, add spacing between the toggle button and config icon:
```swift
headerHorizontalStackView.setCustomSpacing(Metrics.spacing3, after: budgetViewToggleButton)
```

### Step 1.12: Add Flip Logic to MonthCarouselCell

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/MonthCarouselCell.swift`

Add to existing class:

```swift
// MARK: - Properties (add)

private var isShowingBudgetView = false
private lazy var budgetCard: BudgetCard = {
    let card = BudgetCard()
    card.isHidden = true
    card.delegate = self
    card.translatesAutoresizingMaskIntoConstraints = false
    return card
}()

// MARK: - Setup (add budgetCard to view hierarchy and set delegate)

// In setupViews(), add:
monthCard.flipDelegate = self  // IMPORTANT: Wire up the flip delegate!
contentView.addSubview(budgetCard)

// In setupConstraints(), add:
NSLayoutConstraint.activate([
    budgetCard.topAnchor.constraint(equalTo: monthCard.topAnchor),
    budgetCard.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
    budgetCard.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
    budgetCard.bottomAnchor.constraint(equalTo: monthCard.bottomAnchor),
])

// MARK: - Flip Methods

func flipToBudgetView(allocations: [BudgetAllocation], summary: UnallocatedBudgetSummary) {
    guard !isShowingBudgetView else { return }

    budgetCard.configure(
        month: monthCard.currentMonth,
        year: monthCard.currentYear,
        allocations: allocations,
        unallocatedSummary: summary
    )

    UIView.transition(
        with: contentView,
        duration: 0.4,
        options: [.transitionFlipFromRight, .showHideTransitionViews]
    ) {
        self.monthCard.isHidden = true
        self.budgetCard.isHidden = false
        // Hide transaction-related views
        self.searchContainerView.isHidden = true
        self.tableHeaderView.isHidden = true
        self.transactionTableView.isHidden = true
        self.emptyStateView.isHidden = true
    } completion: { _ in
        self.isShowingBudgetView = true
        self.monthCard.setShowingBudgetView(true)
    }
}

func flipToTransactionView() {
    guard isShowingBudgetView else { return }

    UIView.transition(
        with: contentView,
        duration: 0.4,
        options: [.transitionFlipFromLeft, .showHideTransitionViews]
    ) {
        self.monthCard.isHidden = false
        self.budgetCard.isHidden = true
        // Show transaction-related views
        self.searchContainerView.isHidden = false
        self.tableHeaderView.isHidden = false
        // Restore table/empty state based on transactions
        let hasTransactions = !self.transactions.isEmpty
        self.transactionTableView.isHidden = !hasTransactions
        self.emptyStateView.isHidden = hasTransactions
    } completion: { _ in
        self.isShowingBudgetView = false
        self.monthCard.setShowingBudgetView(false)
    }
}
```

### Step 1.13: Implement MonthCardFlipDelegate in MonthCarouselCell

```swift
// MARK: - MonthCardFlipDelegate

extension MonthCarouselCell: MonthCardFlipDelegate {

    func didRequestFlip(isShowingBudgetView: Bool) {
        if isShowingBudgetView {
            // Get mock data for now
            let mockAllocations = [
                BudgetAllocation.mock(category: .meals, allocated: 50000, used: 37500),
                BudgetAllocation.mock(category: .transportation, allocated: 30000, used: 28000),
                BudgetAllocation.mock(category: .entertainment, allocated: 20000, used: 25000),
            ]
            let mockSummary = UnallocatedBudgetSummary.mock()
            flipToBudgetView(allocations: mockAllocations, summary: mockSummary)
        } else {
            flipToTransactionView()
        }
    }

    func didSelectAllocationCategory(_ category: TransactionCategory) {
        // Will implement later
        print("Selected category: \(category.displayName)")
    }

    func didTapAllocation(_ allocation: BudgetAllocation) {
        // Forward to parent for navigation
        // Will implement later
        print("Tapped allocation: \(allocation.category.displayName)")
    }
}
```

---

### ✅ Phase 1 Checkpoint

**Files created/modified in Phase 1:**
- ✅ `MonthCardFlipDelegate.swift` - Protocol for flip communication
- ✅ `BudgetAllocationDetailsFlowDelegate.swift` - Protocol for details navigation
- ✅ `BudgetAllocationModel.swift` - Minimal models with mock() methods
- ✅ `BudgetCard.swift` - Back side of the flip card
- ✅ `MonthBudgetCard.swift` - Added `flipDelegate`, computed properties, toggle button
- ✅ `MonthCarouselCell.swift` - Added flip logic, delegate conformance, budgetCard

**Key implementation details:**
- `monthCard.flipDelegate = self` must be set in `setupViews()`
- `budgetCard` constraints match `monthCard` bounds (top, leading, trailing, bottom)
- Flip animation hides/shows: `monthCard`, `searchContainerView`, `tableHeaderView`, `transactionTableView`, `emptyStateView`
- BudgetCard uses same `gradientLayer` as MonthBudgetCard for visual consistency

**You should be able to:**
1. **Build and run** the app without errors
2. **See a pie chart icon** in MonthBudgetCard header
3. **Tap the icon** and see the card flip to show BudgetCard with gradient background
4. **Tap the card icon** on BudgetCard to flip back
5. **See transactions list hidden** when BudgetCard is showing

---

## Phase 2: Data Models & Constants

> **Goal**: Expand the minimal models from Phase 1 into complete data models with database support. UI still uses mock data.

---

### Understanding This Phase

In Phase 1, we created **minimal scaffolding** - just enough to see something on screen. Now we need **real data structures** that can:
1. Be saved to a database
2. Be converted to/from JSON
3. Hold all the information we need

**Key Concept: Two Models for One Thing**

We use TWO different structs for allocations:

| Model | Purpose | Where Used |
|-------|---------|------------|
| `BudgetAllocationModel` | Database storage | Saving/loading from SQLite |
| `BudgetAllocation` | Display in UI | Views, ViewModels |

**Why two models?**

```swift
// DATABASE MODEL - Uses simple types that databases understand
struct BudgetAllocationModel: Codable {
    let categoryKey: String      // "category.meals" - just a string
}

// DISPLAY MODEL - Uses rich types that are easier to work with
struct BudgetAllocation {
    let category: TransactionCategory  // An enum with icon, color, name
}
```

The database can't store a `TransactionCategory` enum - it can only store strings and numbers. So we:
1. Convert `TransactionCategory` → `String` when saving
2. Convert `String` → `TransactionCategory` when loading

---

**Already implemented in Phase 1:**
- ✅ `AllocationStatus` enum with `color` and `localizedLabel`
- ✅ `BudgetAllocation` struct with basic properties and `mock()` method
- ✅ `UnallocatedBudgetSummary` struct with `mock()` method

**What Phase 2 adds:**
- `BudgetAllocationModel` (database/Codable model for persistence)
- `icon` property to `AllocationStatus`
- Full initializer for `BudgetAllocation`
- Conversion methods between database and display models

---

### Step 2.1: Complete BudgetAllocationModel

**File:** `Finova/Sources/Core/Repositories/BudgetAllocationRepository/BudgetAllocationModel.swift`

Expand your existing file with the complete implementation. I'll explain each part:

```swift
import UIKit

// ═══════════════════════════════════════════════════════════════════
// MARK: - Database Model
// ═══════════════════════════════════════════════════════════════════
//
// This struct is for DATABASE STORAGE ONLY.
//
// WHY Codable?
// -----------
// Codable = Encodable + Decodable
// - Encodable: Can be converted TO JSON/data
// - Decodable: Can be created FROM JSON/data
//
// Our database library (SQLite.swift) uses Codable to automatically
// save and load our objects. Without Codable, we'd have to write
// manual conversion code for every property.
//
// WHY simple types only?
// ----------------------
// Databases store: Int, String, Double, Bool, Data
// Databases DON'T store: Enums, custom objects, UIColor
//
// So we store `categoryKey: String` instead of `category: TransactionCategory`
// ═══════════════════════════════════════════════════════════════════

struct BudgetAllocationModel: Codable {

    // ─────────────────────────────────────────────────────────────
    // WHY `let id: Int?` (optional)?
    //
    // When CREATING a new allocation, we don't have an ID yet.
    // The database GENERATES the ID when we save.
    //
    // let newAllocation = BudgetAllocationModel(id: nil, ...)  // No ID
    // let savedId = database.insert(newAllocation)              // DB gives us ID
    // ─────────────────────────────────────────────────────────────
    let id: Int?

    // ─────────────────────────────────────────────────────────────
    // WHY `monthDate: Int` instead of `Date`?
    //
    // We use "month anchor" format: the Unix timestamp of the first
    // day of the month at midnight. This makes it easy to:
    // - Compare months (just compare integers)
    // - Query the database (WHERE monthDate = 1704067200)
    // - Avoid timezone issues
    //
    // Example: January 2024 = 1704067200 (Jan 1, 2024 00:00:00 UTC)
    // ─────────────────────────────────────────────────────────────
    let monthDate: Int

    // ─────────────────────────────────────────────────────────────
    // WHY `categoryKey: String` instead of `TransactionCategory`?
    //
    // The database can't store Swift enums. We store the string key:
    // - TransactionCategory.meals → "category.meals"
    // - TransactionCategory.transportation → "category.transportation"
    //
    // When loading, we convert back:
    // - "category.meals" → TransactionCategory.meals
    // ─────────────────────────────────────────────────────────────
    let categoryKey: String

    let allocatedAmount: Int        // Amount in cents (50000 = $500.00)
    let isRecurring: Bool           // Should this repeat every month?
    let parentAllocationId: Int?    // If recurring, points to the original

    // ─────────────────────────────────────────────────────────────
    // CUSTOM INITIALIZER
    //
    // WHY write our own init when Swift auto-generates one?
    //
    // To provide DEFAULT VALUES:
    // - `id: Int? = nil` means you don't have to pass id
    // - `isRecurring: Bool = false` means it defaults to false
    //
    // So you can write:
    //   BudgetAllocationModel(monthDate: 123, categoryKey: "meals", allocatedAmount: 50000)
    // Instead of:
    //   BudgetAllocationModel(id: nil, monthDate: 123, categoryKey: "meals",
    //                         allocatedAmount: 50000, isRecurring: false, parentAllocationId: nil)
    // ─────────────────────────────────────────────────────────────
    init(
        id: Int? = nil,
        monthDate: Int,
        categoryKey: String,
        allocatedAmount: Int,
        isRecurring: Bool = false,
        parentAllocationId: Int? = nil
    ) {
        self.id = id
        self.monthDate = monthDate
        self.categoryKey = categoryKey
        self.allocatedAmount = allocatedAmount
        self.isRecurring = isRecurring
        self.parentAllocationId = parentAllocationId
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Allocation Status Enum
// ═══════════════════════════════════════════════════════════════════
//
// This enum represents the "health" of an allocation:
// - underBudget: Spending is under control (0-79% used)
// - nearLimit: Getting close to the limit (80-99% used)
// - overBudget: Exceeded the allocation (100%+ used)
//
// WHY use an enum instead of just checking percentages everywhere?
//
// 1. SINGLE SOURCE OF TRUTH:
//    The thresholds (80%, 100%) are defined in ONE place.
//    If we want to change "near limit" to 85%, we change it once.
//
// 2. ASSOCIATED DATA:
//    Each status "knows" its color, icon, and label.
//    The UI just asks: status.color, status.icon
//
// 3. TYPE SAFETY:
//    You can't accidentally pass an invalid status.
//    The compiler ensures only these 3 values exist.
// ═══════════════════════════════════════════════════════════════════

enum AllocationStatus {
    case underBudget    // 0-79% used
    case nearLimit      // 80-99% used
    case overBudget     // 100%+ used

    // ─────────────────────────────────────────────────────────────
    // COMPUTED PROPERTY: color
    //
    // Each status has an associated color for visual feedback.
    // This is a "computed property" - it calculates the value
    // each time you access it (no storage).
    // ─────────────────────────────────────────────────────────────
    var color: UIColor {
        switch self {
        case .underBudget: return Colors.mainMagenta
        case .nearLimit: return Colors.warningAmber
        case .overBudget: return Colors.mainRed
        }
    }

    // SF Symbol icon name for each status
    var icon: String {
        switch self {
        case .underBudget: return "checkmark.circle.fill"
        case .nearLimit: return "exclamationmark.triangle.fill"
        case .overBudget: return "xmark.circle.fill"
        }
    }

    // Localized text for accessibility and display
    var localizedLabel: String {
        switch self {
        case .underBudget: return "allocation.status.under".localized
        case .nearLimit: return "allocation.status.near".localized
        case .overBudget: return "allocation.status.over".localized
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Display Model
// ═══════════════════════════════════════════════════════════════════
//
// This struct is for UI DISPLAY.
//
// It's different from BudgetAllocationModel because:
// 1. Uses rich types (TransactionCategory instead of String)
// 2. Has computed properties for UI (status, usagePercentage)
// 3. Has a mutable property (usedAmount) that we fill in later
//
// FLOW:
// Database → BudgetAllocationModel → BudgetAllocation → UI
// ═══════════════════════════════════════════════════════════════════

struct BudgetAllocation {

    // ─────────────────────────────────────────────────────────────
    // STORED PROPERTIES
    // These values are stored in memory
    // ─────────────────────────────────────────────────────────────
    let id: Int?
    let monthDate: Int
    let category: TransactionCategory  // Rich type, not just a string!
    let allocatedAmount: Int
    let isRecurring: Bool
    let parentAllocationId: Int?

    // ─────────────────────────────────────────────────────────────
    // WHY `var usedAmount` instead of `let`?
    //
    // When we load allocations from the database, we don't know
    // how much has been spent yet. We fill this in LATER by
    // querying transactions.
    //
    // 1. Load allocation (usedAmount = 0)
    // 2. Query transactions for this category
    // 3. Set usedAmount = sum of transactions
    // ─────────────────────────────────────────────────────────────
    var usedAmount: Int = 0

    // ─────────────────────────────────────────────────────────────
    // COMPUTED PROPERTIES
    // These calculate their values from other properties
    // ─────────────────────────────────────────────────────────────

    var remainingAmount: Int {
        allocatedAmount - usedAmount
        // Can be negative if overspent!
    }

    var usagePercentage: Double {
        // Guard against division by zero
        guard allocatedAmount > 0 else { return 0 }
        return Double(usedAmount) / Double(allocatedAmount) * 100
    }

    var status: AllocationStatus {
        let percentage = usagePercentage
        if percentage > 100 { return .overBudget }
        else if percentage >= 80 { return .nearLimit }
        else { return .underBudget }
    }

    // ─────────────────────────────────────────────────────────────
    // INITIALIZERS
    // ─────────────────────────────────────────────────────────────

    // Standard initializer - used when creating new allocations
    init(
        id: Int? = nil,
        monthDate: Int,
        category: TransactionCategory,
        allocatedAmount: Int,
        isRecurring: Bool = false,
        parentAllocationId: Int? = nil,
        usedAmount: Int = 0
    ) {
        self.id = id
        self.monthDate = monthDate
        self.category = category
        self.allocatedAmount = allocatedAmount
        self.isRecurring = isRecurring
        self.parentAllocationId = parentAllocationId
        self.usedAmount = usedAmount
    }

    // ─────────────────────────────────────────────────────────────
    // CONVENIENCE INITIALIZER: init(from model:)
    //
    // Creates a display model from a database model.
    // This is where we convert:
    // - categoryKey (String) → category (TransactionCategory)
    //
    // The `.first { }` finds the first category where the key matches.
    // If no match found, defaults to .miscellaneous
    // ─────────────────────────────────────────────────────────────
    init(from model: BudgetAllocationModel) {
        self.id = model.id
        self.monthDate = model.monthDate
        self.category = TransactionCategory.allCases.first {
            $0.key == model.categoryKey
        } ?? .miscellaneous
        self.allocatedAmount = model.allocatedAmount
        self.isRecurring = model.isRecurring
        self.parentAllocationId = model.parentAllocationId
        self.usedAmount = 0  // Will be filled in later
    }

    // ─────────────────────────────────────────────────────────────
    // WHY `mutating func` for setUsedAmount?
    //
    // Structs are VALUE TYPES - they're copied, not shared.
    // To modify a struct's property, the method must be `mutating`.
    //
    // This tells Swift: "This method changes the struct itself"
    // ─────────────────────────────────────────────────────────────
    mutating func setUsedAmount(_ amount: Int) {
        self.usedAmount = amount
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Mock Data
    //
    // Creates fake allocations for testing UI before database is ready.
    // See Section 3.4 for explanation of static func mock().
    // ─────────────────────────────────────────────────────────────

    static func mock(
        category: TransactionCategory = .meals,
        allocated: Int = 50000,
        used: Int = 37500,
        isRecurring: Bool = false
    ) -> BudgetAllocation {
        BudgetAllocation(
            id: Int.random(in: 1...1000),
            monthDate: Int(Date().timeIntervalSince1970),
            category: category,
            allocatedAmount: allocated,
            isRecurring: isRecurring,
            usedAmount: used
        )
    }
}

// MARK: - Unallocated Budget Summary

struct UnallocatedBudgetSummary {
    let monthDate: Int
    let totalBudget: Int
    let totalAllocated: Int
    let totalUsedInUnallocatedCategories: Int

    var unallocatedAmount: Int {
        totalBudget - totalAllocated
    }

    var unallocatedRemaining: Int {
        unallocatedAmount - totalUsedInUnallocatedCategories
    }

    var isOverspent: Bool {
        unallocatedRemaining < 0
    }

    static func mock() -> UnallocatedBudgetSummary {
        UnallocatedBudgetSummary(
            monthDate: Int(Date().timeIntervalSince1970),
            totalBudget: 200000,
            totalAllocated: 150000,
            totalUsedInUnallocatedCategories: 25000
        )
    }
}

// MARK: - Errors

enum BudgetAllocationError: LocalizedError {
    case duplicateAllocation
    case allocationNotFound
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .duplicateAllocation:
            return "allocation.error.duplicate".localized
        case .allocationNotFound:
            return "allocation.error.notFound".localized
        case .invalidAmount:
            return "allocation.error.invalidAmount".localized
        }
    }
}
```

---

## Phase 3: UI Components with Mock Data

> **Goal**: Build all visual components using mock/hardcoded data. See the complete UI.

### Understanding This Phase

Now that you understand Swift basics (Section 3.0) and have models (Phase 2), we'll build the visual components. This phase focuses on **UIKit patterns** you'll use throughout iOS development.

**Key UIKit Concepts Used:**

| Pattern | Where Used | Why |
|---------|-----------|-----|
| **UITableView** | AllocationCell, BudgetCard | Efficient scrolling lists |
| **UITableViewCell subclass** | AllocationCell | Custom cell layout |
| **Delegation** | BudgetCard → MonthCarouselCell | Component communication |
| **Auto Layout** | All views | Responsive positioning |
| **CAShapeLayer** | CircularProgressView | Custom drawing |
| **UIHostingController** | BudgetDonutChartView | SwiftUI ↔ UIKit bridge |

---

### Step 3.1: Create AllocationCell

> **UITableViewCell subclass** - This is iOS's way of creating custom table rows. Each cell is recycled (reused) as you scroll to save memory. That's why we have a `reuseIdentifier`.

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/BudgetCard/AllocationCell.swift`

```swift
import UIKit

// ═══════════════════════════════════════════════════════════════════
// UITableViewCell SUBCLASSING
//
// When you want a custom table row, you:
// 1. Create a class that inherits from UITableViewCell
// 2. Add your custom UI components to contentView (not self)
// 3. Define a reuseIdentifier so the table can recycle cells
//
// The table calls configure() when it needs to display data in the cell.
// The same cell object might show different data as you scroll!
// ═══════════════════════════════════════════════════════════════════

final class AllocationCell: UITableViewCell {

    // STATIC PROPERTY: Same for ALL AllocationCell instances
    // Used by tableView.dequeueReusableCell(withIdentifier:)
    static let reuseIdentifier = "AllocationCell"

    // MARK: - UI Components
    // (See Section 3.3 for why we use `private lazy var`)

    private lazy var iconContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray600
        view.layer.cornerRadius = CornerRadius.medium
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var categoryIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray100
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var categoryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var usageLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var recurringIcon: UIImageView = {
        let imageView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        imageView.image = UIImage(systemName: "repeat", withConfiguration: config)
        imageView.tintColor = Colors.gray400
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var progressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray600
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var statusBadge: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Tap Handling

    private var tapAction: (() -> Void)?

    // MARK: - Initialization

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = Colors.gray700
        selectionStyle = .none

        contentView.addSubview(iconContainerView)
        iconContainerView.addSubview(categoryIconView)
        contentView.addSubview(titleStackView)
        titleStackView.addArrangedSubview(categoryLabel)
        titleStackView.addArrangedSubview(usageLabel)
        contentView.addSubview(recurringIcon)
        contentView.addSubview(progressBar)
        contentView.addSubview(statusBadge)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            iconContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 40),
            iconContainerView.heightAnchor.constraint(equalToConstant: 40),

            categoryIconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            categoryIconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            categoryIconView.widthAnchor.constraint(equalToConstant: 20),
            categoryIconView.heightAnchor.constraint(equalToConstant: 20),

            titleStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing3),
            titleStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing3),
            titleStackView.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -Metrics.spacing2),

            recurringIcon.leadingAnchor.constraint(equalTo: categoryLabel.trailingAnchor, constant: Metrics.spacing2),
            recurringIcon.centerYAnchor.constraint(equalTo: categoryLabel.centerYAnchor),

            progressBar.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing3),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            progressBar.topAnchor.constraint(equalTo: titleStackView.bottomAnchor, constant: Metrics.spacing2),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
            progressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing3),

            statusBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            statusBadge.centerYAnchor.constraint(equalTo: titleStackView.centerYAnchor),
        ])
    }

    // MARK: - Configuration

    func configure(with allocation: BudgetAllocation) {
        categoryIconView.image = UIImage(named: allocation.category.iconName)
        categoryLabel.text = allocation.category.displayName
        usageLabel.text = String(
            format: "budget.usage.format".localized,
            allocation.usedAmount.currencyString,
            allocation.allocatedAmount.currencyString
        )

        recurringIcon.isHidden = !allocation.isRecurring

        let progress = Float(allocation.usagePercentage / 100)
        progressBar.progressTintColor = allocation.status.color
        progressBar.setProgress(min(progress, 1.0), animated: false)

        statusBadge.text = allocation.status.localizedLabel
        statusBadge.textColor = allocation.status.color
    }

    func setTapAction(_ action: @escaping () -> Void) {
        self.tapAction = action
        let tap = UITapGestureRecognizer(target: self, action: #selector(cellTapped))
        contentView.addGestureRecognizer(tap)
    }

    @objc private func cellTapped() {
        tapAction?()
    }

    func highlight() {
        UIView.animate(withDuration: 0.2) {
            self.backgroundColor = Colors.lowMagenta
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.3) {
                self.backgroundColor = Colors.gray700
            }
        }
    }
}
```

### Step 3.2: Create CircularProgressView

**File:** `Finova/Sources/Scenes/BudgetAllocationDetails/Components/CircularProgressView.swift`

> **Core Animation (CAShapeLayer)** - iOS uses layers for efficient drawing. Instead of drawing shapes every frame, you describe the shape once and the GPU handles rendering. This is much faster than manual drawing in `draw(_:)`.

```swift
import UIKit

// ═══════════════════════════════════════════════════════════════════
// CUSTOM DRAWING WITH CAShapeLayer
//
// UIView's visual content is actually drawn by its `layer` (a CALayer).
// CAShapeLayer is a specialized layer for drawing shapes like:
// - Circles, arcs, rectangles
// - Custom paths (UIBezierPath)
//
// Benefits:
// - GPU-accelerated rendering (very fast)
// - Easy animation (animate strokeEnd, strokeColor, etc.)
// - Memory efficient (no bitmap, just shape math)
//
// We use TWO layers:
// 1. trackLayer: The gray background circle (always full)
// 2. progressLayer: The colored progress arc (strokeEnd animates 0→1)
// ═══════════════════════════════════════════════════════════════════

final class CircularProgressView: UIView {

    // MARK: - Properties

    private var progress: CGFloat = 0
    private var trackColor: UIColor = Colors.gray600
    private var progressColor: UIColor = Colors.mainMagenta
    private let lineWidth: CGFloat = 12

    private lazy var trackLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = trackColor.cgColor
        layer.lineWidth = lineWidth
        layer.lineCap = .round
        return layer
    }()

    private lazy var progressLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = progressColor.cgColor
        layer.lineWidth = lineWidth
        layer.lineCap = .round
        layer.strokeEnd = 0
        return layer
    }()

    private lazy var centerStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var percentageLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleLG.font
        label.textColor = Colors.gray100
        label.textAlignment = .center
        return label
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textAlignment = .center
        return label
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePaths()
    }

    // MARK: - Setup

    private func setupUI() {
        layer.addSublayer(trackLayer)
        layer.addSublayer(progressLayer)

        addSubview(centerStackView)
        centerStackView.addArrangedSubview(percentageLabel)
        centerStackView.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            centerStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func updatePaths() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2

        let startAngle = -CGFloat.pi / 2
        let endAngle = startAngle + 2 * CGFloat.pi

        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )

        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }

    // MARK: - Configuration

    func configure(percentage: Double, status: AllocationStatus, animated: Bool = true) {
        progress = CGFloat(min(percentage, 100) / 100)
        progressColor = status.color

        percentageLabel.text = String(format: "format.percentage".localized, Int(percentage))
        statusLabel.text = status.localizedLabel
        statusLabel.textColor = status.color

        progressLayer.strokeColor = progressColor.cgColor

        if animated {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = progressLayer.strokeEnd
            animation.toValue = progress
            animation.duration = 0.5
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressLayer.add(animation, forKey: "progressAnimation")
        }

        progressLayer.strokeEnd = progress
    }
}
```

### Step 3.3: Create BudgetDonutChartView (SwiftUI)

**File:** `Finova/Sources/SwiftUI/Charts/BudgetDonutChartView.swift`

> **SwiftUI in a UIKit App** - You can use SwiftUI views inside UIKit by wrapping them in `UIHostingController`. This lets us use Swift Charts (iOS 16+) while keeping the rest of the app in UIKit. See Step 3.4 for how to embed this view.

```swift
import SwiftUI
import Charts  // Apple's declarative charting framework (iOS 16+)

// ═══════════════════════════════════════════════════════════════════
// SwiftUI vs UIKit
//
// SwiftUI is Apple's DECLARATIVE UI framework (introduced in 2019).
// Instead of imperative code ("add this button, set its title"),
// you DESCRIBE what you want and SwiftUI figures out how to render it.
//
// UIKit (imperative):
//   let label = UILabel()
//   label.text = "Hello"
//   view.addSubview(label)
//
// SwiftUI (declarative):
//   Text("Hello")
//
// WHY use SwiftUI here?
// - Swift Charts is SwiftUI-only (no UIKit version)
// - Declarative charts are much easier to write
// - We wrap it in UIHostingController to use in UIKit
//
// @available(iOS 16.0, *) means this code only runs on iOS 16+
// On older iOS, we'd need a fallback (or skip the chart)
// ═══════════════════════════════════════════════════════════════════

@available(iOS 16.0, *)
struct BudgetDonutChartView: View {
    let allocations: [BudgetAllocation]
    let unallocatedAmount: Int
    var onSegmentTapped: ((TransactionCategory) -> Void)?

    @State private var selectedCategory: TransactionCategory?

    var body: some View {
        ZStack {
            Chart {
                ForEach(allocations, id: \.category.key) { allocation in
                    SectorMark(
                        angle: .value("Amount", allocation.allocatedAmount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(allocation.status.color))
                    .opacity(selectedCategory == allocation.category ? 1.0 : 0.8)
                }

                if unallocatedAmount > 0 {
                    SectorMark(
                        angle: .value("Unallocated", unallocatedAmount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(Colors.gray500))
                    .opacity(0.5)
                }
            }
            .chartLegend(.hidden)

            VStack(spacing: 4) {
                if let selected = selectedCategory,
                   let allocation = allocations.first(where: { $0.category == selected }) {
                    Image(uiImage: selected.icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(allocation.allocatedAmount.currencyString)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(Colors.gray100))
                    Text(selected.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(Color(Colors.gray400))
                } else {
                    Text(unallocatedAmount.currencyString)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(Colors.gray100))
                    Text("budget.unallocated".localized)
                        .font(.system(size: 10))
                        .foregroundColor(Color(Colors.gray400))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTap(at: location, geometry: geometry)
                    }
            }
        }
    }

    private func handleTap(at location: CGPoint, geometry: GeometryProxy) {
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let vector = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y)
        let radius = min(geometry.size.width, geometry.size.height) / 2
        let innerRadius = radius * 0.6

        guard distance > innerRadius && distance < radius else {
            selectedCategory = nil
            return
        }

        var angle = atan2(vector.y, vector.x)
        if angle < 0 { angle += 2 * .pi }
        angle = angle - .pi / 2
        if angle < 0 { angle += 2 * .pi }

        let total = allocations.reduce(0) { $0 + $1.allocatedAmount } + unallocatedAmount
        let normalizedAngle = angle / (2 * .pi)
        var cumulativePercent: Double = 0

        for allocation in allocations {
            let percent = Double(allocation.allocatedAmount) / Double(total)
            if normalizedAngle >= cumulativePercent && normalizedAngle < cumulativePercent + percent {
                selectedCategory = allocation.category
                onSegmentTapped?(allocation.category)
                return
            }
            cumulativePercent += percent
        }

        selectedCategory = nil
    }
}
```

### Step 3.4: Update BudgetCard with Full UI

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/BudgetCard/BudgetCard.swift`

> **Important:** This layout matches `MonthBudgetCard` exactly - same header format with "Month / Year", same footer style with two vertical stacks, and progress bar edge-to-edge at bottom.

```swift
import UIKit

final class BudgetCard: UIView {

    // MARK: - Properties

    private var allocations: [BudgetAllocation] = []
    private var unallocatedSummary: UnallocatedBudgetSummary?
    weak var delegate: MonthCardFlipDelegate?
    private let gradientLayer = Colors.gradientBlack

    // MARK: - UI Components

    // Header - matching MonthBudgetCard style
    private lazy var headerHorizontalStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var headerDateStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing2
        stack.alignment = .center
        return stack
    }()

    private lazy var monthLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM  // Uses fontStyle like MonthBudgetCard
        label.textColor = Colors.gray100
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    private lazy var yearLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var flipBackButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        button.setImage(UIImage(systemName: "creditcard.fill", withConfiguration: config), for: .normal)
        button.tintColor = Colors.gray100
        button.addTarget(self, action: #selector(flipBack), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var chartContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // Footer - matching MonthBudgetCard style (two vertical stacks)
    private lazy var footerStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var allocatedStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        return stack
    }()

    private lazy var allocatedTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "budget.allocated.label".localized  // "Allocated"
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var allocatedValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var percentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.alignment = .trailing
        return stack
    }()

    private lazy var percentTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "budget.percent.label".localized  // "Budget"
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var percentValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        return label
    }()

    // Progress bar - edge to edge like MonthBudgetCard
    private lazy var progressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray600
        bar.progressTintColor = Colors.mainMagenta
        bar.cornerRadius = 4.0
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var allocationsTableView: UITableView = {
        let table = UITableView()
        table.register(AllocationCell.self, forCellReuseIdentifier: AllocationCell.reuseIdentifier)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.isScrollEnabled = true
        table.showsVerticalScrollIndicator = false
        table.delegate = self
        table.dataSource = self
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Apply gradient background like MonthBudgetCard
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = CornerRadius.extraLarge
        clipsToBounds = true

        // Header setup - matching MonthBudgetCard
        headerDateStackView.addArrangedSubview(monthLabel)
        headerDateStackView.addArrangedSubview(yearLabel)

        headerHorizontalStackView.addArrangedSubview(headerDateStackView)
        headerHorizontalStackView.addArrangedSubview(UIView()) // Spacer
        headerHorizontalStackView.addArrangedSubview(flipBackButton)

        // Footer setup - matching MonthBudgetCard
        allocatedStackView.addArrangedSubview(allocatedTextLabel)
        allocatedStackView.addArrangedSubview(allocatedValueLabel)

        percentStackView.addArrangedSubview(percentTextLabel)
        percentStackView.addArrangedSubview(percentValueLabel)

        footerStackView.addArrangedSubview(allocatedStackView)
        footerStackView.addArrangedSubview(percentStackView)

        addSubview(headerHorizontalStackView)
        addSubview(chartContainerView)
        addSubview(footerStackView)
        addSubview(allocationsTableView)
        addSubview(progressBar)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header
            headerHorizontalStackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing6),
            headerHorizontalStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            headerHorizontalStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            // Chart container
            chartContainerView.topAnchor.constraint(equalTo: headerHorizontalStackView.bottomAnchor, constant: Metrics.spacing3),
            chartContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            chartContainerView.widthAnchor.constraint(equalToConstant: 140),
            chartContainerView.heightAnchor.constraint(equalToConstant: 140),

            // Table view
            allocationsTableView.topAnchor.constraint(equalTo: chartContainerView.bottomAnchor, constant: Metrics.spacing3),
            allocationsTableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            allocationsTableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            allocationsTableView.bottomAnchor.constraint(equalTo: footerStackView.topAnchor, constant: -Metrics.spacing3),

            // Footer - above progress bar
            footerStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            footerStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),
            footerStackView.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -Metrics.spacing4),

            // Progress bar - edge to edge at bottom (like MonthBudgetCard)
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    @objc private func flipBack() {
        delegate?.didRequestFlip(isShowingBudgetView: false)
    }

    // MARK: - Configuration

    func configure(
        month: String,
        year: String,
        allocations: [BudgetAllocation],
        unallocatedSummary: UnallocatedBudgetSummary
    ) {
        self.allocations = allocations
        self.unallocatedSummary = unallocatedSummary

        // Header - matching MonthBudgetCard format with "/ " prefix on year
        monthLabel.text = month
        monthLabel.applyStyle()
        yearLabel.text = "/ " + year

        // Footer values
        allocatedValueLabel.text = unallocatedSummary.totalAllocated.currencyString

        let allocatedPercent = unallocatedSummary.totalBudget > 0
            ? Float(unallocatedSummary.totalAllocated) / Float(unallocatedSummary.totalBudget)
            : 0

        percentValueLabel.text = String(
            format: "budget.allocated.percent".localized,
            Int(allocatedPercent * 100)
        )

        // Progress bar
        progressBar.setProgress(min(allocatedPercent, 1.0), animated: true)

        if allocatedPercent > 1.0 {
            progressBar.progressTintColor = Colors.warningAmber
            percentValueLabel.textColor = Colors.warningAmber
        } else {
            progressBar.progressTintColor = Colors.mainMagenta
            percentValueLabel.textColor = Colors.gray100
        }

        allocationsTableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension BudgetCard: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allocations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: AllocationCell.reuseIdentifier,
            for: indexPath
        ) as? AllocationCell else {
            return UITableViewCell()
        }

        let allocation = allocations[indexPath.row]
        cell.configure(with: allocation)
        cell.setTapAction { [weak self] in
            self?.delegate?.didTapAllocation(allocation)
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension BudgetCard: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}
```

### Step 3.5: Update BudgetAllocationDetailsView with Full UI

**File:** `Finova/Sources/Scenes/BudgetAllocationDetails/View/BudgetAllocationDetailsView.swift`

```swift
import UIKit

final class BudgetAllocationDetailsView: UIView {

    // MARK: - UI Components

    // Header
    private lazy var headerContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var backButtonGlassContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray700.withAlphaComponent(0.6)
        view.layer.cornerRadius = CornerRadius.medium
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = Colors.gray100
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var categoryIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray100
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var categoryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleMD.font
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var monthYearLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        return label
    }()

    // Scroll View
    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // Summary Card
    private lazy var summaryCardView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray700
        view.layer.cornerRadius = CornerRadius.medium
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var circularProgressView: CircularProgressView = {
        let view = CircularProgressView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var allocatedLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "allocation.details.summary.allocated".localized
        return label
    }()

    private lazy var allocatedValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var usedLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "allocation.details.summary.used".localized
        return label
    }()

    private lazy var usedValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var remainingLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "allocation.details.summary.remaining".localized
        return label
    }()

    private lazy var remainingValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var recurringBadge: UIView = {
        let container = UIView()
        container.backgroundColor = Colors.gray600
        container.layer.cornerRadius = CornerRadius.small
        container.isHidden = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let icon = UIImageView(image: UIImage(systemName: "repeat", withConfiguration: iconConfig))
        icon.tintColor = Colors.gray300

        let label = UILabel()
        label.text = "allocation.details.summary.recurring".localized
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray300

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
        ])

        return container
    }()

    private lazy var warningBanner: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.lowAmber
        view.layer.cornerRadius = CornerRadius.small
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var warningLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.warningAmber
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Transactions Section
    private lazy var transactionsHeaderLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray100
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private(set) lazy var transactionsTableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = Colors.gray700
        table.layer.cornerRadius = CornerRadius.medium
        table.separatorStyle = .none
        table.isScrollEnabled = false
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private lazy var emptyStateView: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false

        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .light)
        let icon = UIImageView(image: UIImage(systemName: "tray", withConfiguration: config))
        icon.tintColor = Colors.gray500
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "allocation.details.transactions.empty".localized
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(icon)
        view.addSubview(label)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: view.topAnchor, constant: Metrics.spacing4),
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: Metrics.spacing3),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        return view
    }()

    // Action Buttons
    private lazy var actionButtonsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray700
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var editButton: Button = {
        let button = Button(variant: .base)
        button.setTitle("allocation.details.action.edit".localized, for: .normal)
        return button
    }()

    private(set) lazy var deleteButton: Button = {
        let button = Button(variant: .outlined)
        button.setTitle("allocation.details.action.delete".localized, for: .normal)
        button.setTitleColor(Colors.mainRed, for: .normal)
        button.layer.borderColor = Colors.mainRed.cgColor
        return button
    }()

    private var tableHeightConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = Colors.gray700

        // Header
        addSubview(headerContainerView)
        headerContainerView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        headerContainerView.addSubview(categoryIconView)
        headerContainerView.addSubview(categoryLabel)
        headerContainerView.addSubview(monthYearLabel)

        // Scroll
        addSubview(scrollView)
        scrollView.addSubview(contentView)

        // Summary
        contentView.addSubview(summaryCardView)
        summaryCardView.addSubview(circularProgressView)
        summaryCardView.addSubview(allocatedLabel)
        summaryCardView.addSubview(allocatedValueLabel)
        summaryCardView.addSubview(usedLabel)
        summaryCardView.addSubview(usedValueLabel)
        summaryCardView.addSubview(remainingLabel)
        summaryCardView.addSubview(remainingValueLabel)
        summaryCardView.addSubview(recurringBadge)
        summaryCardView.addSubview(warningBanner)
        warningBanner.addSubview(warningLabel)

        // Transactions
        contentView.addSubview(transactionsHeaderLabel)
        contentView.addSubview(transactionsTableView)
        contentView.addSubview(emptyStateView)

        // Actions
        addSubview(actionButtonsContainerView)
        actionButtonsContainerView.addSubview(editButton)
        actionButtonsContainerView.addSubview(deleteButton)

        setupConstraints()
    }

    private func setupConstraints() {
        let safeArea = safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            // Header
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerContainerView.heightAnchor.constraint(equalToConstant: 160),

            backButtonGlassContainer.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: Metrics.spacing2),
            backButtonGlassContainer.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor, constant: Metrics.spacing4),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 40),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 40),

            backButton.centerXAnchor.constraint(equalTo: backButtonGlassContainer.centerXAnchor),
            backButton.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

            categoryIconView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor, constant: Metrics.spacing4),
            categoryIconView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: -Metrics.spacing4),
            categoryIconView.widthAnchor.constraint(equalToConstant: 48),
            categoryIconView.heightAnchor.constraint(equalToConstant: 48),

            categoryLabel.leadingAnchor.constraint(equalTo: categoryIconView.trailingAnchor, constant: Metrics.spacing3),
            categoryLabel.bottomAnchor.constraint(equalTo: monthYearLabel.topAnchor, constant: -4),

            monthYearLabel.leadingAnchor.constraint(equalTo: categoryIconView.trailingAnchor, constant: Metrics.spacing3),
            monthYearLabel.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: -Metrics.spacing4),

            // Scroll
            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Summary Card
            summaryCardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing4),
            summaryCardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            summaryCardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),

            circularProgressView.topAnchor.constraint(equalTo: summaryCardView.topAnchor, constant: Metrics.spacing4),
            circularProgressView.leadingAnchor.constraint(equalTo: summaryCardView.leadingAnchor, constant: Metrics.spacing4),
            circularProgressView.widthAnchor.constraint(equalToConstant: 120),
            circularProgressView.heightAnchor.constraint(equalToConstant: 120),

            allocatedLabel.topAnchor.constraint(equalTo: summaryCardView.topAnchor, constant: Metrics.spacing4),
            allocatedLabel.leadingAnchor.constraint(equalTo: circularProgressView.trailingAnchor, constant: Metrics.spacing4),

            allocatedValueLabel.centerYAnchor.constraint(equalTo: allocatedLabel.centerYAnchor),
            allocatedValueLabel.trailingAnchor.constraint(equalTo: summaryCardView.trailingAnchor, constant: -Metrics.spacing4),

            usedLabel.topAnchor.constraint(equalTo: allocatedLabel.bottomAnchor, constant: Metrics.spacing3),
            usedLabel.leadingAnchor.constraint(equalTo: circularProgressView.trailingAnchor, constant: Metrics.spacing4),

            usedValueLabel.centerYAnchor.constraint(equalTo: usedLabel.centerYAnchor),
            usedValueLabel.trailingAnchor.constraint(equalTo: summaryCardView.trailingAnchor, constant: -Metrics.spacing4),

            remainingLabel.topAnchor.constraint(equalTo: usedLabel.bottomAnchor, constant: Metrics.spacing3),
            remainingLabel.leadingAnchor.constraint(equalTo: circularProgressView.trailingAnchor, constant: Metrics.spacing4),

            remainingValueLabel.centerYAnchor.constraint(equalTo: remainingLabel.centerYAnchor),
            remainingValueLabel.trailingAnchor.constraint(equalTo: summaryCardView.trailingAnchor, constant: -Metrics.spacing4),

            recurringBadge.topAnchor.constraint(equalTo: remainingLabel.bottomAnchor, constant: Metrics.spacing3),
            recurringBadge.leadingAnchor.constraint(equalTo: circularProgressView.trailingAnchor, constant: Metrics.spacing4),

            warningBanner.topAnchor.constraint(equalTo: circularProgressView.bottomAnchor, constant: Metrics.spacing3),
            warningBanner.leadingAnchor.constraint(equalTo: summaryCardView.leadingAnchor, constant: Metrics.spacing4),
            warningBanner.trailingAnchor.constraint(equalTo: summaryCardView.trailingAnchor, constant: -Metrics.spacing4),
            warningBanner.bottomAnchor.constraint(equalTo: summaryCardView.bottomAnchor, constant: -Metrics.spacing4),

            warningLabel.topAnchor.constraint(equalTo: warningBanner.topAnchor, constant: Metrics.spacing3),
            warningLabel.leadingAnchor.constraint(equalTo: warningBanner.leadingAnchor, constant: Metrics.spacing3),
            warningLabel.trailingAnchor.constraint(equalTo: warningBanner.trailingAnchor, constant: -Metrics.spacing3),
            warningLabel.bottomAnchor.constraint(equalTo: warningBanner.bottomAnchor, constant: -Metrics.spacing3),

            // Transactions
            transactionsHeaderLabel.topAnchor.constraint(equalTo: summaryCardView.bottomAnchor, constant: Metrics.spacing5),
            transactionsHeaderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),

            transactionsTableView.topAnchor.constraint(equalTo: transactionsHeaderLabel.bottomAnchor, constant: Metrics.spacing3),
            transactionsTableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            transactionsTableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            transactionsTableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing4),

            emptyStateView.topAnchor.constraint(equalTo: transactionsHeaderLabel.bottomAnchor, constant: Metrics.spacing3),
            emptyStateView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            emptyStateView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            emptyStateView.heightAnchor.constraint(equalToConstant: 120),

            // Actions
            actionButtonsContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionButtonsContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButtonsContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionButtonsContainerView.heightAnchor.constraint(equalToConstant: 100),

            editButton.topAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor, constant: Metrics.spacing3),
            editButton.leadingAnchor.constraint(equalTo: actionButtonsContainerView.leadingAnchor, constant: Metrics.spacing4),
            editButton.heightAnchor.constraint(equalToConstant: 48),

            deleteButton.topAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor, constant: Metrics.spacing3),
            deleteButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: Metrics.spacing3),
            deleteButton.trailingAnchor.constraint(equalTo: actionButtonsContainerView.trailingAnchor, constant: -Metrics.spacing4),
            deleteButton.widthAnchor.constraint(equalTo: editButton.widthAnchor, multiplier: 0.5),
            deleteButton.heightAnchor.constraint(equalToConstant: 48),
        ])

        tableHeightConstraint = transactionsTableView.heightAnchor.constraint(equalToConstant: 0)
        tableHeightConstraint?.isActive = true
    }

    // MARK: - Configuration

    func configure(with allocation: BudgetAllocation) {
        // Header
        headerContainerView.backgroundColor = allocation.status.color.withAlphaComponent(0.15)
        categoryIconView.image = UIImage(named: allocation.category.iconName)
        categoryLabel.text = allocation.category.displayName

        let date = Date(timeIntervalSince1970: TimeInterval(allocation.monthDate))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        monthYearLabel.text = formatter.string(from: date)

        // Progress
        circularProgressView.configure(
            percentage: allocation.usagePercentage,
            status: allocation.status,
            animated: true
        )

        // Summary
        allocatedValueLabel.text = allocation.allocatedAmount.currencyString
        usedValueLabel.text = allocation.usedAmount.currencyString
        remainingValueLabel.text = allocation.remainingAmount.currencyString

        let isOver = allocation.remainingAmount < 0
        remainingValueLabel.textColor = isOver ? Colors.mainRed : Colors.gray100

        recurringBadge.isHidden = !allocation.isRecurring

        // Warning
        if isOver {
            warningBanner.isHidden = false
            warningLabel.text = String(
                format: "allocation.warning.exceeded".localized,  // "You've exceeded this allocation by %@"
                abs(allocation.remainingAmount).currencyString
            )
        } else {
            warningBanner.isHidden = true
        }

        // Transactions header
        transactionsHeaderLabel.text = "allocation.details.transactions.header".localized
    }

    func updateTableHeight(rowCount: Int, rowHeight: CGFloat = 72) {
        tableHeightConstraint?.constant = max(CGFloat(rowCount) * rowHeight, 0)
        transactionsTableView.isHidden = rowCount == 0
        emptyStateView.isHidden = rowCount > 0
        layoutIfNeeded()
    }

    func setTransactionCount(_ count: Int) {
        transactionsHeaderLabel.text = String(
            format: "allocation.details.transactions.count.format".localized,
            count
        )
    }
}
```

---

### ✅ Phase 3 Checkpoint

At this point you should be able to:
1. **Flip to BudgetCard** and see the donut chart with mock allocations
2. **See allocation rows** with progress bars and status colors
3. **Tap an allocation** (prints to console for now)
4. **See the Detail Screen** (if you wire up navigation with mock data)

The UI is complete with hardcoded/mock data. Now we add real data persistence.

---

## Phase 4: Data Layer (Repository & Service)

> **Goal**: Create data persistence. UI still uses mock data until Phase 5.

### Understanding This Phase

This phase implements the **data layer** - how data is stored and retrieved. We use two patterns:

**Repository Pattern (Section 3.6 reminder):**
- Handles ONLY database operations (CRUD: Create, Read, Update, Delete)
- Doesn't know about business rules
- Returns raw data models

**Service Pattern:**
- Contains business logic (calculations, validations)
- Uses repositories to get/save data
- Returns display-ready data

```
┌──────────────────┐     ┌─────────────────────┐     ┌──────────────┐
│   ViewController │────▶│       Service       │────▶│  Repository  │
│                  │     │   (business logic)  │     │  (database)  │
│  "Show me the    │     │                     │     │              │
│   allocations"   │     │  1. Get allocations │     │  fetch()     │
│                  │     │  2. Get transactions│     │  insert()    │
│                  │◀────│  3. Calculate usage │◀────│  update()    │
│                  │     │  4. Return combined │     │  delete()    │
└──────────────────┘     └─────────────────────┘     └──────────────┘
```

---

### Step 4.1: Create BudgetAllocationRepository

**File:** `Finova/Sources/Core/Repositories/BudgetAllocationRepository/BudgetAllocationRepository.swift`

> **Codable + JSON** - We store allocations as JSON data using Swift's `JSONEncoder`/`JSONDecoder`. The `Codable` protocol we added to `BudgetAllocationModel` makes this automatic. See Section 3.0.6 for details.

```swift
import Foundation

// ═══════════════════════════════════════════════════════════════════
// REPOSITORY PATTERN
//
// A Repository is a "gatekeeper" for the database. All data access
// goes through it. This has several benefits:
//
// 1. ABSTRACTION: The rest of the app doesn't know HOW data is stored
//    (Could be JSON file, SQLite, Core Data, or a server)
//
// 2. SINGLE RESPONSIBILITY: Only knows about CRUD operations
//    (No business logic like "is this allocation over budget?")
//
// 3. TESTABILITY: You can create a mock repository for testing
//    that doesn't touch real storage
//
// In this app, we use SecureLocalDataManager to store JSON data
// securely in the Keychain/encrypted storage.
// ═══════════════════════════════════════════════════════════════════

final class BudgetAllocationRepository {
    private let secureStorage = SecureLocalDataManager.shared
    private let storageKey = "budget_allocations"

    // MARK: - CRUD Operations

    func insert(_ allocation: BudgetAllocationModel) throws -> Int {
        var allocations = fetchAllModels()

        if allocations.contains(where: {
            $0.monthDate == allocation.monthDate && $0.categoryKey == allocation.categoryKey
        }) {
            throw BudgetAllocationError.duplicateAllocation
        }

        let newId = (allocations.map { $0.id ?? 0 }.max() ?? 0) + 1
        let newAllocation = BudgetAllocationModel(
            id: newId,
            monthDate: allocation.monthDate,
            categoryKey: allocation.categoryKey,
            allocatedAmount: allocation.allocatedAmount,
            isRecurring: allocation.isRecurring,
            parentAllocationId: allocation.parentAllocationId
        )

        allocations.append(newAllocation)
        try save(allocations)
        return newId
    }

    func update(_ allocation: BudgetAllocationModel) throws {
        var allocations = fetchAllModels()
        guard let index = allocations.firstIndex(where: { $0.id == allocation.id }) else {
            throw BudgetAllocationError.allocationNotFound
        }
        allocations[index] = allocation
        try save(allocations)
    }

    func delete(id: Int) throws {
        var allocations = fetchAllModels()
        allocations.removeAll { $0.id == id }
        try save(allocations)
    }

    func fetchAllocations(forMonth monthAnchor: Int) -> [BudgetAllocation] {
        return fetchAllModels()
            .filter { $0.monthDate == monthAnchor }
            .map { BudgetAllocation(from: $0) }
    }

    func fetchAllocation(byId id: Int) -> BudgetAllocationModel? {
        return fetchAllModels().first { $0.id == id }
    }

    func fetchRecurringAllocations() -> [BudgetAllocationModel] {
        return fetchAllModels().filter { $0.isRecurring && $0.parentAllocationId == nil }
    }

    func fetchAllocationInstances(forParent parentId: Int) -> [BudgetAllocationModel] {
        return fetchAllModels().filter { $0.parentAllocationId == parentId }
    }

    // MARK: - Private

    private func fetchAllModels() -> [BudgetAllocationModel] {
        guard let data = secureStorage.getData(forKey: storageKey),
              let allocations = try? JSONDecoder().decode([BudgetAllocationModel].self, from: data) else {
            return []
        }
        return allocations
    }

    private func save(_ allocations: [BudgetAllocationModel]) throws {
        let data = try JSONEncoder().encode(allocations)
        secureStorage.setData(data, forKey: storageKey)
    }
}
```

### Step 4.2: Create BudgetAllocationService

**File:** `Finova/Sources/Core/Services/BudgetAllocationService.swift`

> **Service Layer** - This is where business logic lives. The service coordinates between multiple repositories and performs calculations. ViewModels call the service, never the repository directly.

```swift
import Foundation

// ═══════════════════════════════════════════════════════════════════
// SERVICE PATTERN
//
// Services contain BUSINESS LOGIC - the rules that make your app unique.
//
// For allocations, business logic includes:
// - Calculating how much has been spent (by querying transactions)
// - Checking if an allocation exists before creating a duplicate
// - Generating recurring allocation instances
// - Combining data from multiple sources
//
// WHY NOT put this in the Repository?
// - Repositories should be "dumb" - just save/load data
// - Business rules change more often than storage
// - Easier to test business logic separately
//
// WHY NOT put this in the ViewModel?
// - Multiple ViewModels might need the same logic
// - Keeps ViewModels focused on UI state
// - Service can be used by other services
// ═══════════════════════════════════════════════════════════════════

final class BudgetAllocationService {
    private let allocationRepo: BudgetAllocationRepository
    private let transactionRepo: TransactionRepository
    private let budgetRepo: BudgetRepository

    init(
        allocationRepo: BudgetAllocationRepository = BudgetAllocationRepository(),
        transactionRepo: TransactionRepository = TransactionRepository(),
        budgetRepo: BudgetRepository = BudgetRepository()
    ) {
        self.allocationRepo = allocationRepo
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
    }

    // MARK: - Create

    func createAllocation(
        category: TransactionCategory,
        amount: Int,
        monthAnchor: Int,
        isRecurring: Bool
    ) throws -> Int {
        guard amount > 0 else { throw BudgetAllocationError.invalidAmount }

        let model = BudgetAllocationModel(
            monthDate: monthAnchor,
            categoryKey: category.key,
            allocatedAmount: amount,
            isRecurring: isRecurring
        )
        return try allocationRepo.insert(model)
    }

    // MARK: - Update

    func updateAllocation(id: Int, newAmount: Int) throws {
        guard let existing = allocationRepo.fetchAllocation(byId: id) else {
            throw BudgetAllocationError.allocationNotFound
        }

        let updated = BudgetAllocationModel(
            id: existing.id,
            monthDate: existing.monthDate,
            categoryKey: existing.categoryKey,
            allocatedAmount: newAmount,
            isRecurring: existing.isRecurring,
            parentAllocationId: existing.parentAllocationId
        )
        try allocationRepo.update(updated)
    }

    // MARK: - Delete

    func deleteAllocation(id: Int, deleteAllFuture: Bool = false) throws {
        if deleteAllFuture {
            let instances = allocationRepo.fetchAllocationInstances(forParent: id)
            for instance in instances {
                if let instanceId = instance.id {
                    try allocationRepo.delete(id: instanceId)
                }
            }
        }
        try allocationRepo.delete(id: id)
    }

    // MARK: - Fetch

    func getAllocationsWithUsage(forMonth monthAnchor: Int) -> [BudgetAllocation] {
        var allocations = allocationRepo.fetchAllocations(forMonth: monthAnchor)
        let usageByCategory = calculateUsageByCategory(forMonth: monthAnchor)

        for i in allocations.indices {
            let categoryKey = allocations[i].category.key
            allocations[i].setUsedAmount(usageByCategory[categoryKey] ?? 0)
        }
        return allocations
    }

    func getUnallocatedSummary(forMonth monthAnchor: Int) -> UnallocatedBudgetSummary {
        let budgets = budgetRepo.fetchBudgets()
        let budget = budgets.first { $0.monthDate == monthAnchor }
        let totalBudget = budget?.amount ?? 0

        let allocations = allocationRepo.fetchAllocations(forMonth: monthAnchor)
        let totalAllocated = allocations.reduce(0) { $0 + $1.allocatedAmount }

        let allocatedCategories = Set(allocations.map { $0.category.key })
        let usageByCategory = calculateUsageByCategory(forMonth: monthAnchor)
        let unallocatedUsage = usageByCategory
            .filter { !allocatedCategories.contains($0.key) }
            .reduce(0) { $0 + $1.value }

        return UnallocatedBudgetSummary(
            monthDate: monthAnchor,
            totalBudget: totalBudget,
            totalAllocated: totalAllocated,
            totalUsedInUnallocatedCategories: unallocatedUsage
        )
    }

    func getTransactions(forCategory category: TransactionCategory, monthAnchor: Int) -> [Transaction] {
        return transactionRepo.fetchAllTransactions().filter { transaction in
            transaction.category == category &&
            transaction.budgetMonthDate == monthAnchor &&
            transaction.type == .expense
        }.sorted { $0.date > $1.date }
    }

    // MARK: - Private

    private func calculateUsageByCategory(forMonth monthAnchor: Int) -> [String: Int] {
        let transactions = transactionRepo.fetchAllTransactions()
            .filter { $0.budgetMonthDate == monthAnchor && $0.type == .expense }

        var usage: [String: Int] = [:]
        for transaction in transactions {
            usage[transaction.category.key, default: 0] += transaction.amount
        }
        return usage
    }
}
```

---

## Phase 5: Connect Data to UI

> **Goal**: Replace mock data with real data from services.

### Understanding This Phase

This is where everything comes together. We'll:
1. Create a **ViewModel** that uses the Service
2. Update the **ViewController** to use the ViewModel
3. Replace **mock data** with real data

**The Complete Data Flow:**

```
User taps "flip to budget" button
           │
           ▼
MonthCarouselCell.didRequestFlip()
           │
           ▼
BudgetAllocationService.getAllocationsWithUsage(forMonth:)
           │
           ├──▶ BudgetAllocationRepository.fetchAllocations()
           │              │
           │              ▼
           │         [BudgetAllocation] (with usedAmount = 0)
           │
           ├──▶ TransactionRepository.fetchAllTransactions()
           │              │
           │              ▼
           │         Calculate usage by category
           │
           ▼
    [BudgetAllocation] (with usedAmount filled in)
           │
           ▼
BudgetCard.configure(allocations:)
           │
           ▼
    UITableView.reloadData()  →  AllocationCell displays each allocation
```

---

### Step 5.1: Create BudgetAllocationDetailsViewModel

> **MVVM Reminder (Section 3.7)**: The ViewModel holds data and logic. It doesn't know about UIKit. The ViewController asks it for data and tells it when actions happen.

**File:** `Finova/Sources/Scenes/BudgetAllocationDetails/ViewModel/BudgetAllocationDetailsViewModel.swift`

```swift
import Foundation

// ═══════════════════════════════════════════════════════════════════
// VIEWMODEL PATTERN
//
// The ViewModel is the "brain" of a screen. It:
// 1. HOLDS the data the View needs to display
// 2. EXPOSES computed properties for formatted display values
// 3. HANDLES user actions (delete, edit) via methods
// 4. CALLS the Service for business operations
// 5. NOTIFIES the ViewController when data changes
//
// The ViewModel does NOT:
// - Know about UIKit (no UILabel, UIButton, etc.)
// - Talk directly to the database (uses Service)
// - Navigate to other screens (uses FlowDelegate)
//
// This separation means you can:
// - Test the ViewModel without a UI
// - Reuse the ViewModel with a different UI (iPad layout, etc.)
// - Change the UI without touching business logic
// ═══════════════════════════════════════════════════════════════════

final class BudgetAllocationDetailsViewModel {

    // ─────────────────────────────────────────────────────────────
    // DEPENDENCIES
    //
    // `private let` means:
    // - Only this class can access these
    // - They can't be changed after init
    //
    // The service is injected via init() for testability.
    // In tests, you can pass a mock service.
    // ─────────────────────────────────────────────────────────────
    private let allocation: BudgetAllocation
    private let allocationService: BudgetAllocationService

    // ─────────────────────────────────────────────────────────────
    // private(set) = External code can READ but not WRITE
    //
    // The ViewController needs to read transactions for the table,
    // but shouldn't directly modify the array.
    // ─────────────────────────────────────────────────────────────
    private(set) var transactions: [Transaction] = []

    // MARK: - Computed

    var category: TransactionCategory { allocation.category }
    var allocatedAmount: Int { allocation.allocatedAmount }
    var usedAmount: Int { allocation.usedAmount }
    var remainingAmount: Int { allocation.remainingAmount }
    var usagePercentage: Double { allocation.usagePercentage }
    var status: AllocationStatus { allocation.status }
    var isRecurring: Bool { allocation.isRecurring }
    var allocationId: Int? { allocation.id }
    var monthDate: Int { allocation.monthDate }

    var formattedAllocated: String { allocatedAmount.currencyString }
    var formattedUsed: String { usedAmount.currencyString }
    var formattedRemaining: String { remainingAmount.currencyString }
    var transactionCount: Int { transactions.count }
    var isOverBudget: Bool { remainingAmount < 0 }

    var monthYearString: String {
        let date = Date(timeIntervalSince1970: TimeInterval(allocation.monthDate))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var budgetAllocation: BudgetAllocation { allocation }

    // MARK: - Init

    init(allocation: BudgetAllocation, allocationService: BudgetAllocationService = BudgetAllocationService()) {
        self.allocation = allocation
        self.allocationService = allocationService
        loadTransactions()
    }

    func loadTransactions() {
        transactions = allocationService.getTransactions(
            forCategory: category,
            monthAnchor: allocation.monthDate
        )
    }

    // MARK: - Actions

    func updateAllocation(newAmount: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let id = allocationId else {
            completion(.failure(BudgetAllocationError.allocationNotFound))
            return
        }
        do {
            try allocationService.updateAllocation(id: id, newAmount: newAmount)
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    func deleteAllocation(deleteAllFuture: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let id = allocationId else {
            completion(.failure(BudgetAllocationError.allocationNotFound))
            return
        }
        do {
            try allocationService.deleteAllocation(id: id, deleteAllFuture: deleteAllFuture)
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
}
```

### Step 5.2: Update BudgetAllocationDetailsViewController

**File:** `Finova/Sources/Scenes/BudgetAllocationDetails/View/BudgetAllocationDetailsViewController.swift`

```swift
import UIKit

final class BudgetAllocationDetailsViewController: UIViewController {

    private let mainView = BudgetAllocationDetailsView()
    private let viewModel: BudgetAllocationDetailsViewModel
    weak var flowDelegate: BudgetAllocationDetailsFlowDelegate?

    init(allocation: BudgetAllocation) {
        self.viewModel = BudgetAllocationDetailsViewModel(allocation: allocation)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = mainView }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupTableView()
        setupActions()
        configureView()
    }

    private func setupTableView() {
        mainView.transactionsTableView.delegate = self
        mainView.transactionsTableView.dataSource = self
        mainView.transactionsTableView.register(
            TransactionCell.self,
            forCellReuseIdentifier: TransactionCell.reuseIdentifier
        )
    }

    private func setupActions() {
        mainView.backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        mainView.editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        mainView.deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }

    private func configureView() {
        mainView.configure(with: viewModel.budgetAllocation)
        mainView.updateTableHeight(rowCount: viewModel.transactionCount)
        mainView.setTransactionCount(viewModel.transactionCount)
        mainView.transactionsTableView.reloadData()
    }

    @objc private func backTapped() {
        flowDelegate?.dismissAllocationDetails()
    }

    @objc private func editTapped() {
        let alert = UIAlertController(
            title: "allocation.edit.title".localized,
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "allocation.edit.amount.placeholder".localized
            field.keyboardType = .decimalPad
            field.text = String(format: "%.2f", Double(self.viewModel.allocatedAmount) / 100)
        }
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "alert.save".localized, style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text,
                  let amount = Double(text) else { return }
            self?.viewModel.updateAllocation(newAmount: Int(amount * 100)) { result in
                if case .success = result {
                    self?.flowDelegate?.didUpdateAllocation()
                }
            }
        })
        present(alert, animated: true)
    }

    @objc private func deleteTapped() {
        if viewModel.isRecurring {
            // Recurring allocation: offer choice to delete this month or all future
            let alert = UIAlertController(
                title: "allocation.delete.recurring.title".localized,
                message: "allocation.delete.recurring.message".localized,
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(
                title: "allocation.delete.recurring.thisMonth".localized,
                style: .destructive
            ) { [weak self] _ in
                self?.performDelete(deleteAllFuture: false)
            })
            alert.addAction(UIAlertAction(
                title: "allocation.delete.recurring.allFuture".localized,
                style: .destructive
            ) { [weak self] _ in
                self?.performDelete(deleteAllFuture: true)
            })
            alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
            present(alert, animated: true)
        } else {
            // Single allocation: simple confirmation
            let alert = UIAlertController(
                title: "allocation.delete.title".localized,
                message: String(
                    format: "allocation.delete.message".localized,
                    viewModel.category.displayName
                ),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
            alert.addAction(UIAlertAction(
                title: "alert.delete".localized,
                style: .destructive
            ) { [weak self] _ in
                self?.performDelete(deleteAllFuture: false)
            })
            present(alert, animated: true)
        }
    }

    private func performDelete(deleteAllFuture: Bool) {
        viewModel.deleteAllocation(deleteAllFuture: deleteAllFuture) { [weak self] result in
            if case .success = result {
                self?.flowDelegate?.didDeleteAllocation()
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension BudgetAllocationDetailsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.transactionCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: TransactionCell.reuseIdentifier,
            for: indexPath
        ) as? TransactionCell else { return UITableViewCell() }

        cell.configure(with: viewModel.transactions[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate

extension BudgetAllocationDetailsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        flowDelegate?.navigateToTransactionDetails(transaction: viewModel.transactions[indexPath.row])
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 72 }
}
```

### Step 5.3: Update MonthCarouselCell to Use Real Data

Replace mock data in `didRequestFlip` with calls to the service:

```swift
// In MonthCarouselCell

private let allocationService = BudgetAllocationService()

func didRequestFlip(isShowingBudgetView: Bool) {
    if isShowingBudgetView {
        let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
        let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)
        flipToBudgetView(allocations: allocations, summary: summary)
    } else {
        flipToTransactionView()
    }
}
```

### Step 5.4: Wire Up Allocation Tap Navigation

Update the MonthCarouselCell to forward allocation taps to the parent:

```swift
// Add a parent delegate property
weak var parentFlowDelegate: DashboardFlowDelegate?

func didTapAllocation(_ allocation: BudgetAllocation) {
    parentFlowDelegate?.navigateToAllocationDetails(allocation: allocation)
}
```

Update ViewControllersFactory:

```swift
static func makeBudgetAllocationDetailsViewController(
    allocation: BudgetAllocation
) -> BudgetAllocationDetailsViewController {
    return BudgetAllocationDetailsViewController(allocation: allocation)
}
```

---

## Phase 6: Modal & Creation Flow

> **Goal**: Add allocation creation via modal.

### Understanding This Phase

We'll extend the existing Add Transaction modal to also create allocations. This is a common iOS pattern: **repurposing existing UI** by adding modes rather than creating entirely new screens.

**Key Decisions:**

| Decision | Why |
|----------|-----|
| **Segmented Control** | Clear visual indicator of mode |
| **Reuse existing modal** | Consistent UX, less code to maintain |
| **Separate save methods** | Each mode has different validation rules |

---

### Step 6.1: Add Segmented Control to AddTransactionModal

Add mode enum and UI:

```swift
enum ModalMode {
    case transaction
    case allocation
}

private var currentMode: ModalMode = .transaction

private lazy var modeSegmentedControl: UISegmentedControl = {
    let control = UISegmentedControl(items: ["Transaction", "Allocation"])
    control.selectedSegmentIndex = 0
    control.selectedSegmentTintColor = Colors.mainMagenta
    control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
    return control
}()

@objc private func modeChanged() {
    currentMode = modeSegmentedControl.selectedSegmentIndex == 0 ? .transaction : .allocation
    updateUIForMode()
}

private func updateUIForMode() {
    // Show/hide appropriate fields
}
```

### Step 6.2: Allocation-specific Fields

Add to modal:
- Category picker (reuse existing)
- Amount field
- Month picker (current month)
- Recurring toggle

### Step 6.3: Save Allocation

```swift
private func saveAllocation() {
    let service = BudgetAllocationService()
    do {
        _ = try service.createAllocation(
            category: selectedCategory,
            amount: amountInCents,
            monthAnchor: selectedMonthAnchor,
            isRecurring: recurringToggle.isOn
        )
        delegate?.didSaveAllocation()
        dismiss(animated: true)
    } catch {
        showError(error.localizedDescription)
    }
}
```

---

## Phase 7: Polish & Edge Cases

> **Goal**: Clean up mock data, handle edge cases, and prepare for production.

### Understanding This Phase

This final phase transitions the code from **development quality** to **production quality**. In software engineering, this includes:

1. **Removing scaffolding** - Mock data, placeholder views, print statements
2. **Handling edge cases** - Empty states, errors, unexpected data
3. **Adding reactivity** - Auto-refresh when data changes elsewhere
4. **Memory management** - Cleaning up observers, avoiding leaks

**Why Clean Up Mock Data?**

```swift
// DEVELOPMENT: Useful for testing UI quickly
static func mock() -> BudgetAllocation { ... }

// PRODUCTION: Dangerous!
// - Someone might accidentally use mock() in real code
// - Makes the codebase confusing ("Is this real or fake?")
// - Takes up space and maintenance burden
```

---

### Step 7.1: Remove Mock Data from Models

**File:** `Finova/Sources/Core/Repositories/BudgetAllocationRepository/BudgetAllocationModel.swift`

Remove the static `mock()` methods from `BudgetAllocation` and `UnallocatedBudgetSummary`:

```swift
// ❌ DELETE these methods from BudgetAllocation
static func mock(
    category: TransactionCategory = .meals,
    allocated: Int = 50000,
    used: Int = 37500,
    isRecurring: Bool = false
) -> BudgetAllocation { ... }

// ❌ DELETE this method from UnallocatedBudgetSummary
static func mock() -> UnallocatedBudgetSummary { ... }
```

### Step 7.2: Verify MonthCarouselCell Uses Real Data

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/MonthCarouselCell.swift`

Ensure `didRequestFlip` uses the service, not mocks:

```swift
// ✅ FINAL VERSION - Real data only
func didRequestFlip(isShowingBudgetView: Bool) {
    if isShowingBudgetView {
        let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
        let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)
        flipToBudgetView(allocations: allocations, summary: summary)
    } else {
        flipToTransactionView()
    }
}
```

### Step 7.3: Remove Placeholder Views

**File:** `BudgetAllocationDetailsView.swift`

If you kept any placeholder labels from Phase 1, remove them:

```swift
// ❌ DELETE if still present
private lazy var placeholderLabel: UILabel = { ... }()
```

**File:** `BudgetCard.swift`

Same - remove any placeholder labels:

```swift
// ❌ DELETE if still present
private lazy var placeholderLabel: UILabel = { ... }()
```

### Step 7.4: Handle Edge Cases

Add these behaviors:

**Empty State for No Allocations (BudgetCard):**

```swift
// In BudgetCard.configure()
if allocations.isEmpty {
    showEmptyState()  // "No allocations yet. Tap + to add one."
} else {
    hideEmptyState()
    allocationsTableView.reloadData()
}
```

**Over-Allocation Warning:**

```swift
// In BudgetCard.configure()
if summary.totalAllocated > summary.totalBudget {
    allocationProgressBar.progressTintColor = Colors.warningAmber
    allocationPercentLabel.textColor = Colors.warningAmber
    // Optionally show a warning banner
}
```

**Filter Transactions on Chart Segment Tap:**

```swift
// In MonthCarouselCell
func didSelectAllocationCategory(_ category: TransactionCategory) {
    // Flip back to transaction view with filter applied
    flipToTransactionView()

    // Apply category filter
    var filters = TransactionFilters()
    filters.categories = [category]
    delegate?.didUpdateFilters(filters, forMonth: monthAnchor)
}
```

### Step 7.5: Add Notification Observers for Refresh

**File:** `MonthCarouselCell.swift`

> **NotificationCenter** - iOS's built-in "broadcast" system. One object posts a notification, and ANY object listening for that notification receives it. This is how unrelated objects communicate without knowing about each other.

```swift
// ═══════════════════════════════════════════════════════════════════
// NOTIFICATION CENTER PATTERN
//
// Problem: User deletes an allocation in the detail screen.
//          The BudgetCard (on a different screen) shows stale data.
//
// Solution: When allocation is deleted:
//   1. Detail screen posts: "Hey everyone, an allocation was deleted!"
//   2. BudgetCard is LISTENING for that message
//   3. BudgetCard refreshes itself
//
// This is "loose coupling" - neither screen knows about the other.
// They just know about the notification NAME.
//
// IMPORTANT: Always remove observers in deinit to avoid:
//   - Memory leaks
//   - Crashes (calling methods on deallocated objects)
// ═══════════════════════════════════════════════════════════════════

// In init or awakeFromNib
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleAllocationChange),
    name: .allocationDidUpdate,
    object: nil
)

NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleAllocationChange),
    name: .allocationDidDelete,
    object: nil
)

@objc private func handleAllocationChange() {
    // Refresh BudgetCard if currently showing
    if isShowingBudgetView {
        let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
        let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)
        budgetCard.configure(
            month: monthCard.currentMonth,
            year: monthCard.currentYear,
            allocations: allocations,
            unallocatedSummary: summary
        )
    }
}
```

**Add Notification Names:**

```swift
// In a Notifications.swift or extension
extension Notification.Name {
    static let allocationDidUpdate = Notification.Name("allocationDidUpdate")
    static let allocationDidDelete = Notification.Name("allocationDidDelete")
}
```

### Step 7.6: Lazy Generation for Recurring Allocations

**File:** `BudgetAllocationService.swift`

> **Lazy Generation** - Instead of creating all future recurring instances upfront, we create them "on demand" when the user first views a month. This prevents database bloat and handles the infinite-future problem.

```
EAGER GENERATION (Bad):                LAZY GENERATION (Good):
─────────────────────────             ─────────────────────────
Create recurring for:                 Create ONLY when viewed:
  January   ✓                           January   ✓ (user is here)
  February  ✓                           February  ✓ (user scrolled)
  March     ✓                           March     (not created yet)
  April     ✓                           April     (not created yet)
  ...                                   ...
  Year 2050 ✓  ← Millions of rows!      (created when needed)
```

Add lazy generation when fetching allocations:

```swift
func getAllocationsWithUsage(forMonth monthAnchor: Int) -> [BudgetAllocation] {
    // Generate any missing recurring instances first
    generateRecurringInstancesIfNeeded(forMonth: monthAnchor)

    var allocations = allocationRepo.fetchAllocations(forMonth: monthAnchor)
    // ... rest of implementation
}

private func generateRecurringInstancesIfNeeded(forMonth monthAnchor: Int) {
    let recurringParents = allocationRepo.fetchRecurringAllocations()

    for parent in recurringParents {
        guard let parentId = parent.id,
              parent.monthDate < monthAnchor else { continue }

        // Check if instance already exists for this month
        let existingInstances = allocationRepo.fetchAllocationInstances(forParent: parentId)
        let hasInstance = existingInstances.contains { $0.monthDate == monthAnchor }

        if !hasInstance {
            let instance = BudgetAllocationModel(
                monthDate: monthAnchor,
                categoryKey: parent.categoryKey,
                allocatedAmount: parent.allocatedAmount,
                isRecurring: false,
                parentAllocationId: parentId
            )
            try? allocationRepo.insert(instance)
        }
    }
}
```

### Step 7.7: Final Cleanup Checklist

- [ ] All `mock()` methods removed from models
- [ ] No hardcoded test data in view controllers
- [ ] No placeholder labels remaining
- [ ] All `print()` debug statements removed
- [ ] All `// TODO` comments addressed or documented
- [ ] Localization keys use `.localized` instead of hardcoded strings
- [ ] No force unwraps (`!`) without proper validation
- [ ] Memory leaks checked (weak delegates, notification observers removed in deinit)

### Step 7.8: Verify Build

```bash
# Clean build folder and rebuild
xcodebuild clean build -scheme Finova -destination 'platform=iOS Simulator,name=iPhone 15'
```

Ensure:
- No compiler warnings related to unused code
- No references to deleted mock methods
- App launches and all features work with real data

---

### ✅ Phase 7 Checkpoint

At this point:
1. **No mock data** exists in the codebase
2. **All edge cases** are handled gracefully
3. **Notifications** keep UI in sync after changes
4. **Recurring allocations** generate automatically
5. **Code is production-ready**

---

## Testing Checklist

### Navigation
- [ ] Flip toggle icon visible in MonthBudgetCard header
- [ ] Card flips with animation when tapped
- [ ] Allocation rows are tappable
- [ ] Detail screen appears on row tap
- [ ] Back button returns to dashboard with card flipped

### BudgetCard
- [ ] Donut chart renders with correct segments
- [ ] Chart center shows unallocated by default
- [ ] Tapping segment highlights and shows category
- [ ] Progress bar shows allocation percentage
- [ ] Warning color when over-allocated

### Detail Screen
- [ ] Header color matches status
- [ ] Circular progress animates
- [ ] Summary values are correct
- [ ] Recurring badge shows for recurring allocations
- [ ] Warning banner shows when over budget
- [ ] Transactions list filtered correctly
- [ ] Empty state when no transactions
- [ ] Edit updates allocation
- [ ] Delete removes allocation
- [ ] Recurring delete shows options

---

## Localization Keys

> **Note:** You should add these keys to your `Localizable.xcstrings` file BEFORE implementing the code. This way, all UI text is localized from the start.

```swift
// ═══════════════════════════════════════════════════════════════════
// ALLOCATION STATUS (used in AllocationStatus enum)
// ═══════════════════════════════════════════════════════════════════
"allocation.status.under" = "Under";
"allocation.status.near" = "Near";
"allocation.status.over" = "Over";

// ═══════════════════════════════════════════════════════════════════
// ERRORS (used in BudgetAllocationError enum)
// ═══════════════════════════════════════════════════════════════════
"allocation.error.duplicate" = "Allocation already exists for this category";
"allocation.error.notFound" = "Allocation not found";
"allocation.error.invalidAmount" = "Invalid amount";

// ═══════════════════════════════════════════════════════════════════
// DETAIL SCREEN - Summary Section
// ═══════════════════════════════════════════════════════════════════
"allocation.details.summary.allocated" = "Allocated";
"allocation.details.summary.used" = "Used";
"allocation.details.summary.remaining" = "Remaining";
"allocation.details.summary.recurring" = "Recurring";

// ═══════════════════════════════════════════════════════════════════
// DETAIL SCREEN - Transactions Section
// ═══════════════════════════════════════════════════════════════════
"allocation.details.transactions.header" = "Transactions";
"allocation.details.transactions.empty" = "No transactions yet";

// ═══════════════════════════════════════════════════════════════════
// DETAIL SCREEN - Warning Banner
// ═══════════════════════════════════════════════════════════════════
"allocation.warning.exceeded" = "You've exceeded this allocation by %@";  // %@ = currency amount

// ═══════════════════════════════════════════════════════════════════
// DETAIL SCREEN - Actions
// ═══════════════════════════════════════════════════════════════════
"allocation.details.action.edit" = "Edit Allocation";
"allocation.details.action.delete" = "Delete";

// ═══════════════════════════════════════════════════════════════════
// EDIT ALLOCATION ALERT
// ═══════════════════════════════════════════════════════════════════
"allocation.edit.title" = "Edit Allocation";
"allocation.edit.amount.placeholder" = "Amount";

// ═══════════════════════════════════════════════════════════════════
// DELETE ALLOCATION ALERTS
// ═══════════════════════════════════════════════════════════════════
"allocation.delete.title" = "Delete Allocation?";
"allocation.delete.message" = "Remove %@ allocation?";  // %@ = category name
"allocation.delete.recurring.title" = "Delete Recurring Allocation?";
"allocation.delete.recurring.message" = "Choose which occurrences to delete";
"allocation.delete.recurring.thisMonth" = "This Month Only";
"allocation.delete.recurring.allFuture" = "All Future Months";

// ═══════════════════════════════════════════════════════════════════
// GENERIC ALERTS (may already exist in your project)
// ═══════════════════════════════════════════════════════════════════
"alert.cancel" = "Cancel";
"alert.delete" = "Delete";
"alert.save" = "Save";

// ═══════════════════════════════════════════════════════════════════
// BUDGET CARD (back of MonthBudgetCard)
// ═══════════════════════════════════════════════════════════════════
"budget.allocations.title" = "Budget Allocations";
"budget.unallocated" = "Unallocated";
"budget.limit.format" = "Budget: %@";           // %@ = currency amount
"budget.allocated.percent" = "%d%% allocated";  // %d = percentage number
"budget.allocated.label" = "Allocated";         // Footer left column header
"budget.percent.label" = "Budget";              // Footer right column header

// ═══════════════════════════════════════════════════════════════════
// MODAL - Segmented Control
// ═══════════════════════════════════════════════════════════════════
"modal.segment.transaction" = "Transaction";
"modal.segment.allocation" = "Allocation";
```

### How to Use Localization in Swift

All strings use the `.localized` extension (already in your codebase):

```swift
// In UIKit views:
label.text = "allocation.status.under".localized

// In SwiftUI:
Text("budget.unallocated".localized)

// With format arguments:
String(format: "allocation.warning.over".localized, overAmount)
```

---

## Summary

| Phase | What You Build | What You See |
|-------|---------------|--------------|
| 1 | Scaffolding, protocols, empty views | Flip animation, placeholder screens |
| 2 | Complete data models with `mock()` methods | Same UI, code compiles |
| 3 | Full UI components | Complete visual design with mock data |
| 4 | Repository & Service | Same UI (data layer ready, not connected) |
| 5 | Connect data to UI | Real data displayed (mocks still exist but unused) |
| 6 | Modal creation | Full create/edit flow |
| 7 | Polish & remove mocks | Production-ready, no test data in codebase |

### Mock Data Lifecycle

```
Phase 1-2: Create mock() methods in models
     ↓
Phase 3:   UI components use mocks via didRequestFlip()
     ↓
Phase 4:   Data layer built (mocks still used)
     ↓
Phase 5:   Switch to real data (mocks become unused)
     ↓
Phase 7:   DELETE all mock() methods and placeholders
```

Follow each phase in order. Run the app after each step to verify progress visually.

---

## Quick Reference: Swift Concepts Used in This Guide

For new Swift developers, here's a quick lookup of concepts used throughout this guide:

### Language Basics

| Concept | Syntax | Section |
|---------|--------|---------|
| Constant | `let name = "value"` | 3.0.1 |
| Variable | `var count = 0` | 3.0.1 |
| Optional | `var name: String?` | 3.0.2 |
| Force unwrap | `name!` (dangerous) | 3.0.2 |
| Optional chaining | `name?.count` | 3.0.2 |
| Nil coalescing | `name ?? "default"` | 3.0.2 |
| Safe unwrap | `if let x = optional { }` | 3.0.2 |
| Guard | `guard let x = opt else { return }` | 3.10 |

### Types

| Concept | When to Use | Section |
|---------|-------------|---------|
| `struct` | Data containers (copied) | 3.0.3 |
| `class` | Objects with identity (shared) | 3.0.3 |
| `enum` | Fixed set of options | 3.0.4 |
| `protocol` | Contracts/interfaces | 3.1 |

### Properties

| Concept | Syntax | Section |
|---------|--------|---------|
| Stored | `var x = 0` | 3.5 |
| Computed | `var x: Int { return y * 2 }` | 3.5 |
| Lazy | `lazy var x = { ... }()` | 3.3 |
| private | `private var x` | 3.9 |
| private(set) | `private(set) var x` | 3.9 |

### Methods

| Concept | Syntax | Use Case |
|---------|--------|----------|
| Instance method | `func doThing()` | Called on an object |
| Static method | `static func mock()` | Called on the type |
| Mutating method | `mutating func set()` | Modifies struct |
| @objc | `@objc func tap()` | Used with #selector |

### Closures & Callbacks

| Concept | Syntax | Section |
|---------|--------|---------|
| Closure | `{ param in return value }` | 3.0.5 |
| Trailing closure | `func { ... }` | 3.0.5 |
| @escaping | `@escaping (Result) -> Void` | 3.11 |
| [weak self] | `{ [weak self] in ... }` | 3.12 |

### iOS Patterns

| Pattern | Purpose | Section |
|---------|---------|---------|
| Delegate | Parent-child communication | 3.1 |
| MVVM | Separating View/ViewModel/Model | 3.7 |
| Repository | Database abstraction | 3.6 |
| Service | Business logic | 3.6 |
| NotificationCenter | Broadcast messaging | 7.5 |

### Memory Management

| Concept | Syntax | Why |
|---------|--------|-----|
| weak var delegate | `weak var delegate: X?` | Prevents retain cycles |
| [weak self] | In escaping closures | Prevents retain cycles |
| deinit | `deinit { }` | Cleanup when deallocated |

---

## Further Learning

After completing this guide, you'll have practical experience with:

✅ Swift fundamentals (optionals, structs, enums, closures)
✅ UIKit views and view controllers
✅ Auto Layout constraints
✅ Table views with custom cells
✅ MVVM architecture
✅ Repository and Service patterns
✅ SwiftUI integration in UIKit apps
✅ Core Animation (CAShapeLayer)
✅ Notification Center

**Recommended next steps:**
1. Apple's Swift Programming Language book (free online)
2. Ray Wenderlich iOS tutorials
3. Stanford's CS193p course (free on YouTube)
4. Build your own feature following the patterns in this guide
