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
-- TODO : remove the limitation
--  limit 10000
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
    '-1' as mode
  from ACT_400 NA
    inner join ACT_400 NA2
      on NA.item_id_a = NA2.item_id_a
        and NA.item_id_b = NA2.item_id_b
  where NA.mode = 'binding'
    and NA2.mode = 'inhibition'
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
    '+1' as mode
  from ACT_400 NA
  where NA.mode = 'binding'

  except

  select
    NA.ext_a, NA.ext_b,
    NA.item_id_a, NA.item_id_b,
    '+1' as mode
  from ACT_400 NA
  where NA.mode = 'inhibition'
;


--
-- negative: binding + inhibition
create temporary view NEG_UNION as
  select distinct
    U.uniprot_id,
    U.preferred_name,
    U2.uniprot_id,
    U2.preferred_name,
    N.*
  from NEG_BINDINGS N
  left outer join UNI_MAPPING U on N.item_id_a = U.protein_id
  left outer join UNI_MAPPING U2 on N.item_id_b = U2.protein_id
;


--
-- positive: binding with no inhibition
create temporary view POS_UNION as
  select distinct
    U.uniprot_id,
    U.preferred_name,
    U2.uniprot_id,
    U2.preferred_name,
    P.*
  from POS_BINDINGS P
  left outer join UNI_MAPPING U on P.item_id_a = U.protein_id
  left outer join UNI_MAPPING U2 on P.item_id_b = U2.protein_id
;


-------------------------------------------------------------
--
-- query part
--
-------------------------------------------------------------

select * from NEG_UNION
union
select * from POS_UNION
;
