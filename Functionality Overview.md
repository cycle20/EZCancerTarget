### Quick Overview of Functionality

```
                           +---------------+
                           | Input table   |
                           +-------o-------+
                                   |
                                   |
                                   v
                          +-----------------+
                          | clue.io search  |
                          +-----------------+
                                   |
                                   |
                             result table
                                   |
                                   |
                                   v

    ==================== NEXT STAGE: "DATAPATCH" ========================= 

                                   |
                                   |
                                   v

             +---------------------o
             |
             |   [additional details from other sources to result of clue]
             |
             v
    +------------------+       +---------------+       +------------+
    | FDA Label search |  -->  | PubMed search |  -->  | EMA search |
    +------------------+       +---------------+       +------o-----+
                                                              |
                                                              |
             +------------------------------------------------+
             |
             |
             v
    +----------------+
    | UniProt search | ------------+  
    +----------------+             |
                                   |
                                   v

    ==================== FINAL STAGE: "RENDER" ===========================



```

