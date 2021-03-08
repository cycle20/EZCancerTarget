--
-- binding_test.sql:
-- -----------------
--
-- unit test of binding_query.sql
--
.read src/binding_query.sql

.timer on
.mode table

--
-- FILTER_TEST
--
select
  case count(*)
    when 426510 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as FILTER_TEST
  , '426510 rows expected' as EXPECTED
  , count(*) as ROWS
from FILTER;

--
-- NETWORK_ACTIONS_DIRECTIONAL
--
select
  case count(*)
    when 23598 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NETWORK_ACTIONS_DIRECTIONAL_TEST
  , '23598 rows expected' as EXPECTED
  , count(*) as ROWS
from NETWORK_ACTIONS_DIRECTIONAL;

--
-- NETWORK_ACTIONS_NON_DIRECTIONAL
--
select
  case count(*)
    when 379312 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NETWORK_ACTIONS_NON_DIRECTIONAL_TEST
  , '379312 rows expected' as EXPECTED
  , count(*) as ROWS
from NETWORK_ACTIONS_NON_DIRECTIONAL;



--
-- NETWORK_ACTIONS_UNION
--
select
  case count(*)
    when 12860 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NETWORK_ACTIONS_UNION
  , '12860 rows expected' as EXPECTED
  , count(*) as ROWS
from NETWORK_ACTIONS_UNION;


--
-- LAYER3_TEST
--
select
  case count(*)
    when 11302 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as LAYER3_TEST
  , '11302 rows expected' as EXPECTED
  , count(*) as ROWS
from LAYER3;

--
-- POS_BINDINDS_TEST
--
select
  case count(*)
    when 8694 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as POS_BINDINDS_TEST
  , '8694 rows expected' as EXPECTED
  , count(*) as ROWS
from POS_BINDINGS;

--
-- NEG_BINDINDS_TEST
--
select
  case count(*)
    when 682 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NEG_BINDINDS_TEST
  , '682 rows expected' as EXPECTED
  , count(*) as ROWS
from NEG_BINDINGS;

--
-- CALC1__L3_minus_NEG_BINDINGS_TEST
--
select
  case count(*)
    when 12367 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as CALC1__L3_minus_NEG_BINDINGS_TEST
  , '12367 rows expected' as EXPECTED
  , count(*) as ROWS
from(
  select
    NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B
  from LAYER3
  except
  select
    NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B
  from NEG_BINDINGS
  )
;

/*
--
-- CALC2__L3_minus_NEG_BINDINGS_with_SCOREs_TEST
--
select
  case count(*)
    when 12680 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as CALC2__L3_minus_NEG_BINDINGS_with_SCOREs_TEST
  , '12680 rows expected' as EXPECTED
  , count(*) as ROWS
from(
  select
    NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B
    , SCORE
  from LAYER3
  except
  select
    NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B
    , SCORE
  from NEG_BINDINGS
)
;
*/

.print Count of NEG_BINDINGS union with POS_BINDING
select
  case count(*)
    when 9376 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NEG_BINDINGS_union_with_POS_BINDING
  , '9376 rows expected' as EXPECTED
  , count(*) as ROWS
from (
select * from NEG_BINDINGS
union
select * from POS_BINDINGS
)
;
.print Count of NEG_BINDINGS union with POS_BINDING <<< ONLY A,B columns
select
  case count(*)
    when 9376 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NEG_BINDINGS_union_with_POS_BINDING_only_A_n_B_cols
  , '9376 rows expected' as EXPECTED
  , count(*) as ROWS
from (
  select A,B from NEG_BINDINGS
  union
  select A,B from POS_BINDINGS
)
;


.print Count of NEG_BINDINGS intersect POS_BINDING
select
  case count(*)
    when 0 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NEG_BINDINGS_intersect_POS_BINDING
  , '0 rows expected' as EXPECTED
  , count(*) as ROWS
from (
  select * from NEG_BINDINGS
  intersect
  select * from POS_BINDINGS
)
;
.print Count of NEG_BINDINGS intersect with POS_BINDING <<< ONLY A,B columns
select
  case count(*)
    when 0 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NEG_BINDINGS_intersect_POS_BINDING_only_A_n_B_cols
  , '0 rows expected' as EXPECTED
  , count(*) as ROWS
from (
  select A,B from NEG_BINDINGS
  intersect
  select A,B from POS_BINDINGS
)
;

--
--
.print Count of NP_UNION
select
  case count(*)
    when 9376 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NP_UNION
  , '9376 rows expected' as EXPECTED
  , count(*) as ROWS
from NP_UNION;

--
--
.print Count of NP_INTERSECT
select
  case count(*)
    when 0 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NP_INTERSECT
  , '0 rows expected' as EXPECTED
  , count(*) as ROWS
from NP_INTERSECT;


--
--
.print Count of NP_UNION inner join with itself
select
  case count(*)
    when 9368 then '>>>>> PASSED'
    else '>>>>> FAILED/CHANGED'
  end as NP_UNION_inner_join_NP_UNION
  , '9368 rows expected' as EXPECTED
  , count(*) as ROWS
from (
  select N.A, N.B from NP_UNION N
    inner join NP_UNION N2 on N2.B = N.A and N2.A = N.B
)
;
