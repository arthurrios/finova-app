# Finova — apresentação por capítulos (PT-BR)

`finova-apresentacao-ptbr.pdf` — 28 páginas, quadradas (576×576 pt).
`01.png` … `28.png` — as mesmas páginas em 1200×1200.

Feita para due diligence do Grupo Primo. Três regras valem em todo o deck:

1. **O que está na loja é a 1.5.1**, com SQLite local. Nuvem, grupos e importação de
   extrato existem só como código na 1.6.0 e aparecem no capítulo "A construir" — nunca
   como recurso atual.
2. **Nenhuma tração é vendida.** O app já tem usuários todo mês, mas poucos — porque nunca
   houve divulgação. O que falta é marketing, não canal. O argumento é produto pronto mais
   quem construiu.
3. **Todo número do capítulo 6 foi medido no repositório**, não estimado.
4. **O capítulo 7 trata o futuro como duas fundações**, não como lista de recursos:
   um banco de dados na nuvem (que destrava conta compartilhada, grupos e multi-aparelho)
   e Open Finance — que é condição para competir (os concorrentes já nascem nele), traz o
   extrato, torna a importação de arquivo desnecessária, e abre o caminho para
   investimentos.

## Capítulos

| Páginas | Capítulo |
|---|---|
| 01 | Capa |
| 02–04 | 1 · Entrar e abrir o mês |
| 05–08 | 2 · Lançar do jeito real |
| 09–13 | 3 · Cartões e faturas |
| 14–16 | 4 · Parcelas sob controle |
| 17–21 | 5 · Orçamento por categoria |
| 22–24 | 6 · Volume do projeto |
| 25–27 | 7 · O que vem depois |
| 28 | Fecho |

## Volume do projeto — como foi medido

Tudo em `release/v1.5.1`, a mesma versão publicada na App Store:

| Número | O que é | Como medir de novo |
|---|---|---|
| 57.772 | linhas de Swift em `Finova/Sources` | `git ls-tree -r --name-only release/v1.5.1 \| grep '^Finova/Sources/.*\.swift$'` e somar as linhas |
| 232 | arquivos Swift do app | mesma listagem, `wc -l` |
| 21 | telas | pastas distintas em `Finova/Sources/Scenes` |
| 33 | arquivos de teste | arquivos `.swift` em `FinovaTests` |
| 428 | commits | `git rev-list --count release/v1.5.1` |
| 15 | meses | primeiro commit 07/05/2025, último da 1.5.1 em 10/08/2026 |
| 658 | textos localizados | chaves em `Localizable.xcstrings` (en + pt-BR) |

Para comparação, a 1.6.0 (não publicada) tem 307 arquivos, 30 telas e 502 commits.

## Telas

17 capturas, todas de uma sessão só: `release/v1.5.1` + demo seed, aparelho em pt-BR,
moeda R$. Os nomes do seed foram traduzidos para o guia (Supermercado, Cartão Azul,
Essenciais) e ficam só na cópia de teste, não no repositório.

## Destaques

Nada é desenhado por cima da captura. Duas peças fazem o trabalho: um brilho magenta em
volta do cartão pai (onde) e um cartão com o detalhe ampliado (o quê). Todas as caixas são
medidas por `detect.py` e conferidas por `verify_boxes.py` antes de desenhar.
