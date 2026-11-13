# Finova Monetization Strategy

## Core Principle

Maximize developer revenue by making web-based payments the primary channel (keep ~97% of revenue) while offering StoreKit as a secondary option for convenience (keep 85%). All AI processing runs on-device using native iOS frameworks, meaning **zero ongoing infrastructure costs** regardless of user scale.

---

## Subscription Tiers

### Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                     FINOVA SUBSCRIPTION TIERS                    │
├──────────────┬───────────────────┬───────────────────────────────┤
│     FREE     │       PRO         │         INTELLIGENCE          │
│    $0/mo     │  $3.99-4.99/mo    │        $7.99-9.99/mo          │
├──────────────┼───────────────────┼───────────────────────────────┤
│ Core         │ Everything Free + │ Everything Pro +              │
│ budgeting    │ Budget allocation │ AI statement parsing          │
│ Manual       │ CloudKit sync     │ Auto-categorization           │
│ transactions │ Family sharing    │ Spending predictions          │
│ Basic        │ Credit card mgmt  │ Anomaly detection             │
│ categories   │ Unlimited budgets │ Notification intelligence     │
│ Basic        │ Advanced reports  │ Savings recommendations       │
│ reports      │ Priority support  │ Smart insights                │
└──────────────┴───────────────────┴───────────────────────────────┘
```

---

### Tier 1: Free

The free tier must be genuinely useful. A generous free tier converts better than a crippled one that frustrates users. The goal is to get users hooked on the habit of tracking finances with Finova, then upgrade when they outgrow the limits.

| Feature | Details |
|---------|---------|
| Manual transaction entry | Unlimited |
| Basic categories | Up to 8 custom categories |
| Basic budget overview | Monthly view only |
| Basic reports | Current month summary |
| Transaction history | Last 3 months |
| Single device | No sync |
| Credit card tracking | 1 card |
| Local data storage | On-device only |

**Why this works**: Users can genuinely manage their finances. The limitations are felt over time (wanting more history, more categories, multiple devices), creating natural upgrade pressure without frustration.

---

### Tier 2: Pro

The core power-user tier. Budget allocation and sync/sharing are the anchor features here because they solve the two biggest pain points: "Where should my money go?" and "I need this on all my devices / shared with my partner."

| Feature | Details |
|---------|---------|
| Everything in Free | |
| **Budget allocation** | Full allocation by category with rollover |
| **CloudKit sync** | Real-time sync across all devices |
| **Family/partner sharing** | Up to 5 members, shared budgets and visibility |
| **Credit card management** | Unlimited cards, statement tracking, due date alerts |
| **Unlimited budgets** | No category cap |
| **Advanced reports** | Monthly, quarterly, yearly breakdowns with charts |
| **Transaction history** | Unlimited |
| **Data export** | CSV/PDF export |
| **Priority support** | Direct email support |

**Pricing**:

| Channel | Monthly | Annual | Annual Savings |
|---------|---------|--------|----------------|
| Web (Stripe/PIX) | $3.99 | $29.99 | 37% |
| App Store (StoreKit) | $4.99 | $39.99 | 33% |

**Why the price difference**: The web price is lower because the payment processing fees are lower. Users get a better deal, and the developer keeps more per subscriber. Both sides win.

| Channel | Monthly Price | Fee | Developer Keeps | Margin |
|---------|--------------|-----|-----------------|--------|
| Web $3.99/mo | $3.99 | ~$0.42 | **$3.57** | 89.5% |
| StoreKit $4.99/mo | $4.99 | $0.75 | **$4.24** | 85.0% |
| Web $29.99/yr | $29.99 | ~$1.17 | **$28.82** | 96.1% |
| StoreKit $39.99/yr | $39.99 | $6.00 | **$33.99** | 85.0% |

---

### Tier 3: Intelligence

The premium tier built around the AI feature set (v1.7.0+). This tier is the differentiator - no other budget app in the market offers on-device, privacy-first AI financial intelligence.

| Feature | Details |
|---------|---------|
| Everything in Pro | |
| **Bank statement parsing** | Import PDF/image statements, auto-extract transactions |
| **Auto-categorization** | AI-powered category suggestions that learn from your corrections |
| **Spending predictions** | Forecast next month's spending based on patterns |
| **Anomaly detection** | Alerts for unusual transactions or spending spikes |
| **Notification intelligence** | Parse bank notifications to auto-log transactions (with permission) |
| **Savings recommendations** | AI-driven suggestions for where to cut spending |
| **Smart insights** | Weekly/monthly AI-generated financial health summaries |
| **Budget optimization** | Suggestions for reallocating budget based on actual patterns |

**Pricing**:

| Channel | Monthly | Annual | Annual Savings |
|---------|---------|--------|----------------|
| Web (Stripe/PIX) | $7.99 | $59.99 | 37% |
| App Store (StoreKit) | $9.99 | $79.99 | 33% |

| Channel | Monthly Price | Fee | Developer Keeps | Margin |
|---------|--------------|-----|-----------------|--------|
| Web $7.99/mo | $7.99 | ~$0.53 | **$7.46** | 93.4% |
| StoreKit $9.99/mo | $9.99 | $1.50 | **$8.49** | 85.0% |
| Web $59.99/yr | $59.99 | ~$2.04 | **$57.95** | 96.6% |
| StoreKit $79.99/yr | $79.99 | $12.00 | **$67.99** | 85.0% |

**Why this justifies the premium**: All AI processing happens on-device, which means zero server costs. But the user doesn't know or care about that - they see magic. Statement parsing alone saves hours of manual entry per month. At $7.99/mo, the app pays for itself if it saves the user even 30 minutes.

---

## Feature Gate Matrix

| Feature | Free | Pro | Intelligence |
|---------|------|-----|-------------|
| Manual transactions | Unlimited | Unlimited | Unlimited |
| Custom categories | 8 | Unlimited | Unlimited |
| Budget overview | Monthly | Monthly/Quarterly/Yearly | Monthly/Quarterly/Yearly |
| Reports | Current month | Full history + charts | Full history + charts |
| Transaction history | 3 months | Unlimited | Unlimited |
| Budget allocation | - | Full | Full |
| CloudKit sync | - | Multi-device | Multi-device |
| Family sharing | - | Up to 5 members | Up to 5 members |
| Credit cards | 1 card | Unlimited | Unlimited |
| Data export | - | CSV/PDF | CSV/PDF |
| Priority support | - | Email | Email |
| AI statement parsing | - | - | Full |
| Auto-categorization | - | - | Full |
| Spending predictions | - | - | Full |
| Anomaly detection | - | - | Full |
| Notification parsing | - | - | Full |
| Savings insights | - | - | Full |

---

## Payment Architecture: Web-First Strategy

### Why Web-First

```
Revenue per $7.99/mo Intelligence subscriber (annual):

  App Store only:   $7.99 x 12 = $95.88 → Apple takes $14.38 → You keep $81.50
  Web only:         $7.99 x 12 = $95.88 → Stripe takes $8.40  → You keep $87.48
  Web annual:       $59.99/yr            → Stripe takes $2.04  → You keep $57.95

  Difference per subscriber per year: +$5.98 (web monthly) to +$23.96 (web annual vs StoreKit annual)

  At 1,000 paying subscribers: +$5,980 to +$23,960 more per year
  At 10,000 paying subscribers: +$59,800 to +$239,600 more per year
