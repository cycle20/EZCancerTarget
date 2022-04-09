
# Issue #44: reminder

* **If** there is no stopped container,
  * **then** check ```exec/docker/run_rocker.bash``` for more details to bring up an environment,
  * **else** start the stopped container. e.g.: ```sudo docker start wonderful_haibt```

Run tests from command line:
* ```Rscript -e 'tinytest::test_all()'```
