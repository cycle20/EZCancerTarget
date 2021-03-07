--
-- binding_test.sql:
-- -----------------
--
-- unit test of binding_query.sql
--

--
-- FILTER_TEST
--
select
  case count(*)
    when 426510 then '>>>>> PASSED: returned: 426510 rows'
    else '>>>>> FAILED/CHANGED'
  end as FILTER_TEST
from FILTER;

--
-- NETWORK_ACTIONS_DIRECTIONAL 
--
select
  case count(*)
    when 23599 then '>>>>> PASSED: returned: 23599 rows'
    else '>>>>> FAILED/CHANGED'
  end as NETWORK_ACTIONS_DIRECTIONAL_TEST
from NETWORK_ACTIONS_DIRECTIONAL;

--
-- LAYER3_TEST
--
select
  case count(*)
    when 12860 then '>>>>> PASSED: returned: 12860 rows'
    else '>>>>> FAILED/CHANGED'
  end as LAYER3_TEST
from LAYER3;

--
-- POS_BINDINDS_TEST
--
select
  case count(*)
    when 10787 then '>>>>> PASSED: returned: 10787 rows'
    else '>>>>> FAILED/CHANGED'
  end as POS_BINDINDS_TEST
from POS_BINDINGS;

--
-- NEG_BINDINDS_TEST
--
select
  case count(*)
    when 90 then '>>>>> PASSED: returned: 90 rows'
    else '>>>>> FAILED/CHANGED'
  end as NEG_BINDINDS_TEST
from NEG_BINDINGS;

--
-- CALC1__L3_minus_NEG_BINDINGS_TEST
--
select
  case count(*)
    when 12367 then '>>>>> PASSED: returned: 12367 rows'
    else '>>>>> FAILED/CHANGED'
  end as CALC1__L3_minus_NEG_BINDINGS_TEST
from(
  select
    NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B, IS_DIRECTIONAL
  from LAYER3
  except
  select
    NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B, IS_DIRECTIONAL
  from NEG_BINDINGS
  )
;

--
-- NAME_A,UNI_A,EXTERN_A,NAME_B,UNI_B,EXTERN_B,A,B,IS_DIRECTIONAL
-- A1BG,P04217,9606.ENSP00000263100,PIK3CA,P42336,9606.ENSP00000263967,4435199,4435346,0
-- A1BG,P04217,9606.ENSP00000263100,PIK3CA,P42336,9606.ENSP00000263967,4435199,4435346,1
-- 

-- .print "LAYER3 query EXCEPT NEG_BINDINGS (first 4 rows)"
-- select * from (
--   select
--     NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B, IS_DIRECTIONAL
--   from LAYER3
--   except
--   select
--     NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B, IS_DIRECTIONAL
--   from NEG_BINDINGS
-- )
-- limit 4
-- ;

--
-- CALC2__L3_minus_NEG_BINDINGS_with_SCOREs_TEST
--
select
  case count(*)
    when 12680 then '>>>>> PASSED: returned: 12680 rows'
    else '>>>>> FAILED/CHANGED'
  end as CALC2__L3_minus_NEG_BINDINGS_with_SCOREs_TEST
from(
  select
    NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B, IS_DIRECTIONAL, SCORE
  from LAYER3
  except
  select
    NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B, IS_DIRECTIONAL, SCORE
  from NEG_BINDINGS
)
;

-- .print "LAYER3 query EXCEPT NEG_BINDINGS with scores (first 4 rows)"
-- select * from (
--   select
--     NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B, IS_DIRECTIONAL, SCORE
--   from LAYER3
--   except
--   select
--     NAME_A, UNI_A, EXTERN_A, NAME_B, UNI_B, EXTERN_B, A, B, IS_DIRECTIONAL, SCORE
--   from NEG_BINDINGS
-- )
-- limit 4
-- ;

.print Count of NEG_BINDINGS union with POS_BINDING
select count(*) from (
select * from NEG_BINDINGS
union
select * from POS_BINDINGS
)
;

.print Count of NEG_BINDINGS union with POS_BINDING <<< ONLY A,B columns
select count(*) from (
select A,B from NEG_BINDINGS
union
select A,B from POS_BINDINGS
)
;

drop view if exists NP_UNION;
create temporary view NP_UNION as
  select A,B from NEG_BINDINGS
  union
  select A,B from POS_BINDINGS
;

--
--
.print Count of NP_UNION
select count(*) from NP_UNION;

--
--
.print Count of NP_UNION inner join with itself
select count(*) from (
  select N.A, N.B from NP_UNION N
    inner join NP_UNION N2 on N2.B = N.A and N2.A = N.B
)
;
