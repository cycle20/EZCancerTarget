--
-- network_assiociations.sql
--

--
-- Complex query assembled by WITH-statement and sub-querys.
--

WITH
--
-- direction_to sub-query
--

--
-- semantics of query (in pseudo code)
-- -----------------------------------
--
-- IF mode = binding
-- THEN
--   get each connection
--   IF list of "action" contains "inhibition"
--   THEN
--     RETURN +1
--   ELSE
--     RETURN -1
--   ENDIF
-- ENDIF
-- ELSE
--   RETURN -1
-- ENDIF
--

--
-- sub-tasks:
-- - get internal STRING ids of external ids
-- - get bindig connections
-- - get inibition connections
-- - get binding + inhibition combinations
--   -- get all connections for them
--   -- mark them by +1
-- - get connections with -1 to mark non-binding connections
--

INTERNAL_STRING_IDS(uniprot_id, protein_external_id, protein_id) AS (
  select
    us.uniprot_id,
    ip.protein_external_id,
    ip.protein_id
  from items_proteins ip
  inner join uniprot2string us
    on ip.protein_external_id = us.string_external_id

),

HAS_BINDING(protein_a, protein_b) AS (
  select distinct item_id_a as protein_a, item_id_b as protein_b
  from NETWORK_ACTIONS where mode = "binding"
),

HAS_NO_BINDING(protein_a, protein_b) AS (
  select distinct item_id_a as protein_a, item_id_b as protein_b
  from NETWORK_ACTIONS NA

  EXCEPT

  select protein_a, protein_b from HAS_BINDING
),

IS_INHIBITION(protein_a, protein_b) AS (
  select item_id_a as protein_a, item_id_b as protein_b
  from NETWORK_ACTIONS where action = "inhibition"
)

--
-- main query
--
select *, "+1" as INHIBITION
from (
  select
    I.UNIPROT_ID as UNIPROT_A, I2.UNIPROT_ID as UNIPROT_B, NA.MODE,
    I.PROTEIN_EXTERNAL_ID as STRING_A, I2.PROTEIN_EXTERNAL_ID as STRING_B,
    NA.ITEM_ID_A, NA.ITEM_ID_B
  from INTERNAL_STRING_IDS I
  -- TODO only HB.PROTEIN_A and PROTEIN_B differ
  inner join HAS_BINDING HB on I.PROTEIN_ID = HB.PROTEIN_A          -- < IMPORTANT: can be refactored later
  inner join INTERNAL_STRING_IDS I2 on I2.PROTEIN_ID = HB.PROTEIN_B -- < IMPORTANT
  inner join NETWORK_ACTIONS NA
    on NA.ITEM_ID_A = HB.PROTEIN_A and NA.ITEM_ID_B = HB.PROTEIN_B

  UNION

  -- With this SELECT the UNION results almost half as much rows:
  -- (It means there are many bi-directional "binding" entries)
  -- select NA.ITEM_ID_B as ITEM_ID_A, NA.ITEM_ID_A as ITEM_ID_B, NA.MODE

  select
    I.UNIPROT_ID as UNIPROT_A, I2.UNIPROT_ID as UNIPROT_B, NA.MODE,
    I.PROTEIN_EXTERNAL_ID as STRING_A, I2.PROTEIN_EXTERNAL_ID as STRING_B,
    NA.ITEM_ID_A, NA.ITEM_ID_B
  from INTERNAL_STRING_IDS I
  -- TODO only HB.PROTEIN_A and PROTEIN_B differ
  inner join HAS_BINDING HB on I.PROTEIN_ID = HB.PROTEIN_B          -- < IMPORTANT: reverse direction
  inner join INTERNAL_STRING_IDS I2 on I2.PROTEIN_ID = HB.PROTEIN_A -- < IMPORTANT
  inner join NETWORK_ACTIONS NA
    on NA.ITEM_ID_A = HB.PROTEIN_A and NA.ITEM_ID_B = HB.PROTEIN_B
)

UNION

-- IF it is not BINDING, BUT it is INHIBITION ==> -1
select *, "-1" as INHIBITION
from (
  select
    I.UNIPROT_ID as UNIPROT_A, I2.UNIPROT_ID as UNIPROT_B, "inhibition" as MODE,
    I.PROTEIN_EXTERNAL_ID as STRING_A, I2.PROTEIN_EXTERNAL_ID as STRING_B,
    NA.ITEM_ID_A, NA.ITEM_ID_B
  from INTERNAL_STRING_IDS I
  inner join HAS_NO_BINDING HNB on I.PROTEIN_ID = HNB.PROTEIN_A      -- < IMPORTANT differences
  inner join INTERNAL_STRING_IDS I2 on I2.PROTEIN_ID = HNB.PROTEIN_B -- < IMPORTANT
  inner join NETWORK_ACTIONS NA
    on NA.ITEM_ID_A = HNB.PROTEIN_A and NA.ITEM_ID_B = HNB.PROTEIN_B
)

; -- end of WITH statement
