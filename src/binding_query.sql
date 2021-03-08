attach database 'binding_query.db' as 'BQD';

.timer off
.header on
.mode csv

drop table if exists BQD.FILTER;
create table BQD.FILTER as
  select *
  from NETWORK_ACTIONS
  where
    SCORE > 400
    and (MODE = 'binding' or MODE = 'inhibition')
;


drop table if exists BQD.NETWORK_ACTIONS_DIRECTIONAL;
create table BQD.NETWORK_ACTIONS_DIRECTIONAL as
    select
      ITEM_ID_A A,
      ITEM_ID_B B,
      IS_DIRECTIONAL,
      MODE
    from BQD.FILTER
    where
      IS_DIRECTIONAL = 't'
      and A_IS_ACTING = 't'
 
    UNION

    -- FLIP
    select
      ITEM_ID_B as A,
      ITEM_ID_A as B,
      IS_DIRECTIONAL,
      MODE
    from BQD.FILTER
    where
      IS_DIRECTIONAL = 't'
      and A_IS_ACTING = 'f'
;


--
-- NETWORK_ACTIONS_NON_DIRECTIONAL view
--
drop table if exists BQD.NETWORK_ACTIONS_NON_DIRECTIONAL;
create table BQD.NETWORK_ACTIONS_NON_DIRECTIONAL as
  select
    ITEM_ID_A A,
    ITEM_ID_B B,
    IS_DIRECTIONAL,
    MODE
  from BQD.FILTER
  where IS_DIRECTIONAL = 'f'
    and A_IS_ACTING = 'f'
;

drop table if exists BQD.NETWORK_ACTIONS_UNION;
create table BQD.NETWORK_ACTIONS_UNION as 
  select * from BQD.NETWORK_ACTIONS_DIRECTIONAL
  union
  select * from BQD.NETWORK_ACTIONS_NON_DIRECTIONAL
;


drop table if exists BQD.LAYER1;
create table BQD.LAYER1 as
select *
from
  BQD.NETWORK_ACTIONS_UNION U
;


drop table if exists BQD.LAYER2;
create table BQD.LAYER2 as
select
  I.PREFERRED_NAME NAME_A,
  I.UNIPROT_KB_ID UNI_A,
  I.PROTEIN_EXTERNAL_ID EXTERN_A,
  I2.PREFERRED_NAME NAME_B,
  I2.UNIPROT_KB_ID UNI_B,
  I2.PROTEIN_EXTERNAL_ID EXTERN_B,
  L.*
from
  BQD.LAYER1 L
    inner join ITEMS_PROTEINS I
      on L.A = I.PROTEIN_ID
    inner join ITEMS_PROTEINS I2
      on L.B = I2.PROTEIN_ID
;

drop table if exists BQD.LAYER3;
create table BQD.LAYER3 as
select L.*
  from BQD.LAYER2 L
  inner join UNIPROT2STRING US on
    L.EXTERN_A = US.STRING_EXTERNAL_ID
UNION --------
select L.*
  from BQD.LAYER2 L
  inner join UNIPROT2STRING US on
    L.EXTERN_B = US.STRING_EXTERNAL_ID
;

--
-- POS_BINDINGS view:
--
-- collect 'binding' associations with no 'inhibition'
--
drop table if exists BQD.POS_BINDINGS;
create table BQD.POS_BINDINGS as
  select
    NAME_A, UNI_A, EXTERN_A,
    NAME_B, UNI_B, EXTERN_B,
    A, B,
    '+1' as MODE
  from BQD.LAYER3
  where MODE = 'binding'

  except

  select
    NAME_A, UNI_A, EXTERN_A,
    NAME_B, UNI_B, EXTERN_B,
    A, B,
    '+1' as MODE
  from BQD.LAYER3
  where MODE = 'inhibition'
;

--
-- NEG_BINDINGS view:
--
-- collect 'binding' associations which also have 'inhibition'
--
drop table if exists BQD.NEG_BINDINGS;
create table BQD.NEG_BINDINGS as
  select
    NAME_A, UNI_A, EXTERN_A,
    NAME_B, UNI_B, EXTERN_B,
    A, B,
    '-1' as MODE
  from BQD.LAYER3
  where MODE = 'binding'

  INTERSECT

  select
    NAME_A, UNI_A, EXTERN_A,
    NAME_B, UNI_B, EXTERN_B,
    A, B,
    '-1' as MODE
  from BQD.LAYER3
  where MODE = 'inhibition'
;


--
-- Union of NEG_BINDINGS and POS_BINDINGS
--
drop table if exists BQD.NP_UNION;
create table BQD.NP_UNION as
  select A,B from BQD.NEG_BINDINGS
  union
  select A,B from BQD.POS_BINDINGS
;

--
-- Intersection of NEG_BINDINGS and POS_BINDINGS only A,B cols
--
drop table if exists BQD.NP_INTERSECT;
create table BQD.NP_INTERSECT as
  select A,B from BQD.NEG_BINDINGS
  intersect
  select A,B from BQD.POS_BINDINGS
;

-- ==============================================

--
-- The main query
--
drop table if exists BQD.NP_UNION2;
create table BQD.NP_UNION2 as
  select * from BQD.NEG_BINDINGS
  union
  select * from BQD.POS_BINDINGS
;

.timer on
drop table if exists BQD.RESULT;

.print Query into BQD.RESULT table
create table BQD.RESULT as
select distinct
  I.PREFERRED_NAME NAME_A,
  I.UNIPROT_KB_ID UNI_A,
  I.PROTEIN_EXTERNAL_ID EXTERN_A,
  I2.PREFERRED_NAME NAME_B,
  I2.UNIPROT_KB_ID UNI_B,
  I2.PROTEIN_EXTERNAL_ID EXTERN_B,
  NU.MODE,
  case NWAU.IS_DIRECTIONAL
    when 't' then 1 else 0
  end as IS_DIRECTIONAL,
  F.SCORE
from NP_UNION2 NU
    inner join FILTER F
      on NU.A = F.ITEM_ID_A and NU.B = F.ITEM_ID_B
    inner join ITEMS_PROTEINS I
      on NU.A = I.PROTEIN_ID
    inner join ITEMS_PROTEINS I2
      on NU.B = I2.PROTEIN_ID
    inner join NETWORK_ACTIONS_UNION NWAU
      on NU.A = NWAU.A and NU.B = NWAU.B
;
