--
-- network_assiociations.sql
--

-------------------------------------------------------------
--
-- auxiliary part: helper views
--
-------------------------------------------------------------


--
-- UNI_MAPPING view:
--
-- maps UniProt Ids to STRING Ids
--
create temporary view UNI_MAPPING as
  select
    us.uniprot_id,
    ip.protein_external_id,
    ip.protein_id,
    ip.preferred_name
  from items_proteins ip
  inner join uniprot2string us
    on ip.protein_external_id = us.string_external_id
;
--
-- UNI_LOOSE view:
--
-- UNI_MAPPING "mutation" for outer joins
-- (LOOSEly coupled items)
--
create temporary view UNI_LOOSE as
  select
    ip.uniprot_kb_id as uniprot_id,
    ip.protein_external_id,
    ip.protein_id,
    ip.preferred_name
  from items_proteins ip
;

--
-- ACT_400 view:
--
-- network actions with 400+ score
--
create temporary view ACT_400 as
  select
    IP.PROTEIN_EXTERNAL_ID as EXT_A,
    IP2.PROTEIN_EXTERNAL_ID as EXT_B,
    NA.*
  from NETWORK_ACTIONS NA
  inner join ITEMS_PROTEINS IP
    on IP.PROTEIN_ID = NA.ITEM_ID_A
  inner join ITEMS_PROTEINS IP2
    on IP2.PROTEIN_ID = NA.ITEM_ID_B
  where SCORE > 400
    and (MODE = 'binding' or MODE = 'inhibition')
;


--
-- NEG_BINDINGS view:
--
-- collect 'binding' associations which also have 'inhibition'
--
create temporary view NEG_BINDINGS as
  select
    NA.ext_a, NA.ext_b,
    NA.item_id_a, NA.item_id_b,
    NA.a_is_acting,
    '-1' as mode
  from ACT_400 NA
  where NA.mode = 'binding'

  INTERSECT

  select
    NA.ext_a, NA.ext_b,
    NA.item_id_a, NA.item_id_b,
    NA.a_is_acting,
    '-1' as mode
  from ACT_400 NA
  where NA.mode = 'inhibition'
;


--
-- POS_BINDINGS view:
--
-- collect 'binding' associations with no 'inhibition'
--
create temporary view POS_BINDINGS as
  select
    NA.ext_a, NA.ext_b,
    NA.item_id_a, NA.item_id_b,
    NA.a_is_acting,
    '+1' as mode
  from ACT_400 NA
  where NA.mode = 'binding'

  except

  select
    NA.ext_a, NA.ext_b,
    NA.item_id_a, NA.item_id_b,
    NA.a_is_acting,
    '+1' as mode
  from ACT_400 NA
  where NA.mode = 'inhibition'
;


--
-- negative: binding + inhibition
create temporary view NEG_UNION as

  -- IF A-side is fixed
  select distinct
    U.uniprot_id as UNIPROT_ID_A,
    U.preferred_name as PREFERRED_NAME_A,
    U2.uniprot_id as UNIPROT_ID_B,
    U2.preferred_name as PREFERRED_NAME_B,
    N.*
  from NEG_BINDINGS N
  inner join UNI_MAPPING U on N.item_id_a = U.protein_id
  left outer join UNI_LOOSE U2 on N.item_id_b = U2.protein_id

  UNION

  -- IF B-side is fixed
  select distinct
    U.uniprot_id as UNIPROT_ID_A,
    U.preferred_name as PREFERRED_NAME_A,
    U2.uniprot_id as UNIPROT_ID_B,
    U2.preferred_name as PREFERRED_NAME_B,
    N.*
  from NEG_BINDINGS N
  inner join UNI_MAPPING U2 on N.item_id_b = U2.protein_id
  left outer join UNI_LOOSE U on N.item_id_a = U.protein_id
;


--
-- positive: binding with no inhibition
create temporary view POS_UNION as
  -- IF A-side is fixed
  select distinct
    U.uniprot_id as UNIPROT_ID_A,
    U.preferred_name as PREFERRED_NAME_A,
    U2.uniprot_id as UNIPROT_ID_B,
    U2.preferred_name as PREFERRED_NAME_B,
    P.*
  from POS_BINDINGS P
  inner join UNI_MAPPING U on P.item_id_a = U.protein_id
  left outer join UNI_LOOSE U2 on P.item_id_b = U2.protein_id

  UNION

  -- IF B-side is fixed
  select distinct
    U.uniprot_id as UNIPROT_ID_A,
    U.preferred_name as PREFERRED_NAME_A,
    U2.uniprot_id as UNIPROT_ID_B,
    U2.preferred_name as PREFERRED_NAME_B,
    P.*
  from POS_BINDINGS P
  inner join UNI_MAPPING U2 on P.item_id_b = U2.protein_id
  left outer join UNI_LOOSE U on P.item_id_a = U.protein_id
;


-------------------------------------------------------------
--
-- query part
--
-------------------------------------------------------------

select
  UNIPROT_ID_A,
  PREFERRED_NAME_A,
  UNIPROT_ID_B,
  PREFERRED_NAME_B,
  EXT_A,
  EXT_B,
  ITEM_ID_A,
  ITEM_ID_B,
  MODE,
  case A_IS_ACTING
    when 't' then 'A -> B'
    when 'f' then 'A <- B'
    else 'NA'
  end as DIRECTION
from (
  select * from NEG_UNION
  union
  select * from POS_UNION
)
;
