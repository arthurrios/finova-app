//
//  DemoSeedDatasets.swift
//  Finova
//
//  The content `DemoSeedGenerator` writes: a Brazilian ledger (Portuguese, reais — the default) and
//  an American one (English, dollars), each written for its own country — local merchants, prices
//  and habits — rather than one ledger with the numbers converted.
//

#if DEBUG || DEMO
import Foundation

struct DemoDataset {

    // MARK: - Shape

    struct Card {
        enum Role {
            /// Closes about a week from today: its current statement is open.
            case open
            /// Closed a few days ago and falls due in a few days: its current statement is closed.
            case closed
        }
        let name: String
        let lastFour: String
        let brand: CardBrand
        let color: CardColor
        let limit: Double
        let role: Role
    }

    /// When an item happens. Month offsets are relative to the current month (0), history runs
    /// from -11, and anything at or after today only appears where the schedule is meant to be planned.
    enum Schedule {
        /// A monthly series starting at the first history month, generated through the app's horizon.
        case recurring(day: Int, card: Int?)
        /// A one-off on each of `days`, in every history month (or only `months`). Amounts vary.
        case monthly(days: [Int], months: Set<Int>?, card: Int?)
        /// An installment purchase made in month `monthOffset`.
        case installments(count: Int, monthOffset: Int, day: Int, card: Int?)
        /// A one-off in whichever seeded month (history or the next five) is this calendar month.
        case yearly(month: Int, day: Int, card: Int?)
        /// A one-off dated today, never on a card: a card's budget month can be the next one. Fills the
        /// open month on any date, so budget history's "so far" figures have something to show.
        case today
    }

    struct Item {
        let title: String
        let category: TransactionCategory
        let type: TransactionType
        /// Major units (reais, dollars, yen). For installments, the purchase total.
        let amount: Double
        let schedule: Schedule
    }

    let currency: String
    let cards: [Card]
    let items: [Item]
    /// An installment purchase whose last two installments get paid ahead of time.
    let earlyPaidTitle: String?
    /// An installment purchase that gets cancelled (estorno) after the first installments.
    let cancelledTitle: String?

    // MARK: - Lookup

    /// BRL gets the Brazilian ledger; every other currency gets the American one. Its amounts are
    /// always stored as dollars-and-cents, so in a zero-decimal currency (yen) they read about a
    /// hundred times larger — roughly the right magnitude, and far better than seven-yen coffees.
    static func forCurrency(_ code: String) -> DemoDataset {
        code == "BRL" ? brazil : unitedStates
    }

    // MARK: - Builders

    private static func rec(_ title: String, _ category: TransactionCategory, _ amount: Double,
                            day: Int, card: Int? = nil, income: Bool = false) -> Item {
        Item(title: title, category: category, type: income ? .income : .expense, amount: amount,
             schedule: .recurring(day: day, card: card))
    }

    private static func monthly(_ title: String, _ category: TransactionCategory, _ amount: Double,
                                days: [Int], months: Set<Int>? = nil, card: Int? = nil,
                                income: Bool = false) -> Item {
        Item(title: title, category: category, type: income ? .income : .expense, amount: amount,
             schedule: .monthly(days: days, months: months, card: card))
    }

    private static func inst(_ title: String, _ category: TransactionCategory, total: Double,
                             _ count: Int, month: Int, day: Int, card: Int? = nil) -> Item {
        Item(title: title, category: category, type: .expense, amount: total,
             schedule: .installments(count: count, monthOffset: month, day: day, card: card))
    }

    private static func yearly(_ title: String, _ category: TransactionCategory, _ amount: Double,
                               month: Int, day: Int, card: Int? = nil, income: Bool = false) -> Item {
        Item(title: title, category: category, type: income ? .income : .expense, amount: amount,
             schedule: .yearly(month: month, day: day, card: card))
    }

    private static func today(_ title: String, _ category: TransactionCategory, _ amount: Double) -> Item {
        Item(title: title, category: category, type: .expense, amount: amount, schedule: .today)
    }

