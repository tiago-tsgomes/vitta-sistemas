-- ============================================================
-- SEED: 12 pacientes para cada profissional da empresa
--       Usuario Autonomo (24 pacientes no total)
-- Execute em:
--   https://app.supabase.com/project/ccdeuabmjwgntwssjfgo/sql
-- ============================================================

DO $$
DECLARE
  v_emp_id   uuid;
  v_profs    uuid[];
  v_prof_id  uuid;
  v_pac_id   uuid;
  i          integer;
  idx_c      integer;

  -- Nomes masculinos
  primeiros_m text[] := ARRAY[
    'Ricardo Andrade','Fábio Mendes','Adriano Sousa','Maurício Lima','Sérgio Pinto',
    'Leandro Gomes','Cláudio Neto','Marcelo Dias','Renato Costa','Júlio Rocha',
    'Otávio Melo','Caio Freitas'
  ];

  -- Nomes femininos
  primeiros_f text[] := ARRAY[
    'Débora Lins','Natália Campos','Viviane Ramos','Eliana Barros','Denise Cunha',
    'Sueli Ferraz','Adriana Luz','Fernanda Vilas','Roberta Duarte','Ingrid Moura',
    'Cristiane Ávila','Jéssica Prado'
  ];

  -- Sobrenomes
  sobrenomes text[] := ARRAY[
    'Silva','Santos','Oliveira','Souza','Pereira','Costa','Ferreira','Alves',
    'Rodrigues','Nascimento','Lima','Araújo','Carvalho','Gomes','Martins',
    'Ribeiro','Almeida','Rocha','Nunes','Pinto'
  ];

  -- Ruas
  ruas text[] := ARRAY[
    'Rua das Acácias','Av. Independência','Rua Tiradentes','Rua Marechal Deodoro','Av. Duque de Caxias',
    'Rua Voluntários da Pátria','Rua Conselheiro Saraiva','Av. Beira Mar','Rua das Palmeiras','Rua João Pessoa',
    'Rua Cel. Paiva','Rua Major Facundo','Av. Visconde do Rio Branco','Rua Padre Mororó','Av. Filomeno Gomes'
  ];

  -- Bairros
  bairros text[] := ARRAY[
    'Aldeota','Meireles','Varjota','Fátima','Benfica',
    'Messejana','Papicu','Cocó','Dionísio Torres','Montese',
    'Parquelândia','Parangaba','Bom Jardim','Antônio Bezerra','Maraponga'
  ];

  -- Cidades e estados (índice sincronizado)
  cidades text[] := ARRAY[
    'Fortaleza','Fortaleza','Caucaia','Maracanaú','Juazeiro do Norte',
    'Sobral','Crato','Iguatu','Quixadá','Russas',
    'Fortaleza','Fortaleza','Caucaia','Fortaleza','Fortaleza'
  ];
  ufs text[] := ARRAY[
    'CE','CE','CE','CE','CE',
    'CE','CE','CE','CE','CE',
    'CE','CE','CE','CE','CE'
  ];

  v_nome   text;
  v_sexo   text;
  v_dtnasc date;
  v_cpf    text;
  v_tel    text;
  v_email  text;
  v_rua    text;
  v_nro    text;
  v_bairro text;
  v_cidade text;
  v_uf     text;
  v_cep    text;
  -- seed começa em 1000 para não colidir com o script da Vida Saúde (que vai de 1 a 60)
  v_seed   integer := 1000;

