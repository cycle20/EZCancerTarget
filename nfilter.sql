
.header on
--.timer on
.mode table
.mode csv

drop view if exists FILTER;

create temp view FILTER as
  select *
  from NETWORK_ACTIONS
  where
    SCORE > 400
    and (MODE = 'binding' or MODE = 'inhibition')
--    and ((item_id_a = 4432849 and item_id_b = 4447277)
--    or (item_id_a = 4432849 and item_id_b = 4447277))
;


drop view if exists NETWORK_ACTIONS_DIRECTIONAL;
create temp view NETWORK_ACTIONS_DIRECTIONAL as
    select
      ITEM_ID_A A,
      ITEM_ID_B B,
      MODE,
      1 as IS_DIRECTIONAL,
      1 as A_IS_ACTING,
      SCORE
    from FILTER
    where
      IS_DIRECTIONAL = 't'
      and A_IS_ACTING = 't'
 
    UNION

    -- FLIP
    select
      ITEM_ID_B as A,
      ITEM_ID_A as B,
      MODE,
      1 as IS_DIRECTIONAL,
      1 as A_IS_ACTING,
      SCORE
    from FILTER
    where
      IS_DIRECTIONAL = 't'
      and A_IS_ACTING = 'f'
--order by IS_DIRECTIONAL
;

drop view if exists NETWORK_ACTIONS_NON_DIRECTIONAL;

--
-- NETWORK_ACTIONS_NON_DIRECTIONAL view
-- TODO: do we need a flip here?
--
create temp view NETWORK_ACTIONS_NON_DIRECTIONAL as
  select
    ITEM_ID_A A,
    ITEM_ID_B B,
    MODE,
    0 as IS_DIRECTIONAL,
    0 as A_IS_ACTING,
    SCORE
  from FILTER
  where IS_DIRECTIONAL = 'f'
    and A_IS_ACTING = 'f'
;

-- .print
-- .print
-- select * from NETWORK_ACTIONS_DIRECTIONAL;
-- .print
-- .print
-- select * from NETWORK_ACTIONS_NON_DIRECTIONAL;


create temp view NETWORK_ACTIONS_UNION as 
  select * from NETWORK_ACTIONS_DIRECTIONAL
  union
  select * from NETWORK_ACTIONS_NON_DIRECTIONAL;


-- select count(*)
-- from
--   NETWORK_ACTIONS_UNION
-- ;


create temp view LAYER1 as
select *
from
  NETWORK_ACTIONS_UNION U
;


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

select * from LAYER3;