    // MARK: - Brazil (BRL, default)

    static let brazil = DemoDataset(
        currency: "BRL",
        cards: [
            Card(name: "Nubank Ultravioleta", lastFour: "4321", brand: .mastercard, color: .purple,
                 limit: 12_000, role: .open),
            Card(name: "Itaú Personnalité Black", lastFour: "8765", brand: .visa, color: .black,
                 limit: 25_000, role: .closed),
        ],
        items: [
            // Fixed monthly
            rec("Salário – Acme Tecnologia", .salary, 14_500, day: 5, income: true),
            rec("Aluguel", .homeMaintenance, 2_800, day: 10),
            rec("Condomínio Ed. Jardins", .bankSlip, 780, day: 10),
            rec("Vivo Fibra + Controle", .communication, 189.90, day: 15),
            rec("Netflix", .subscriptions, 44.90, day: 12, card: 0),
            rec("Spotify Família", .subscriptions, 34.90, day: 18, card: 0),
            rec("Smart Fit", .fitness, 129.90, day: 3, card: 1),
            rec("Porto Seguro Auto", .insurance, 212.40, day: 20),
            rec("Unimed – Plano de saúde", .healthcare, 689, day: 8),
            rec("Wizard – Curso de inglês", .education, 390, day: 7),
            rec("Tesouro Selic", .investments, 1_000, day: 6),
            rec("Reserva de emergência", .savings, 500, day: 6),
            rec("Médicos Sem Fronteiras", .donations, 50, day: 25, card: 1),

            // Installments
            inst("Financiamento Honda Civic", .loans, total: 55_200, 48, month: -20, day: 15),
            inst("IPTU", .taxes, total: 1_840, 10, month: -7, day: 12),
            inst("iPhone 17 Pro – Apple", .miscellaneous, total: 9_599, 12, month: -4, day: 18, card: 1),
            inst("Geladeira Brastemp – Magalu", .homeMaintenance, total: 4_299, 10, month: -2, day: 9, card: 0),
            inst("Passagens LATAM – Florianópolis", .travel, total: 1_380, 6, month: -3, day: 14, card: 1),
            inst("Tênis Nike – Centauro", .clothing, total: 699.90, 3, month: -1, day: 20, card: 0),
            inst("Alura – Plano anual", .education, total: 1_188, 12, month: -5, day: 2, card: 0),
            inst("Fone JBL Tune – Americanas", .entertainment, total: 449.90, 5, month: -2, day: 22, card: 1),

            // Day to day
            monthly("Pão de Açúcar", .market, 620, days: [7]),
            monthly("Assaí Atacadista", .groceries, 480, days: [21]),
            monthly("Hortifruti", .groceries, 95, days: [14, 28]),
            monthly("iFood", .meals, 68, days: [9, 24], card: 0),
            monthly("Coco Bambu", .meals, 210, days: [16], months: [-5, -3, -1, 0], card: 1),
            monthly("Uber", .transportation, 32, days: [4, 13, 27], card: 0),
            monthly("Posto Shell", .transportation, 260, days: [11], card: 1),
            monthly("Enel – Conta de luz", .utilities, 245, days: [17]),
            monthly("Sabesp – Água", .utilities, 98, days: [19]),
            monthly("Drogasil", .healthcare, 86, days: [13], months: [-5, -3, -2, 0]),
            monthly("Renner", .clothing, 289, days: [12], months: [-4, -1], card: 0),
            monthly("Cinemark", .entertainment, 92, days: [22], months: [-5, -3, -1, 0], card: 0),
            monthly("Barbearia Corleone", .personalCare, 70, days: [20]),
            monthly("Lavanderia OMO", .miscellaneous, 45, days: [26]),
            monthly("Pix recebido – Mariana", .transfer, 150, days: [25], months: [-4, -2, 0], income: true),
            monthly("Pix enviado – Racha do churrasco", .transfer, 85, days: [8], months: [-3]),
            monthly("Freela UX – Studio Norte", .salary, 1_800, days: [18], months: [-4, -1], income: true),
            monthly("Presente – Aniversário da mãe", .gifts, 180, days: [2], months: [-2]),
            monthly("Booking.com – Pousada em Floripa", .travel, 1_140, days: [24], months: [-3]),

            // This month so far: two categories past their plan, two with room left
            today("Jantar de aniversário – Coco Bambu", .meals, 420),
            today("Ingressos – Allianz Parque", .entertainment, 380),
            today("Assaí Atacadista – Compra do mês", .groceries, 310),
            today("Posto Shell – Tanque cheio", .transportation, 180),

            // Once a year
            yearly("13º salário – 1ª parcela", .salary, 7_250, month: 11, day: 28, income: true),
            yearly("13º salário – 2ª parcela", .salary, 6_100, month: 12, day: 18, income: true),
            yearly("Presentes de Natal", .gifts, 1_200, month: 12, day: 20, card: 0),
            yearly("Black Friday – Amazon", .miscellaneous, 850, month: 11, day: 27, card: 0),
            yearly("IPVA", .taxes, 2_480, month: 1, day: 15),
            yearly("Restituição do IR", .taxes, 1_380, month: 6, day: 30, income: true),
        ],
        earlyPaidTitle: "Geladeira Brastemp – Magalu",
        cancelledTitle: "Fone JBL Tune – Americanas"
    )