```

### Payment Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    USER UPGRADE FLOW                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
              "Unlock Pro" / "Unlock Intelligence"
                       │
         ┌─────────────┴──────────────┐
         │                            │
    ┌────▼─────┐              ┌───────▼────────┐
    │   WEB    │              │   APP STORE    │
    │ (primary)│              │  (secondary)   │
    └────┬─────┘              └───────┬────────┘
         │                            │
    ┌────▼─────────────┐     ┌───────▼────────┐
    │ Safari/In-App    │     │   StoreKit 2   │
    │ Checkout Page    │     │   Payment      │
    │                  │     │   Sheet        │
    │ ┌──────────────┐ │     └───────┬────────┘
    │ │   Stripe     │ │             │
    │ │   Checkout   │ │             │
    │ └──────┬───────┘ │             │
    │        │ OR      │             │
    │ ┌──────▼───────┐ │             │
    │ │     PIX      │ │             │
    │ │   (Brazil)   │ │             │
    │ └──────────────┘ │             │
    └────────┬─────────┘             │
             │                       │
    ┌────────▼───────────────────────▼────────┐
    │         Firebase Cloud Functions         │
    │  (Stripe webhooks + StoreKit Server      │
    │   Notifications V2)                      │
    └────────────────────┬────────────────────┘
                         │
                ┌────────▼────────┐
                │    Firestore    │
                │ (subscription   │
                │    status)      │
                └────────┬────────┘
                         │
                ┌────────▼────────┐
                │    App checks   │
                │    entitlement  │
                │    on launch    │
                └─────────────────┘
```

