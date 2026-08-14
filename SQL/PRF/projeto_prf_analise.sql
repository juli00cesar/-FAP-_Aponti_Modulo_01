-- 1. Confere a versão do SQLite que tá rodando no navegador
SELECT sqlite_version() AS versao_sqlite;

-- 2. Olha o nome e o tipo de cada coluna pra ver se importou tudo certo
PRAGMA table_info(acidentes_prf_2025);

-- 3. Conta quantas linhas o arquivo tem no total pra confirmar a importação
SELECT COUNT(*) AS total_ocorrencias 
FROM acidentes_prf_2025;

-- 4. Apaga a view antiga se ela já existir, pra não dar erro de duplicidade ao rodar de novo
DROP VIEW IF EXISTS vw_acidentes_base;

-- 5. Cria a view base já com a regra de letalidade: teve 1+ morto vira 1 (fatal), senão vira 0
CREATE VIEW vw_acidentes_base AS
SELECT
    *,
    CASE
        WHEN CAST(mortos AS INTEGER) >= 1 THEN 1
        ELSE 0
    END AS acidente_fatal
FROM acidentes_prf_2025;

-- 6. Puxa o total de acidentes, quantos foram fatais e calcula a % de letalidade geral
-- (Multiplico por 100.0 com ponto decimal pro banco não arredondar a conta pra inteiro)
SELECT
    COUNT(*) AS total_acidentes,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base;

-- 7. Compara o volume e a letalidade por Estado (UF)
-- O filtro HAVING >= 100 tira os estados com poucas ocorrências pra não distorcer a taxa
SELECT
    uf,
    COUNT(*) AS total_acidentes,
    SUM(CAST(mortos AS INTEGER)) AS total_mortos,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY uf
HAVING COUNT(*) >= 100
ORDER BY perc_fatais DESC;

-- 8. Lista as 30 rodovias (BRs) que tiveram o maior número absoluto de mortos
SELECT
    br,
    COUNT(*) AS total_acidentes,
    SUM(CAST(mortos AS INTEGER)) AS total_mortos,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
WHERE br IS NOT NULL
GROUP BY br
HAVING COUNT(*) >= 100
ORDER BY total_mortos DESC
LIMIT 30;

-- 9. Quebra a evolução dos acidentes por Ano e Mês pra ver se tem algum período pior
SELECT
    CAST(strftime('%Y', data_inversa) AS INTEGER) AS ano,
    CAST(strftime('%m', data_inversa) AS INTEGER) AS mes,
    COUNT(*) AS total_acidentes,
    SUM(CAST(mortos AS INTEGER)) AS total_mortos,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY ano, mes
ORDER BY ano, mes;

-- 10. Vê qual tipo de acidente (colisão frontal, capotamento, etc.) tem a maior % de mortes
SELECT
    tipo_acidente,
    COUNT(*) AS total_acidentes,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY tipo_acidente
HAVING COUNT(*) >= 100
ORDER BY perc_fatais DESC;

-- 11. Mostra as 30 principais causas de acidente ordenadas pelas que mais matam proporcionalmente
SELECT
    causa_acidente,
    COUNT(*) AS total_acidentes,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY causa_acidente
HAVING COUNT(*) >= 100
ORDER BY perc_fatais DESC
LIMIT 30;

-- 12. Compara a gravidade dos acidentes dependendo da claridade (dia, noite, madrugada)
SELECT
    fase_dia,
    COUNT(*) AS total_acidentes,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY fase_dia
HAVING COUNT(*) >= 100
ORDER BY perc_fatais DESC;

-- 13. Avalia se chuva, neblina ou tempo ruim aumentam a proporção de acidentes fatais
SELECT
    condicao_meteorologica,
    COUNT(*) AS total_acidentes,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY condicao_meteorologica
HAVING COUNT(*) >= 100
ORDER BY perc_fatais DESC;

-- 14. Confere se pista simples é muito mais letal do que pista dupla ou múltipla
SELECT
    tipo_pista,
    COUNT(*) AS total_acidentes,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY tipo_pista
HAVING COUNT(*) >= 100
ORDER BY perc_fatais DESC;
-- 15. Junta pista e fase do dia pra achar os piores cenários
-- A coluna cobertura_perc mostra qual % do total de acidentes cai nessa combinação
SELECT
    tipo_pista,
    fase_dia,
    COUNT(*) AS total_acidentes,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS cobertura_perc,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY tipo_pista, fase_dia
HAVING COUNT(*) >= 100
ORDER BY perc_fatais DESC;

-- 16. Calcula o Lift: divide a letalidade do grupo pela letalidade média do Brasil
-- Lift maior que 1 = mais perigoso que a média; menor que 1 = menos perigoso
WITH taxa_global AS (
    SELECT 1.0 * SUM(acidente_fatal) / COUNT(*) AS taxa
    FROM vw_acidentes_base
)
SELECT
    b.tipo_acidente,
    COUNT(*) AS total_acidentes,
    SUM(b.acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS cobertura_perc,
    ROUND(1.0 * SUM(b.acidente_fatal) / COUNT(*), 4) AS confianca,
    ROUND((1.0 * SUM(b.acidente_fatal) / COUNT(*)) / g.taxa, 2) AS lift
FROM vw_acidentes_base b
CROSS JOIN taxa_global g
GROUP BY b.tipo_acidente, g.taxa
HAVING COUNT(*) >= 100
ORDER BY lift DESC;

-- 17. Criar View para relatórios mensais (Corrigido com substr pro formato BR)
DROP VIEW IF EXISTS vw_indicadores_mensais;
CREATE VIEW vw_indicadores_mensais AS
SELECT
    CAST(substr(data_inversa, 7, 4) AS INTEGER) AS ano,
    CAST(substr(data_inversa, 4, 2) AS INTEGER) AS mes,
    COUNT(*) AS total_acidentes,
    SUM(CAST(mortos AS INTEGER)) AS total_mortos,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
GROUP BY ano, mes;
SELECT * FROM vw_indicadores_mensais ORDER BY ano, mes;

-- 18. Cria a view consolidada por Estado e Rodovia
DROP VIEW IF EXISTS vw_indicadores_uf_br;

CREATE VIEW vw_indicadores_uf_br AS
SELECT
    uf,
    br,
    COUNT(*) AS total_acidentes,
    SUM(CAST(mortos AS INTEGER)) AS total_mortos,
    SUM(acidente_fatal) AS acidentes_fatais,
    ROUND(100.0 * SUM(acidente_fatal) / COUNT(*), 2) AS perc_fatais
FROM vw_acidentes_base
WHERE br IS NOT NULL
GROUP BY uf, br;

-- Comando para fazer a tabela aparecer na tela:
SELECT * FROM vw_indicadores_uf_br ORDER BY total_mortos DESC;