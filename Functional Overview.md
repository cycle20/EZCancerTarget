### Quick Overview of Functionality

```
=============== INITIAL STAGE: CLUE.IO SEARCH =================

                       +---------------+
                       | Input table   |
                       +-------o-------+
                               |
                               |
                               v
                      +-----------------+
                      | clue.io search  |
                      +--------o--------+
                               |
                               |
                       ( result table )
                               |
                               |
                               v

==================== NEXT STAGE: "DATAPATCH" ==================

"Additional details based on the
 result of the clue.io search."

                               |
                               |
         +--------------+------+------+------------+
         |              |             |            |
         v              v             v            v
   +-----------+   +--------+    +--------+   +---------+
   | FDA Label |   | PubMed |    |  EMA   |   | UniProt |
   |  search   |   | search |    | search |   | search  |
   +-----o-----+   +----o---+    +----o---+   +----o----+
         |              |             |            |
         +--------------+------+------+------------+
                               |
                               |
                               v

==================== FINAL STAGE: "RENDER" ====================

                               |          ( extended dataset )
                               |
                               v
      +------------------------------------------------+
      | * Generate HTML page from the extended dataset |
      | * Deploy it as GitHub Page                     |
      +------------------------------------------------+
```