### Technical Stack

| Component | Technology | Cost |
|-----------|-----------|------|
| Web payments | Stripe Checkout | ~2.9% + $0.30/tx |
| Brazil payments | PIX via Stripe or direct | ~0.5-1% |
| In-app payments | StoreKit 2 | 15% (Small Business Program) |
| Subscription backend | Firebase Cloud Functions | Free tier (2M invocations/mo) |
| Subscription storage | Firestore | Free tier (50K reads/day) |
| Auth (existing) | Firebase Auth | Free tier |
| Receipt validation | StoreKit Server Notifications V2 | Free |

### Apple Small Business Program

Enroll immediately. Requirements:
- Earn less than $1M/year in App Store proceeds (you will for a long time)
- Commission drops from **30% to 15%** on all StoreKit transactions
- No downside, free to enroll
- Apply at: https://developer.apple.com/app-store/small-business-program/

### Apple Compliance

Post-DMA (EU) and post-Epic ruling (US), apps are allowed to link to external purchase pages. The rules require:

1. StoreKit must be offered as **an** option (not necessarily the primary one)
2. External links are permitted with appropriate disclosure
3. Users must be informed they're leaving the app for payment

The upgrade screen in the app will present both options, with web pricing shown prominently due to the lower price.

---

## Upgrade Screen Design

```
┌─────────────────────────────────────────┐
│              Unlock Finova              │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │           INTELLIGENCE            │  │
│  │          $7.99/month              │  │
│  │    or $59.99/year (save 37%)      │  │
│  │                                   │  │
│  │  Everything in Pro, plus:         │  │
│  │  ● AI bank statement import      │  │
│  │  ● Auto-categorization           │  │
│  │  ● Spending predictions          │  │
│  │  ● Smart financial insights      │  │
│  │                                   │  │
│  │  [Subscribe via Web - Best Price] │  │
│  │  [Subscribe via App Store]        │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │              PRO                  │  │
│  │          $3.99/month              │  │
│  │    or $29.99/year (save 37%)      │  │
│  │                                   │  │
│  │  ● Budget allocation             │  │
│  │  ● Sync across all devices       │  │
│  │  ● Family/partner sharing        │  │
│  │  ● Unlimited credit cards        │  │
│  │  ● Advanced reports              │  │
│  │                                   │  │
│  │  [Subscribe via Web - Best Price] │  │
│  │  [Subscribe via App Store]        │  │
│  └───────────────────────────────────┘  │
│                                         │
│            Continue with Free            │
└─────────────────────────────────────────┘
```

---

## Founders Program

### Purpose

Reward early adopters who used the app before monetization was introduced. This builds loyalty, generates word-of-mouth, and creates goodwill. It also preempts backlash from "I used this for free and now you want money."

### Benefit Tiers

| User Joined Before | Reward | Rationale |
|---------------------|--------|-----------|
| v1.5.0 release | **Lifetime Intelligence** | Earliest adopters, tested the MVP |
| v1.7.0 release | **2 years Intelligence free** | Helped refine core features |
| v2.0.0 release | **1 year Pro free** | Still early, supported growth phase |

### Implementation