    // MARK: - United States (USD)

    static let unitedStates = DemoDataset(
        currency: "USD",
        cards: [
            Card(name: "Chase Sapphire Preferred", lastFour: "4417", brand: .visa, color: .blue,
                 limit: 15_000, role: .open),
            Card(name: "Amex Gold", lastFour: "1009", brand: .amex, color: .gold,
                 limit: 20_000, role: .closed),
        ],
        items: [
            rec("Paycheck – Acme Corp", .salary, 3_400, day: 1, income: true),
            rec("Paycheck – Acme Corp (mid-month)", .salary, 3_400, day: 15, income: true),
            rec("Rent – Maple Court Apts", .homeMaintenance, 2_450, day: 1),
            rec("Verizon Wireless", .communication, 85, day: 15),
            rec("Netflix", .subscriptions, 15.49, day: 12, card: 0),
            rec("Spotify Premium", .subscriptions, 11.99, day: 18, card: 0),
            rec("Planet Fitness", .fitness, 24.99, day: 3, card: 1),
            rec("GEICO Auto", .insurance, 146.20, day: 20),
            rec("Coursera Plus", .education, 59, day: 7, card: 0),
            rec("Vanguard Roth IRA", .investments, 500, day: 3),
            rec("Ally Savings transfer", .savings, 400, day: 2),
            rec("American Red Cross", .donations, 25, day: 25, card: 1),

            inst("Auto loan – Toyota Financial", .loans, total: 29_340, 60, month: -20, day: 15),
            inst("iPhone 17 Pro – Apple", .miscellaneous, total: 1_199, 12, month: -4, day: 18, card: 1),
            inst("LG Refrigerator – Best Buy", .homeMaintenance, total: 1_899, 10, month: -2, day: 9, card: 0),
            inst("Delta – NYC ⇄ Miami", .travel, total: 684, 3, month: -3, day: 14, card: 1),
            inst("Nike – Pay in 4", .clothing, total: 240, 4, month: -1, day: 20, card: 0),
            inst("MasterClass – Annual", .education, total: 180, 12, month: -5, day: 2, card: 0),
            inst("Bose QuietComfort – Amazon", .entertainment, total: 349, 5, month: -2, day: 22, card: 1),

            monthly("Whole Foods Market", .groceries, 142, days: [6, 20]),
            monthly("Trader Joe's", .market, 88, days: [13]),
            monthly("Costco", .market, 210, days: [27]),
            monthly("Starbucks", .meals, 6.75, days: [3, 10, 17], card: 0),
            monthly("Chipotle", .meals, 14.50, days: [8, 22], card: 0),
            monthly("DoorDash", .meals, 38, days: [15], card: 1),
            monthly("Uber", .transportation, 24, days: [5, 19], card: 0),
            monthly("Shell", .transportation, 52, days: [9, 23], card: 1),
            monthly("Con Edison", .utilities, 128, days: [17]),
            monthly("CVS Pharmacy", .healthcare, 34, days: [13], months: [-5, -3, -2, 0]),
            monthly("Nordstrom", .clothing, 128, days: [12], months: [-4, -1], card: 0),
            monthly("AMC Theatres", .entertainment, 34, days: [22], months: [-5, -3, -1, 0], card: 0),
            monthly("Great Clips", .personalCare, 26, days: [20]),
            monthly("Target", .miscellaneous, 76, days: [11], card: 1),
            monthly("Amazon", .miscellaneous, 64, days: [4], card: 0),
            monthly("Home Depot", .homeMaintenance, 96, days: [16], months: [-5, -2]),
            monthly("Venmo from Alex", .transfer, 60, days: [25], months: [-4, -2, 0], income: true),
            monthly("Zelle to Sam – BBQ split", .transfer, 45, days: [8], months: [-3]),
            monthly("Freelance – Studio North", .salary, 1_200, days: [18], months: [-4, -1], income: true),
            monthly("Birthday gift – Etsy", .gifts, 58, days: [2], months: [-2]),
            monthly("Airbnb – Miami", .travel, 740, days: [24], months: [-3]),
            monthly("Bill pay – Dr. Patel", .bankSlip, 95, days: [10], months: [-4, -1]),

            today("Birthday dinner – Nobu", .meals, 140),
            today("Concert tickets – Ticketmaster", .entertainment, 120),
            today("Whole Foods Market – Weekly shop", .groceries, 96),
            today("Shell – Full tank", .transportation, 48),

            yearly("IRS estimated tax", .taxes, 1_150, month: 1, day: 15),
            yearly("IRS estimated tax", .taxes, 1_150, month: 4, day: 15),
            yearly("IRS estimated tax", .taxes, 1_150, month: 6, day: 15),
            yearly("IRS estimated tax", .taxes, 1_150, month: 9, day: 15),
            yearly("Tax refund – IRS", .taxes, 1_380, month: 4, day: 20, income: true),
            yearly("Holiday bonus", .salary, 2_500, month: 12, day: 18, income: true),
            yearly("Thanksgiving flights – United", .travel, 520, month: 11, day: 5, card: 1),
            yearly("Black Friday – Best Buy", .miscellaneous, 320, month: 11, day: 27, card: 0),
            yearly("Christmas gifts", .gifts, 600, month: 12, day: 20, card: 0),
        ],
        earlyPaidTitle: "LG Refrigerator – Best Buy",
        cancelledTitle: "Bose QuietComfort – Amazon"
    )
}

// MARK: - Amounts

enum DemoAmounts {
    /// A budget or allocation figure: two significant digits (620, 3,300, 170,000).
    static func round(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        let step = pow(10, floor(log10(value)) - 1)
        return (value / step).rounded() * step
    }

    /// Major units to the minor units the ledger stores, for `currency`'s own decimal places.
    static func minor(_ value: Double, currency: String) -> Int {
        let digits = CurrencyUtils.fractionDigits(for: currency)
        return Int((value * pow(10, Double(digits))).rounded())
    }

    /// A deterministic ±15% wobble so day-to-day spending differs month to month but a reseed of
    /// the same dataset gives the same numbers.
    static func jitter(_ title: String, _ salt: Int) -> Double {
        var h: UInt64 = 1_469_598_103_934_665_603
        for byte in title.utf8 { h = (h ^ UInt64(byte)) &* 1_099_511_628_211 }
        h = (h ^ UInt64(bitPattern: Int64(salt))) &* 1_099_511_628_211
        return 0.85 + Double(h % 3_001) / 10_000
    }
}
#endif
