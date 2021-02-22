--
-- TGFBR1.sql
--
select
  ip.preferred_name as name1,
  ip.protein_id as protein_a,
  ip2.preferred_name as name2,
  ip2.protein_id as protein_b,
  " -> " as direction,
  mode,
  action,
  score

from
  network_actions n
  inner join
    items_proteins ip ON item_id_a = ip.protein_id
  inner join
    items_proteins ip2 ON item_id_b = ip2.protein_id

where
  item_id_b = 4444485
  and a_is_acting  = "t"

UNION

select
  ip2.preferred_name as name1,
  ip2.protein_id as protein_b,
  ip.preferred_name as name2,
  ip.protein_id as protein_a,
  " <- " as direction,
  mode,
  action,
  score

from
  network_actions n
  inner join
    items_proteins ip ON item_id_a = ip.protein_id
  inner join
    items_proteins ip2 ON item_id_b = ip2.protein_id

where
  item_id_a = 4444485
  and a_is_acting  = "t"

order by
  name1, direction;