```swift
struct FoundersProgram {
    static let v2LaunchDate = Date("2027-XX-XX") // Set at v2.0.0 launch

    enum Benefit {
        case lifetimeIntelligence   // Before v1.5.0
        case twoYearsIntelligence   // Before v1.7.0
        case oneYearPro             // Before v2.0.0
    }

    static func benefit(for user: User) -> Benefit? {
        guard let firstUseDate = user.createdAt,
              firstUseDate < v2LaunchDate else { return nil }

        if firstUseDate < version1_5_ReleaseDate {
            return .lifetimeIntelligence
        } else if firstUseDate < version1_7_ReleaseDate {
            return .twoYearsIntelligence
        } else {
            return .oneYearPro
        }
    }
}
```

### Founders Badge

Display a visible "Founder" badge in the app for users who qualify. This costs nothing to implement but makes early adopters feel valued and creates a sense of exclusivity. Users who see it will want to have joined earlier - social proof for why others should subscribe now.

---

## Lifetime Deal (Limited, Pre-v2.0.0 Only)

Offer a one-time purchase option exclusively during the pre-launch window. This creates urgency, generates upfront cash to fund development, and converts users who hate subscriptions.

| Tier | One-Time Price (Web) | One-Time Price (StoreKit) | Limit |
|------|---------------------|--------------------------|-------|
| Lifetime Pro | $49.99 | $59.99 | First 500 users |
| Lifetime Intelligence | $89.99 | $99.99 | First 200 users |

**After v2.0.0 launch, lifetime deals are permanently removed.** Scarcity drives conversions.

### Break-Even Analysis

| Tier | Lifetime Web Price | Dev Keeps | Equivalent to (web monthly) |
|------|-------------------|-----------|----------------------------|
| Pro | $49.99 | ~$48.50 | 13.6 months of Pro |
| Intelligence | $89.99 | ~$87.30 | 11.7 months of Intelligence |

If the average subscriber stays longer than those durations, the subscription is more profitable. But lifetime deals serve a different purpose: upfront cash, word-of-mouth, and converting subscription-averse users who would otherwise stay on free.

---

## Revenue Projections

### Assumptions

- 5% free-to-paid conversion rate (industry average for utility apps)
- 70% choose Pro, 30% choose Intelligence (among paying users)
- 80% of paying users subscribe via web (lower price incentivizes it)
- 60% choose annual billing (better deal incentivizes it)

### Blended Average Revenue Per Paying User

```
Web monthly Pro:          $3.57/mo  (after Stripe fees)
Web annual Pro:           $2.40/mo  (after Stripe fees, amortized)
Web monthly Intelligence: $7.46/mo  (after Stripe fees)
Web annual Intelligence:  $4.83/mo  (after Stripe fees, amortized)
StoreKit monthly Pro:     $4.24/mo  (after Apple 15%)
StoreKit annual Pro:      $2.83/mo  (after Apple 15%, amortized)
StoreKit monthly Intel:   $8.49/mo  (after Apple 15%)
StoreKit annual Intel:    $5.67/mo  (after Apple 15%, amortized)

Weighted average (all channels, all billing cycles): ~$3.80/mo per paying user
```

### Revenue by User Scale

| Total Users | Paying (5%) | Monthly Revenue | Annual Revenue |
|-------------|-------------|-----------------|----------------|
| 1,000 | 50 | $190 | $2,280 |
| 5,000 | 250 | $950 | $11,400 |
| 10,000 | 500 | $1,900 | $22,800 |
| 25,000 | 1,250 | $4,750 | $57,000 |
| 50,000 | 2,500 | $9,500 | $114,000 |
| 100,000 | 5,000 | $19,000 | $228,000 |

### Operating Costs at Scale

| Item | Cost | Notes |
|------|------|-------|
| Apple Developer Program | $99/yr | Required |
| Domain | ~$12/yr | For website and email |
| Firebase | $0 | Free tier covers well beyond 100K users for auth + functions |
| CloudKit | $0 | Apple covers up to generous limits |
| AI processing | $0 | All on-device |
| Stripe | Included above | Deducted from revenue projections |
| **Total fixed costs** | **~$111/yr** | Regardless of user count |

