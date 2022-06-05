# Scan k8s cluster and generates a schema using PlantUML syntax

#### Requirements:

[**JQ command-line JSON processor**](https://stedolan.github.io/jq/)

[**PlantUML**](https://plantuml.com/)

#### Usage:

`schemagenerator.sh [-c CONFIG] [-f FILE]`

##### Available options:

- `-c CONFIG` - Sets the kubernetes config to be used by kubectl

##### Example:

`schemagenerator.sh -c customconfig.conf`  

##### Result:

