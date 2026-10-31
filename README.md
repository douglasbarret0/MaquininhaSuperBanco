# Maquininha do Super Banco Imobiliário

Substitui a maquininha de cartão do jogo. Cada jogador abre o site no próprio celular, entra com o código da partida e vê os saldos atualizando ao vivo.

- `index.html` — o app inteiro (sem build).
- `supabase.sql` — tabelas, regras de acesso e funções. Rode uma vez no SQL Editor do Supabase.

Os saldos ficam no Supabase. As alterações só passam pelas funções `sbi_op`, `sbi_undo` e `sbi_create_room`, que conferem saldo e sala.
