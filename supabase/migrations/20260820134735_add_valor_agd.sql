alter table public."AGENDAMENTO"
  add column "VALOR_AGD" numeric(10,2);

comment on column public."AGENDAMENTO"."VALOR_AGD" is
  'Valor da consulta informado ao marcar "Enviar para Pagamento" (status Realizada). Usado pelo financeiro como valor do serviço, no lugar do VALOR_1CONS fixo do profissional.';
