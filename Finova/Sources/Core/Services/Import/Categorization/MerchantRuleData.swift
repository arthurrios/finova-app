//
//  MerchantRuleData.swift
//  Finova
//
//  The shipped merchant rules, as JSON embedded in the binary.
//
//  These began as files under `Finova/Resources/MerchantRules/`, which is the more natural home for
//  data — until it turned out that `.json` under this project's `PBXFileSystemSynchronizedRootGroup`
//  is never added to Copy Bundle Resources. The build succeeded, the app ran, and
//  `Bundle.main.url(forResource:)` simply returned nil, so every merchant fell through to
//  `.miscellaneous` with no error anywhere. A resource that can silently not exist is worse than no
//  resource: the failure is invisible and looks like a bad categorizer.
//
//  Embedded as a string, it cannot go missing, and it is still parsed through the same `MerchantRule`
//  decoder — so `MerchantRuleSet` can overlay a bundled or downloaded file later without changing
//  shape, and the CI test that walks every rule and resolves its `category` still applies.
//
//  Patterns must be written pre-folded: lowercase, no accents. They are matched against
//  `String.normalizedForSearch()`, which folds both, so an accented pattern would never match.
//

import Foundation

enum MerchantRuleData {

    /// Global brands, applicable in any region.
    static let baseJSON = """
    [
      { "id": "netflix", "patterns": ["netflix"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "spotify", "patterns": ["spotify"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "disneyplus", "patterns": ["disney plus", "disneyplus"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "hbomax", "patterns": ["hbo max", "hbomax"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "primevideo", "patterns": ["prime video"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "youtubepremium", "patterns": ["youtube premium"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "applebill", "patterns": ["apple.com/bill", "apple com bill", "itunes"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "googleone", "patterns": ["google one", "google storage"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "icloud", "patterns": ["icloud"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },
      { "id": "openai", "patterns": ["openai", "chatgpt"], "match": "contains", "category": "subscriptions", "typeConstraint": "expense", "priority": 100 },

      { "id": "ubereats", "patterns": ["uber eats", "ubereats"], "match": "contains", "category": "meals", "typeConstraint": "expense", "priority": 96 },
      { "id": "uber", "patterns": ["uber trip", "uber do brasil", "uber"], "match": "contains", "category": "transportation", "typeConstraint": "expense", "priority": 95 },
      { "id": "ninetynine", "patterns": ["99app", "99 tecnologia", "99pop"], "match": "contains", "category": "transportation", "typeConstraint": "expense", "priority": 90 },
      { "id": "cabify", "patterns": ["cabify"], "match": "contains", "category": "transportation", "typeConstraint": "expense", "priority": 90 },

      { "id": "ifood", "patterns": ["ifood"], "match": "contains", "category": "meals", "typeConstraint": "expense", "priority": 95 },
      { "id": "rappi", "patterns": ["rappi"], "match": "contains", "category": "meals", "typeConstraint": "expense", "priority": 90 },
      { "id": "starbucks", "patterns": ["starbucks"], "match": "contains", "category": "meals", "typeConstraint": "expense", "priority": 85 },
      { "id": "mcdonalds", "patterns": ["mcdonald", "mc donalds", "arcos dourados"], "match": "contains", "category": "meals", "typeConstraint": "expense", "priority": 85 },
      { "id": "burgerking", "patterns": ["burger king", "bk brasil"], "match": "contains", "category": "meals", "typeConstraint": "expense", "priority": 85 },
      { "id": "subway", "patterns": ["subway"], "match": "contains", "category": "meals", "typeConstraint": "expense", "priority": 85 },

      { "id": "amazon", "patterns": ["amazon", "amzn"], "match": "contains", "category": "miscellaneous", "typeConstraint": "expense", "priority": 60 },
      { "id": "mercadolivre", "patterns": ["mercado livre", "mercadolivre", "mercadopago"], "match": "contains", "category": "miscellaneous", "typeConstraint": "expense", "priority": 60 },
      { "id": "aliexpress", "patterns": ["aliexpress"], "match": "contains", "category": "miscellaneous", "typeConstraint": "expense", "priority": 60 },
      { "id": "shopee", "patterns": ["shopee"], "match": "contains", "category": "miscellaneous", "typeConstraint": "expense", "priority": 60 },

      { "id": "airbnb", "patterns": ["airbnb"], "match": "contains", "category": "travel", "typeConstraint": "expense", "priority": 90 },
      { "id": "booking", "patterns": ["booking.com", "booking com"], "match": "contains", "category": "travel", "typeConstraint": "expense", "priority": 90 },
      { "id": "latam", "patterns": ["latam airlines", "tam linhas"], "match": "contains", "category": "travel", "typeConstraint": "expense", "priority": 90 },
      { "id": "gol", "patterns": ["gol linhas", "gol transportes"], "match": "contains", "category": "travel", "typeConstraint": "expense", "priority": 90 },
      { "id": "azul", "patterns": ["azul linhas"], "match": "contains", "category": "travel", "typeConstraint": "expense", "priority": 90 },
      { "id": "decolar", "patterns": ["decolar"], "match": "contains", "category": "travel", "typeConstraint": "expense", "priority": 85 },

      { "id": "steam", "patterns": ["steamgames", "steam games", "valve"], "match": "contains", "category": "entertainment", "typeConstraint": "expense", "priority": 85 },
      { "id": "playstation", "patterns": ["playstation", "sony interactive"], "match": "contains", "category": "entertainment", "typeConstraint": "expense", "priority": 85 },
      { "id": "xbox", "patterns": ["xbox"], "match": "contains", "category": "entertainment", "typeConstraint": "expense", "priority": 80 },
      { "id": "cinemas", "patterns": ["cinemark", "cinepolis", "kinoplex"], "match": "contains", "category": "entertainment", "typeConstraint": "expense", "priority": 85 },

      { "id": "smartfit", "patterns": ["smart fit", "smartfit"], "match": "contains", "category": "fitness", "typeConstraint": "expense", "priority": 90 },
      { "id": "bioritmo", "patterns": ["bluefit", "bio ritmo", "bioritmo"], "match": "contains", "category": "fitness", "typeConstraint": "expense", "priority": 90 },
      { "id": "gympass", "patterns": ["gympass", "wellhub"], "match": "contains", "category": "fitness", "typeConstraint": "expense", "priority": 90 },

      { "id": "onlinecourses", "patterns": ["udemy", "coursera", "alura"], "match": "contains", "category": "education", "typeConstraint": "expense", "priority": 85 },
      { "id": "duolingo", "patterns": ["duolingo"], "match": "contains", "category": "education", "typeConstraint": "expense", "priority": 85 }
    ]
    """