**Profit margin at 10K users: ~99.5%** ($22,800 revenue - $111 costs = $22,689 profit)

---

## Implementation Roadmap

### Phase 1: Pre-Monetization Setup (Before v2.0.0)

```
Priority: Get infrastructure ready while features are still free

1. Apple Small Business Program enrollment
2. Stripe account setup and configuration
3. Web checkout page (single landing page with Stripe Checkout)
4. Firebase Cloud Functions for:
   ├── Stripe webhook handler
   ├── StoreKit Server Notification V2 handler
   └── Subscription status API
5. Firestore schema for subscription records:
   ├── userId
   ├── tier (free | pro | intelligence)
   ├── channel (web | storekit)
   ├── billingCycle (monthly | annual | lifetime)
   ├── expiresAt
   ├── foundersStatus (nullable)
   └── createdAt
6. EntitlementManager in app (reads from Firestore)
7. Feature gate wrappers around Pro/Intelligence features
```

### Phase 2: StoreKit 2 Integration

```swift
// Product identifiers
enum FinovaProduct: String, CaseIterable {
    // Pro
    case proMonthly     = "com.arthurrios.finova.pro.monthly"
    case proAnnual      = "com.arthurrios.finova.pro.annual"
    case proLifetime    = "com.arthurrios.finova.pro.lifetime"

    // Intelligence
    case intelMonthly   = "com.arthurrios.finova.intel.monthly"
    case intelAnnual    = "com.arthurrios.finova.intel.annual"
    case intelLifetime  = "com.arthurrios.finova.intel.lifetime"
}

// Entitlement checking
enum AppTier: Int, Comparable {
    case free = 0
    case pro = 1
    case intelligence = 2

    static func < (lhs: AppTier, rhs: AppTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

protocol EntitlementProviding {
    var currentTier: AppTier { get }
    func hasAccess(to feature: ProFeature) -> Bool
}

enum ProFeature {
    // Pro features
    case budgetAllocation
    case cloudSync
    case familySharing
    case unlimitedCreditCards
    case unlimitedBudgets
    case advancedReports
    case dataExport
    case prioritySupport

    // Intelligence features
    case aiStatementParsing
    case autoCategorizarion
    case spendingPredictions
    case anomalyDetection
    case notificationIntelligence
    case savingsRecommendations
    case smartInsights

    var requiredTier: AppTier {
        switch self {
        case .budgetAllocation, .cloudSync, .familySharing,
             .unlimitedCreditCards, .unlimitedBudgets,
             .advancedReports, .dataExport, .prioritySupport:
            return .pro
        case .aiStatementParsing, .autoCategorizarion,
             .spendingPredictions, .anomalyDetection,
             .notificationIntelligence, .savingsRecommendations,
             .smartInsights:
            return .intelligence
        }
    }
}
```

### Phase 3: Feature Gate Pattern

```swift
// Usage in ViewModels / ViewControllers
class SomeViewModel {
    private let entitlementManager: EntitlementProviding

    func onStatementImportTapped() {
        guard entitlementManager.hasAccess(to: .aiStatementParsing) else {
            delegate?.showUpgradePrompt(for: .intelligence, feature: .aiStatementParsing)
            return
        }
        // Proceed with statement parsing
    }

    func onSyncToggled() {
        guard entitlementManager.hasAccess(to: .cloudSync) else {
            delegate?.showUpgradePrompt(for: .pro, feature: .cloudSync)
            return
        }
        // Proceed with sync
    }
}
```

### Phase 4: Web Checkout Page

A single responsive page hosted on your domain (e.g., finova.app/subscribe):

```
Page structure:
├── Header: Finova logo + "Choose your plan"
├── Tier cards: Pro and Intelligence side by side
│   ├── Feature list
│   ├── Monthly / Annual toggle
│   └── "Subscribe" button → Stripe Checkout
├── FAQ section
│   ├── "Can I cancel anytime?"
│   ├── "Why is the web price different?"
│   └── "How do I access Pro features after subscribing?"
└── Footer: Privacy policy, terms of service

Tech: Static HTML + Stripe Checkout (hosted by Stripe)
No backend needed for the page itself - Stripe handles the payment UI.
```

