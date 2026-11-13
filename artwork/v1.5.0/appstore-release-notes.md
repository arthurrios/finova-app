# App Store Connect — What's New in This Version (1.5.0)

Covers `release/v1.4.0` → `release/v1.5.0` (c8cc837, build 7) — 60 commits.

Each claim was checked against both branches so nothing listed here already shipped in
1.4.0. Scenes absent from 1.4.0 and present in 1.5.0: CreditCards, AddCreditCard,
StatementDetails, EarlyPayment, AllocationTags, Profile. `BusinessDayRule` is also new
(0 → 13 references).

**Deliberately left out:**

- *Adjust Balance* — the scene already exists in 1.4.0, so that commit was a rework, not a
  new feature.
- *Hide values (eye toggle)* — the 1.5.0 range only contains a `fix(hide values)` commit,
  which implies the feature predates 1.4.0. Not claimed as new; worth confirming if you
  want it mentioned.

Both locales are ~2,100 characters, inside the 4,000 limit.

---

## English

```
Credit cards are here.

CREDIT CARDS & STATEMENTS
• Add your cards with their own closing day, due day and limit
• Choose cash or card when you enter an expense. Cash affects your balance right
  away; a card charge goes to the statement instead
• Purchases are placed on the billing cycle that actually contains them, so
  anything bought after the closing date lands on next month's statement
• Open a statement to see its period, closing and due dates, total, status and
  every charge on it
• Mark a statement as paid once you settle it
• Get a reminder as a statement's due date approaches

INSTALLMENTS
• Split a purchase and the installments are spread across statements, billed on
  each due date
• Pay future installments early in one step, and see which open statement they
  will be added to before you confirm
• An installment you pay early stops counting toward the month it would have
  been billed
• Cancel a purchase together with its remaining installments

BUDGET TAGS
• Group categories into your own tags, like Essentials, Lifestyle or Wellbeing
• See what a whole set of categories costs, not just one line
• Filter your dashboard by tag, and reorder tags to change how the budget ring
  is drawn
• Tag names appear in your device's language

A CLEARER MONTH
• The budget card now projects where your month is heading, and what would be
  left if every allocation were fully used
• Saved and overspent sit side by side, and a closed month leads with its outcome
• Unallocated spending is tracked instead of quietly disappearing

ALSO NEW
• A dedicated Profile area for your account and your cards
• Transactions can shift off weekends and holidays automatically
• On iPad, the add button now sits in the bottom trailing corner

FIXES
• Recurring transactions are more reliable: no duplicates, no lost edits, and
  deleting one removes the whole series as expected
• Notification scheduling and monthly reminders repaired
• A refund on a card now reduces the statement instead of increasing it
• Editing a card's dates no longer rewrites statements that already closed
• More Portuguese (Brazil) translations
```

---

## Português (Brasil)

```
Os cartões de crédito chegaram.

CARTÕES E FATURAS
• Cadastre seus cartões com dia de fechamento, vencimento e limite próprios
• Escolha débito ou crédito ao lançar uma despesa. No débito, o saldo muda na
  hora; no crédito, a compra vai para a fatura
• Cada compra entra no ciclo que realmente a contém, então o que você compra
  depois do fechamento cai na fatura do mês seguinte
• Abra uma fatura para ver o período, fechamento, vencimento, total, status e
  todos os lançamentos
• Marque a fatura como paga quando quitar
• Receba um aviso quando o vencimento estiver perto

PARCELAS
• Parcele uma compra e as parcelas se distribuem entre as faturas, cobradas em
  cada vencimento
• Antecipe parcelas futuras de uma vez e veja em qual fatura aberta elas vão
  entrar antes de confirmar
• A parcela antecipada deixa de contar no mês em que seria cobrada
• Cancele uma compra junto com as parcelas restantes

ETIQUETAS DE ORÇAMENTO
• Agrupe categorias em etiquetas suas, como Essenciais, Estilo de vida ou
  Bem-estar
• Veja quanto custa um conjunto inteiro de categorias, não apenas uma linha
• Filtre o painel por etiqueta e reordene as etiquetas para mudar o desenho do
  anel do orçamento
• Os nomes das etiquetas aparecem no idioma do seu aparelho

O MÊS MAIS CLARO
• O cartão de orçamento agora projeta como o mês deve terminar e o que sobraria
  se todo o valor planejado fosse gasto
• Economizado e excedido aparecem lado a lado, e um mês fechado começa pelo
  resultado
• O gasto não alocado é acompanhado, em vez de simplesmente desaparecer

TAMBÉM NOVO
• Uma área de Perfil dedicada para sua conta e seus cartões
• Lançamentos podem ser deslocados automaticamente de fins de semana e feriados
• No iPad, o botão de adicionar agora fica no canto inferior direito

CORREÇÕES
• Transações recorrentes mais confiáveis: sem duplicatas, sem perder edições, e
  excluir uma remove a série inteira como esperado
• Agendamento de notificações e lembretes mensais corrigidos
• Um estorno no cartão agora reduz a fatura, em vez de aumentá-la
• Editar as datas de um cartão não reescreve mais faturas já fechadas
• Mais traduções em português (Brasil)
```
