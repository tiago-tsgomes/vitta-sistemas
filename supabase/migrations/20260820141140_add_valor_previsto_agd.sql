alter table public."AGENDAMENTO"
  add column "VALOR_PREVISTO_AGD" numeric(10,2);

comment on column public."AGENDAMENTO"."VALOR_PREVISTO_AGD" is
  'Valor opcional informado no agendamento (antes da consulta acontecer), usado como estimativa na projeção financeira. Quando a consulta é marcada como Realizada e enviada pra pagamento, o valor definitivo cobrado vai em VALOR_AGD.';