    /// Brazilian merchants and the generic Portuguese vocabulary of a bank statement.
    ///
    /// Loaded by REGION, not by UI language — somebody running the app in English while living in
    /// Brazil still has Portuguese descriptions on their statement, and language would get exactly
    /// those users wrong.
    static let ptBRJSON = """
    [
      { "id": "supermercado", "patterns": ["supermercado", "supermerc", "mercado", "sacolao", "hortifruti", "quitanda", "atacadao", "assai", "carrefour", "pao de acucar", "extra hiper", "big bompreco", "sendas", "prezunic", "zona sul", "st marche", "mambo"], "match": "contains", "category": "groceries", "typeConstraint": "expense", "priority": 90 },
      { "id": "padaria", "patterns": ["padaria", "panificadora", "confeitaria", "cafeteria", "lanchonete", "restaurante", "pizzaria", "churrascaria", "hamburgueria", "acai", "sorveteria", "bar e "], "match": "contains", "category": "meals", "typeConstraint": "expense", "priority": 85 },

      { "id": "farmacia", "patterns": ["farmacia", "drogaria", "drogasil", "droga raia", "raia drogasil", "pacheco", "pague menos", "panvel"], "match": "contains", "category": "healthcare", "typeConstraint": "expense", "priority": 90 },
      { "id": "planosaude", "patterns": ["unimed", "amil", "sulamerica saude", "bradesco saude", "hapvida", "notredame", "porto seguro saude"], "match": "contains", "category": "healthcare", "typeConstraint": "expense", "priority": 90 },
      { "id": "laboratorio", "patterns": ["laboratorio", "clinica", "hospital", "odonto", "dentista", "psicolog"], "match": "contains", "category": "healthcare", "typeConstraint": "expense", "priority": 85 },

      { "id": "posto", "patterns": ["posto ", "auto posto", "ipiranga", "shell ", "petrobras", "br distribuidora", "ale combust"], "match": "contains", "category": "transportation", "typeConstraint": "expense", "priority": 88 },
      { "id": "estacionamento", "patterns": ["estacionamento", "estapar", "pedagio", "sem parar", "conectcar", "veloe", "bilhete unico", "metro sp", "ctc metro"], "match": "contains", "category": "transportation", "typeConstraint": "expense", "priority": 85 },

      { "id": "energia", "patterns": ["cemig", "enel", "cpfl", "light servicos", "coelba", "celesc", "copel", "equatorial", "neoenergia", "energia eletrica"], "match": "contains", "category": "utilities", "typeConstraint": "expense", "priority": 92 },
      { "id": "agua", "patterns": ["sabesp", "copasa", "cedae", "sanepar", "caesb", "embasa", "casan"], "match": "contains", "category": "utilities", "typeConstraint": "expense", "priority": 92 },
      { "id": "gas", "patterns": ["comgas", "naturgy", "gas natural", "ultragaz", "liquigas"], "match": "contains", "category": "utilities", "typeConstraint": "expense", "priority": 90 },

      { "id": "telecom", "patterns": ["vivo ", "claro ", "tim ", "oi fibra", "oi movel", "nextel", "algar", "sky brasil", "net servicos"], "match": "contains", "category": "communication", "typeConstraint": "expense", "priority": 88 },
      { "id": "internet", "patterns": ["internet", "banda larga", "provedor"], "match": "contains", "category": "communication", "typeConstraint": "expense", "priority": 80 },

      { "id": "aluguel", "patterns": ["aluguel", "locacao imovel", "imobiliaria"], "match": "contains", "category": "homeMaintenance", "typeConstraint": "expense", "priority": 90 },
      { "id": "condominio", "patterns": ["condominio", "taxa condominial"], "match": "contains", "category": "homeMaintenance", "typeConstraint": "expense", "priority": 92 },
      { "id": "materialconstrucao", "patterns": ["leroy merlin", "telhanorte", "c&c casa", "material de construcao", "ferragem"], "match": "contains", "category": "homeMaintenance", "typeConstraint": "expense", "priority": 85 },

      { "id": "escola", "patterns": ["escola", "colegio", "faculdade", "universidade", "mensalidade escolar", "curso "], "match": "contains", "category": "education", "typeConstraint": "expense", "priority": 85 },
      { "id": "livraria", "patterns": ["livraria", "saraiva", "cultura livr"], "match": "contains", "category": "education", "typeConstraint": "expense", "priority": 80 },

      { "id": "seguro", "patterns": ["seguro", "seguradora", "porto seguro", "sulamerica", "allianz", "tokio marine", "azul seguros"], "match": "contains", "category": "insurance", "typeConstraint": "expense", "priority": 88 },

      { "id": "impostos", "patterns": ["darf", "iptu", "ipva", "das simples", "receita federal", "gps inss", "licenciamento"], "match": "contains", "category": "taxes", "typeConstraint": "expense", "priority": 92 },
      { "id": "tarifabancaria", "patterns": ["tarifa", "iof", "anuidade", "juros", "cesta de servicos", "manutencao de conta"], "match": "contains", "category": "loans", "typeConstraint": "expense", "priority": 85 },
      { "id": "emprestimo", "patterns": ["emprestimo", "financiamento", "consignado", "parcela do financiamento"], "match": "contains", "category": "loans", "typeConstraint": "expense", "priority": 90 },

      { "id": "roupas", "patterns": ["renner", "riachuelo", "c&a ", "zara ", "hering", "marisa ", "centauro", "nike ", "adidas "], "match": "contains", "category": "clothing", "typeConstraint": "expense", "priority": 85 },
      { "id": "beleza", "patterns": ["barbearia", "cabeleireiro", "salao de beleza", "manicure", "estetica", "boticario", "natura ", "sephora"], "match": "contains", "category": "personalCare", "typeConstraint": "expense", "priority": 85 },

      { "id": "petshop", "patterns": ["petshop", "pet shop", "veterinaria", "cobasi", "petz "], "match": "contains", "category": "miscellaneous", "typeConstraint": "expense", "priority": 80 },
      { "id": "doacao", "patterns": ["doacao", "dizimo", "oferta igreja", "unicef", "medicos sem fronteiras"], "match": "contains", "category": "donations", "typeConstraint": "expense", "priority": 88 },

      { "id": "salario", "patterns": ["salario", "pagamento de salario", "folha de pagamento", "pro labore", "remuneracao", "vencimentos"], "match": "contains", "category": "salary", "typeConstraint": "income", "priority": 95 },
      { "id": "rendimento", "patterns": ["rendimento", "juros sobre capital", "dividendos", "resgate cdb", "resgate tesouro", "aplicacao resgatada"], "match": "contains", "category": "investments", "typeConstraint": "income", "priority": 90 },
      { "id": "aplicacao", "patterns": ["aplicacao", "cdb ", "tesouro direto", "lci", "lca", "fundo de investimento"], "match": "contains", "category": "investments", "typeConstraint": "expense", "priority": 88 },
      { "id": "poupanca", "patterns": ["poupanca"], "match": "contains", "category": "savings", "typeConstraint": null, "priority": 88 },

      { "id": "faturacartao", "patterns": ["pagamento de fatura", "fatura cartao", "pagto fatura", "pagamento cartao de credito"], "match": "contains", "category": "creditCard", "typeConstraint": "expense", "priority": 95 },
      { "id": "boleto", "patterns": ["boleto", "titulo de cobranca"], "match": "contains", "category": "bankSlip", "typeConstraint": "expense", "priority": 70 },
      { "id": "presente", "patterns": ["presente", "gift card"], "match": "contains", "category": "gifts", "typeConstraint": "expense", "priority": 80 }
    ]
    """
}
