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

internal_string_ids(protein_id) AS (
  select protein_id
  from ITEMS_PROTEINS
  inner join UNIPROT2STRING
    on protein_external_id = string_external_id
),

has_binding(protein_a, protein_b) AS (
  select distinct item_id_a as protein_a, item_id_b as protein_b
  from NETWORK_ACTIONS where mode = "binding"
),

is_inhibition(protein_a, protein_b) AS (
  select item_id_a as protein_a, item_id_b as protein_b
  from NETWORK_ACTIONS where action = "inhibition"
),

direction_to(
  name1,
  protein_a,
  name2,
  protein_b,
  direction,
  mode,
  action,
  score) AS (

  select
    ip.preferred_name as name1,
    ip.protein_id as protein_a,
    ip2.preferred_name as name2,
    ip2.protein_id as protein_b,
    " -> " as direction,
    mode,
    action,
    score

  from
    network_actions n
    inner join
      items_proteins ip ON item_id_a = ip.protein_id
    inner join
      items_proteins ip2 ON item_id_b = ip2.protein_id

  where
    item_id_b = 4444485
    and a_is_acting  = "t"
),

--
-- direction_from sub-query
--
direction_from(
  name1,
  protein_a,
  name2,
  protein_b,
  direction,
  mode,
  action,
  score) AS (

  select
    ip2.preferred_name as name1,
    ip2.protein_id as protein_b,
    ip.preferred_name as name2,
    ip.protein_id as protein_a,
    " <- " as direction,
    mode,
    action,
    score

  from
    network_actions n
    inner join
      items_proteins ip ON item_id_a = ip.protein_id
    inner join
      items_proteins ip2 ON item_id_b = ip2.protein_id

  where
    item_id_a = 4444485
    and a_is_acting  = "t"
)


--
-- main query
--
select *, "+1" as INHIBITION
from (
  select NA.ITEM_ID_A, NA.ITEM_ID_B, NA.MODE
    from INTERNAL_STRING_IDS I
      inner join HAS_BINDING HB on I.PROTEIN_ID = HB.PROTEIN_A
      inner join NETWORK_ACTIONS NA
        on NA.ITEM_ID_A = HB.PROTEIN_A and NA.ITEM_ID_B = HB.PROTEIN_B

  UNION

  select NA.ITEM_ID_A, NA.ITEM_ID_B, NA.MODE
    from INTERNAL_STRING_IDS I
      inner join HAS_BINDING HB on I.PROTEIN_ID = HB.PROTEIN_B
      inner join NETWORK_ACTIONS NA
        on NA.ITEM_ID_A = HB.PROTEIN_A and NA.ITEM_ID_B = HB.PROTEIN_B
)
-- TODO
-- IF INHIBITION -1
;
