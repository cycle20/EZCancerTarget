##
## fda-extract.sh:
##
## usage example: bash exec/fda-extract.sh data/drug-label-0001-of-0011.json > extracted.json
##

jq '[ .results | .[] |
  {
    "set_id": .set_id,
    "id": .id,
    "version": .version,
    "effective_time": .effective_time,
    "openfda": .openfda
  }
]' "$1"