---

## Conversion Strategy

### Free-to-Paid Triggers

The app should surface upgrade prompts at moments when the user feels the limitation, not at random times.

| Trigger | Shown When | Target Tier |
|---------|-----------|-------------|
| Category limit | User tries to create 9th category | Pro |
| History limit | User scrolls past 3 months | Pro |
| Sync prompt | User opens app on second device | Pro |
| Share prompt | User taps "Share budget" | Pro |
| Credit card limit | User tries to add 2nd card | Pro |
| Statement import | User taps "Import statement" | Intelligence |
| Smart categorization | User manually categorizes for 10th time | Intelligence |
| Spending insight | User views reports → "Want predictions?" | Intelligence |

### Upgrade Prompt Design

Never block core functionality. Prompts should be:
- **Contextual**: Appear at the moment of need
- **Dismissable**: "Maybe later" always available
- **Value-first**: Show what they gain, not what they lack
- **Non-repetitive**: Once dismissed, don't show the same prompt for 7 days

---

## Pricing Iteration Plan

Launch prices are not permanent. Plan to iterate based on data:

| Metric | Action |
|--------|--------|
| Conversion > 8% | Consider raising prices (high willingness to pay) |
| Conversion < 3% | Consider lowering prices or improving free tier |
| Intelligence/Pro ratio > 50% | Intelligence pricing may be too low |
| Intelligence/Pro ratio < 15% | Intelligence pricing may be too high or features need improvement |
| Annual/Monthly ratio < 40% | Annual discount may not be compelling enough |
| Churn > 8%/month | Investigate feature satisfaction, consider adding retention features |

---

## Risk Analysis

| Risk | Impact | Mitigation |
|------|--------|------------|
| Apple rejects external payment links | High | StoreKit remains a fully functional backup channel; stay compliant with latest guidelines |
| Users resist paying after free period | Medium | Generous free tier keeps core users; founders program rewards early adopters |
| Web payment friction (leaving app) | Medium | Streamline checkout flow; Stripe Checkout is one-click for returning users |
| Competitor undercuts on price | Low | Privacy-first on-device AI is a moat; can't easily be copied |
| Low conversion rate | Medium | A/B test pricing, upgrade prompts, and tier bundling |
| Stripe availability in target markets | Low | PIX integration for Brazil; Stripe supports 40+ countries |

---

## Key Dates and Milestones

```
2026 Q2-Q3 (v1.6.0):
├── Enroll in Apple Small Business Program
├── Set up Stripe account
├── Build web checkout page (placeholder, not yet active)
└── Implement EntitlementManager and Firestore schema

2026 Q3 (v1.7.0):
├── Feature gates active but all features unlocked (still free)
├── Founders tracking begins (record user firstUseDate)
└── Lifetime deal pre-orders open (optional)

2026 Q4 / 2027 Q1 (v2.0.0):
├── Activate paywalls
├── StoreKit 2 products live on App Store
├── Web checkout page live
├── Founders Program benefits applied automatically
├── Lifetime deals available (limited quantity)
├── Marketing campaign launch
└── Monitor conversion metrics weekly
```

---

## Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Payment channels | Web-first + StoreKit fallback | 97% vs 85% margin |
| Number of tiers | 3 (Free, Pro, Intelligence) | Clear value ladder |
| Pro anchor feature | Budget allocation + sync/sharing | Solves daily pain |
| Intelligence anchor feature | AI statement parsing | Saves hours per month |
| Pricing model | Subscription + limited lifetime | Recurring revenue + upfront cash |
| AI infrastructure | 100% on-device native iOS | $0 operational cost at any scale |
| Founders reward | Tiered by adoption date | Loyalty + prevents backlash |

The combination of web-first payments, zero AI infrastructure costs, and a three-tier model creates a business where **nearly every dollar of revenue is profit**. At 10,000 users with 5% conversion, that's ~$22K/year with ~$111 in costs.
