--
-- expression_query.sql
--

.header on

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
  from expr_uniprot2string us
  inner join items_proteins ip
    on ip.protein_external_id = us.string_external_id
;

create temporary view UNI_LOOSE as
  select
    ip.uniprot_kb_id as uniprot_id,
    ip.protein_external_id,
    ip.protein_id,
    ip.preferred_name
  from items_proteins ip
;


--
-- ACT_EXPR view:
--
-- expression query of network actions
--
create temporary view ACT_EXPR as
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
    and MODE = 'expression'
;


-------------------------------------------------------------
--
-- query part
--
-------------------------------------------------------------


-- direction A => B
select
  U.UNIPROT_ID UNI_A,
  U.PREFERRED_NAME PREFERRED_NAME_A,
  U2.UNIPROT_ID UNI_B,
  U2.PREFERRED_NAME PREFERRED_NAME_B,
  AE.*
from ACT_EXPR AE
inner join UNI_MAPPING U2
  on AE.EXT_B = U2.PROTEIN_EXTERNAL_ID
left outer join UNI_LOOSE U
  on AE.EXT_A = U.PROTEIN_EXTERNAL_ID
where
    IS_DIRECTIONAL = 't'
    and A_IS_ACTING = 't'

UNION

-- direction B => A
select
  U.UNIPROT_ID UNI_A,
  U.PREFERRED_NAME PREFERRED_NAME_A,
  U2.UNIPROT_ID UNI_B,
  U2.PREFERRED_NAME PREFERRED_NAME_B,
  AE.*
from ACT_EXPR AE
inner join UNI_MAPPING U
  on AE.EXT_A = U.PROTEIN_EXTERNAL_ID
left outer join UNI_LOOSE U2
  on AE.EXT_B = U2.PROTEIN_EXTERNAL_ID
where
    IS_DIRECTIONAL = 't'
    and A_IS_ACTING = 'f'
;
