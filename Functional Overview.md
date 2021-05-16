### Quick Overview of Functionality

```
    =============== INITIAL STAGE: CLUE.IO SEARCH ========================= 

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

    ==================== NEXT STAGE: "DATAPATCH" ========================= 

                                   |    "This stage provides additional details
                                   |     from other sources to result of clue."
                                   |
                                   v

             +---------------------+
             |
             |
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

                                   |
                          ( extended dataset )
                                   |
                                   v

           +------------------------------------------------+
           | * Generate HTML page from the extended dataset |
           | * Deploy it as GitHub Page                     |
           +------------------------------------------------+

```
