
.timer off
.header on
.mode csv

drop view if exists FILTER;
create temp view FILTER as
  select *
  from NETWORK_ACTIONS
  where
    SCORE > 400
    and (MODE = 'binding' or MODE = 'inhibition')
;


drop view if exists NETWORK_ACTIONS_DIRECTIONAL;
create temp view NETWORK_ACTIONS_DIRECTIONAL as
    select
      ITEM_ID_A A,
      ITEM_ID_B B,
      MODE
    from FILTER
    where
      IS_DIRECTIONAL = 't'
      and A_IS_ACTING = 't'
 
    UNION

    -- FLIP
    select
      ITEM_ID_B as A,
      ITEM_ID_A as B,
      MODE
    from FILTER
    where
      IS_DIRECTIONAL = 't'
      and A_IS_ACTING = 'f'
;


--
-- NETWORK_ACTIONS_NON_DIRECTIONAL view
--
drop view if exists NETWORK_ACTIONS_NON_DIRECTIONAL;
create temp view NETWORK_ACTIONS_NON_DIRECTIONAL as
  select
    ITEM_ID_A A,
    ITEM_ID_B B,
    MODE
  from FILTER
  where IS_DIRECTIONAL = 'f'
    and A_IS_ACTING = 'f'
;

drop view if exists NETWORK_ACTIONS_UNION;
create temp view NETWORK_ACTIONS_UNION as 
  select * from NETWORK_ACTIONS_DIRECTIONAL
  union
  select * from NETWORK_ACTIONS_NON_DIRECTIONAL
;


drop view if exists LAYER1;
create temp view LAYER1 as
select *
from
  NETWORK_ACTIONS_UNION U
;


drop view if exists LAYER2;
create temp view LAYER2 as
select
  I.PREFERRED_NAME NAME_A,
  I.UNIPROT_KB_ID UNI_A,
  I.PROTEIN_EXTERNAL_ID EXTERN_A,
  I2.PREFERRED_NAME NAME_B,
  I2.UNIPROT_KB_ID UNI_B,
  I2.PROTEIN_EXTERNAL_ID EXTERN_B,
  L.*
from
  LAYER1 L
    inner join ITEMS_PROTEINS I
      on L.A = I.PROTEIN_ID
    inner join ITEMS_PROTEINS I2
      on L.B = I2.PROTEIN_ID
;

drop view if exists LAYER3;
create temp view LAYER3 as
select L.*
  from LAYER2 L
  inner join UNIPROT2STRING US on
    L.EXTERN_A = US.STRING_EXTERNAL_ID
UNION --------
select L.*
  from LAYER2 L
  inner join UNIPROT2STRING US on
    L.EXTERN_B = US.STRING_EXTERNAL_ID
;

--
-- POS_BINDINGS view:
--
-- collect 'binding' associations with no 'inhibition'
--
drop view if exists POS_BINDINGS;
create temporary view POS_BINDINGS as
  select
    NAME_A, UNI_A, EXTERN_A,
    NAME_B, UNI_B, EXTERN_B,
    A, B,
    '+1' as MODE
  from LAYER3
  where MODE = 'binding'

  except

  select
    NAME_A, UNI_A, EXTERN_A,
    NAME_B, UNI_B, EXTERN_B,
    A, B,
    '+1' as MODE
  from LAYER3
  where MODE = 'inhibition'
;

--
-- NEG_BINDINGS view:
--
-- collect 'binding' associations which also have 'inhibition'
--
drop view if exists NEG_BINDINGS;
create temporary view NEG_BINDINGS as
  select
    NAME_A, UNI_A, EXTERN_A,
    NAME_B, UNI_B, EXTERN_B,
    A, B,
    '-1' as MODE
  from LAYER3
  where MODE = 'binding'

  INTERSECT

  select
    NAME_A, UNI_A, EXTERN_A,
    NAME_B, UNI_B, EXTERN_B,
    A, B,
    '-1' as MODE
  from LAYER3
  where MODE = 'inhibition'
;


--
-- Union of NEG_BINDINGS and POS_BINDINGS
--
drop view if exists NP_UNION;
create temporary view NP_UNION as
  select A,B from NEG_BINDINGS
  union
  select A,B from POS_BINDINGS
;

--
-- Intersection of NEG_BINDINGS and POS_BINDINGS only A,B cols
--
drop view if exists NP_INTERSECT;
create temporary view NP_INTERSECT as
  select A,B from NEG_BINDINGS
  intersect
  select A,B from POS_BINDINGS
;
