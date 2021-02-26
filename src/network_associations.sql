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
-- NEG_BINDINGS view:
--
-- collect 'binding' associations which also have 'inhibition'
--
create temporary view NEG_BINDINGS as
  select NA.item_id_a, NA.item_id_b, '-1' as mode
  from NETWORK_ACTIONS NA
    inner join NETWORK_ACTIONS NA2
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
  select NA.item_id_a, NA.item_id_b, '+1' as mode
  from NETWORK_ACTIONS NA
  where NA.mode = 'binding'
  except
  select NA.item_id_a, NA.item_id_b, '+1' as mode
  from NETWORK_ACTIONS NA
  where NA.mode = 'inhibition'
;

-------------------------------------------------------------
--
-- query part
--
-------------------------------------------------------------


  -- negative: binding + inhibition
  select distinct
    U.uniprot_id,
    U.preferred_name,
    U2.uniprot_id,
    U2.preferred_name,
    N.*
  from UNI_MAPPING U
  inner join NEG_BINDINGS N on N.item_id_a = U.protein_id
  inner join UNI_MAPPING U2 on N.item_id_b = U2.protein_id

union

  -- positive: binding with no inhibition
  select distinct
    U.uniprot_id,
    U.preferred_name,
    U2.uniprot_id,
    U2.preferred_name,
    P.*
  from UNI_MAPPING U
  inner join POS_BINDINGS P on P.item_id_a = U.protein_id
  inner join UNI_MAPPING U2 on P.item_id_b = U2.protein_id
;