BEGIN
  -- --------------------------------------------------------
  -- 1. Localizar a empresa pelo nome
  -- --------------------------------------------------------
  SELECT "ID_EMP" INTO v_emp_id
  FROM public."EMPRESA"
  WHERE "NOME_EMP" ILIKE '%Autonomo%'
     OR "NOME_EMP" ILIKE '%Autônomo%'
  LIMIT 1;

  IF v_emp_id IS NULL THEN
    RAISE EXCEPTION 'Empresa "Usuario Autonomo" não encontrada. Verifique o nome na tabela EMPRESA.';
  END IF;

  RAISE NOTICE 'Empresa encontrada: %', v_emp_id;

  -- --------------------------------------------------------
  -- 2. Coletar os IDs dos profissionais da empresa
  -- --------------------------------------------------------
  SELECT ARRAY_AGG("ID_PROF" ORDER BY "NOME_PROF")
  INTO v_profs
  FROM public."PROFISSIONAL"
  WHERE "ID_EMP" = v_emp_id;

  IF v_profs IS NULL OR array_length(v_profs, 1) = 0 THEN
    RAISE EXCEPTION 'Nenhum profissional encontrado para a empresa %', v_emp_id;
  END IF;

  RAISE NOTICE '% profissional(is) encontrado(s).', array_length(v_profs, 1);

  -- --------------------------------------------------------
  -- 3. Para cada profissional, inserir 12 pacientes
  -- --------------------------------------------------------
  FOREACH v_prof_id IN ARRAY v_profs LOOP
    RAISE NOTICE 'Inserindo pacientes para o profissional: %', v_prof_id;

    FOR i IN 1..12 LOOP
      v_seed := v_seed + 1;

      -- Sexo e nome aleatório
      IF (v_seed % 2 = 0) THEN
        v_sexo := 'Masculino';
        v_nome := primeiros_m[1 + ((v_seed - 1001) % 12)]
               || ' ' || sobrenomes[1 + floor(random() * 20)::int];
      ELSE
        v_sexo := 'Feminino';
        v_nome := primeiros_f[1 + ((v_seed - 1001) % 12)]
               || ' ' || sobrenomes[1 + floor(random() * 20)::int];
      END IF;

      -- Data de nascimento: entre 18 e 75 anos
      v_dtnasc := CURRENT_DATE
                  - (floor(random() * (75 - 18) + 18) * 365
                     + floor(random() * 365))::int;

      -- CPF fictício com seed para unicidade (não é CPF válido)
      v_cpf := lpad((v_seed * 137 % 999)::text, 3, '0') || '.'
             || lpad((v_seed * 251 % 999)::text, 3, '0') || '.'
             || lpad((v_seed * 373 % 999)::text, 3, '0') || '-'
             || lpad((v_seed * 61  % 99)::text,  2, '0');

      -- Telefone celular (DDD 85 — Fortaleza/CE)
      v_tel := '(85) 9'
             || lpad((1000 + (v_seed * 97  % 8999))::text, 4, '0') || '-'
             || lpad((1000 + (v_seed * 113 % 8999))::text, 4, '0');

      -- E-mail (sem acentos via translate)
      v_email := lower(
                   translate(
                     split_part(v_nome, ' ', 1),
                     'ÁÀÃÂÄáàãâäÉÈÊËéèêëÍÌÎÏíìîïÓÒÕÔÖóòõôöÚÙÛÜúùûüÇç',
                     'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc'
                   )
                 ) || v_seed::text || '@email.com';

      -- Endereço
      idx_c    := 1 + floor(random() * 15)::int;
      v_rua    := ruas[1 + floor(random() * 15)::int];
      v_nro    := (floor(random() * 1998)::int + 1)::text;
      v_bairro := bairros[1 + floor(random() * 15)::int];
      v_cidade := cidades[idx_c];
      v_uf     := ufs[idx_c];
      v_cep    := lpad((60000 + (v_seed * 59 % 5999))::text, 5, '0')
               || '-' || lpad((v_seed * 43 % 999)::text, 3, '0');

      -- Inserir paciente
      INSERT INTO public."PACIENTE" (
        "ID_PAC",
        "NOME_PAC",
        "CPF_PAC",
        "DTNASC_PAC",
        "SEXO_PAC",
        "TEL_PAC",
        "EMAIL_PAC",
        "EMP_PAC",
        "ATIVO_PAC",
        "DTCRI_PAC",
        "CEP_PAC",
        "RUA_PAC",
        "NRO_PAC",
        "BAIRRO_PAC",
        "CIDADE_PAC",
        "UF_PAC",
        "MENOS_PAC"
      ) VALUES (
        gen_random_uuid(),
        v_nome,
        v_cpf,
        v_dtnasc,
        v_sexo,
        v_tel,
        v_email,
        v_emp_id,
        true,
        now() - (floor(random() * 365) || ' days')::interval,
        v_cep,
        v_rua,
        v_nro,
        v_bairro,
        v_cidade,
        v_uf,
        false
      )
      RETURNING "ID_PAC" INTO v_pac_id;

      -- Vincular paciente ao profissional
      INSERT INTO public."PACIENTE_PROFISSIONAL" ("PAC_ID", "PROF_ID")
      VALUES (v_pac_id, v_prof_id);

    END LOOP; -- i in 1..12
  END LOOP; -- profissional

  RAISE NOTICE '✓ % pacientes inseridos com sucesso!', (v_seed - 1000);
END $$;
