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

.print Query into BQD.NP_UNION2 table
drop table if exists BQD.NP_UNION2;
create table BQD.NP_UNION2 as
  select * from BQD.NEG_BINDINGS
  union
  select * from BQD.POS_BINDINGS
;

