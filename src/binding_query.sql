attach database 'binding_query.db' as 'BQD';

.timer off
.header on
.mode csv
.bail on

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

-- ================================================================
.print ============================================================
.print
.print ====== Executing src/binding_query_common_logic.sql
.print
.print ============================================================

.read src/binding_query_common_logic.sql

-- ==============
--
-- The main query
--
.print ====== Query into BQD.RESULT table
.timer on
drop table if exists BQD.RESULT;
create table BQD.RESULT(
  NAME_A text,
  UNI_A text,
  EXTERN_A text,
  NAME_B text,
  UNI_B text,
  EXTERN_B text,
  MODE,
  IS_DIRECTIONAL,
  SCORE int
);


insert into BQD.RESULT
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




-- ================================================================
.print ============================================================
.print
.print ====== 2nd ROUND: Executing src/binding_query_common_logic.sql
.print
.print ============================================================

-- ================================================================
.print ============================================================
.print
.print Query into BQD.RESULT table (associations of 1st neighbours)
.print
.print ============================================================

-- ================================
.print ====== UNIPROT2STRING backup
-- drop table if exists BQD.UNIPROT_BAK; <--- TODO: caller script should protect this part
create table BQD.UNIPROT_BAK as
select
  UNIPROT_ID, STRING_EXTERNAL_ID
from UNIPROT2STRING;

-- =============================================================
.print ====== creation of UNIPROT2STRING based on its backup and
.print ====== BQD.RESULT table
drop table UNIPROT2STRING;

-- load the input of next "round"
create table UNIPROT2STRING as
-- insert into UNIPROT2STRING
  select
    distinct
    R.UNI_A as UNIPROT_ID, 
    R.EXTERN_A as STRING_EXTERNAL_ID
  from BQD.RESULT R
    left outer join BQD.UNIPROT_BAK U
      on R.EXTERN_A = U.STRING_EXTERNAL_ID
        -- this external id is not listed in UNIPROT_BAK
        and R.EXTERN_A is NULL

  union

  select
    distinct
    R.UNI_B as UNIPROT_ID, 
    R.EXTERN_B as STRING_EXTERNAL_ID
  from BQD.RESULT R
    left outer join BQD.UNIPROT_BAK U
      on R.EXTERN_B = U.STRING_EXTERNAL_ID
        -- this external id is not listed in UNIPROT_BAK
        and R.EXTERN_B is NULL
;

-- ==============
--
-- The main query
--
.print ====== 2nd ROUND: Query into BQD.RESULT table
.read src/binding_query_common_logic.sql
.timer on

drop table if exists BQD.RESULT;
create table BQD.RESULT(
  NAME_A text,
  UNI_A text,
  EXTERN_A text,
  NAME_B text,
  UNI_B text,
  EXTERN_B text,
  MODE,
  IS_DIRECTIONAL,
  SCORE int
);


insert into BQD.RESULT
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

select count(*) as RESULT_COUNT from BQD.RESULT;
select count(*) as INPUT_COUNT from UNIPROT2STRING;

.print >>>>> NEW_RESULT
drop table if exists BQD.NEW_RESULT;
create table BQD.NEW_RESULT as
  select distinct R.*
  from BQD.RESULT R
    inner join UNIPROT2STRING U on R.UNI_A = U.UNIPROT_ID
    inner join UNIPROT2STRING U2 on R.UNI_B = U2.UNIPROT_ID
;

.print >>>>> NEW_RESULT_COUNT
select count(*) as NEW_RESULT_COUNT from NEW_RESULT;

