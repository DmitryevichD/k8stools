#!/bin/bash

# Treat unset variables as an error
set -o nounset

# Reset in case getopts has been used previously in the shell
OPTIND=1

printf -v date '%(%Y-%m-%dT%H:%M:%S)T' -1
POSTFIX_OUTPUT=_schema_${date}.puml
NAMESPACE=
SCHEMA_DIR=schemas
OUTPUT=
MAX_WIDTH_DEFAULT=1980
MAX_WIDTH=

mkdir -p $SCHEMA_DIR

function usage() {
  echo "$0 - scan kubernetes cluster and generates a schema using PlantUML syntax"
  echo ""
  echo "Usage: $0 [-c CONFIG] [-n NAMESPACE]"
  printf "\n"
  echo "Available options:"
  echo "    -c CONFIG             Sets a kubernetes config that will be used by kubectl"
  echo "    -n NAMESPACE          Uses a namespace filter.  Default will be used all namespaces"
  echo "    -w MAX_WIDTH          Set max width for the schema.  Default will be used $MAX_WIDTH_DEFAULT"
  echo ""
  echo "Example: $0 -c kube.conf"
}

while getopts "c:n:w:h" opt; do
  case "$opt" in
  c) export KUBECONFIG="$OPTARG" ;;
  n) NAMESPACE="$OPTARG" ;;
  w) MAX_WIDTH="$OPTARG" ;;
  h) usage ;;
  *) echo "$0 is using default k8s config" ;;
  esac
done

if [[ "$MAX_WIDTH" =~ ^[0-9]+$ ]]; then
  echo "Diagram width = $MAX_WIDTH"
else
  if [[ -n "$MAX_WIDTH" ]]; then
    echo "-w is incorrect. Will be used default value: $MAX_WIDTH_DEFAULT"
  fi
  MAX_WIDTH="$MAX_WIDTH_DEFAULT"
fi

OUTPUT=$SCHEMA_DIR

startPuml() {
  echo "@startuml kubernetes" >"$OUTPUT"
  {
    echo "title IGaming cluster diagram"
    echo "!pragma horizontalLineBetweenDifferentPackageAllowed"
    echo ""
    echo "left to right direction"
    echo ""
    echo "scale max $MAX_WIDTH width"
    echo ""
    echo "' Kubernetes"
    echo "!define KubernetesPuml https://raw.githubusercontent.com/dcasati/kubernetes-PlantUML/master/dist"
    echo ""
    echo "!includeurl KubernetesPuml/kubernetes_Common.puml"
    echo "!includeurl KubernetesPuml/kubernetes_Context.puml"
    echo "!includeurl KubernetesPuml/kubernetes_Simplified.puml"
    echo "!includeurl KubernetesPuml/OSS/KubernetesSvc.puml"
    echo "!includeurl KubernetesPuml/OSS/KubernetesDeploy.puml"
    echo "!includeurl KubernetesPuml/OSS/KubernetesIng.puml"
    echo ""
    echo "Cluster_Boundary(cluster, \"Cluster\") {"
    echo ""
  } >>"$OUTPUT"
}

endPuml() {
  {
    echo "}"
    echo "@enduml"
  } >>"$OUTPUT"
}

convertToPumlComponentName() {
  local sourceComponentName=$1
  echo "$sourceComponentName" | tr -d '"-' | tr -d ' '
}

startPumlNamespaceBlock() {
  local namespace=$1
  local namespaceComponent
  namespaceComponent="$(convertToPumlComponentName "$namespace")"

  printf "\nNamespace_Boundary(%s, \"%s\") {\n" "$namespaceComponent" "$namespace" >>"$OUTPUT"
}

endPumlNamespaceBlock() {
  printf "\n}\n" >>"$OUTPUT"
}

function warning() {
  local message=$1
  local componentName
  componentName="$(
    echo $RANDOM | md5sum | head -c 20
    echo
  )"
  {
    echo "{{json"
    echo "#highlight \"WARNING\""
    echo "{\"WARNING\": \"$message\"}"
    printf "}}\n"
  } >>"$OUTPUT"
}

function printComponentDetails() {
  local details=$1

  local namespace
  namespace="$(echo "$details" | jq 'if type=="array" then .[0] else . end | .namespace')"
  namespace="$(convertToPumlComponentName "$namespace")"

  local kind
  kind="$(echo "$details" | jq 'if type=="array" then .[0] else . end | .kind')"
  kind="$(convertToPumlComponentName "$kind")"

  local name
  name="$(echo "$details" | jq 'if type=="array" then .[0] else . end | .name')"
  name="$(convertToPumlComponentName "$name")"

  local componentName
  componentName="$(printf "%s_%s_%s" "$namespace" "$name" "$kind")"
  {
    printf "\n"
    echo "= __$(echo "$kind" | tr -d '"')__"
    echo "{{json"
    echo "$details"
    echo "}}"
    printf "\n"
  } >>"$OUTPUT"
}

function generatePodDetailsFromDeployment() {
  local deployment=$1
  local podDetails
  podDetails="$(echo "$deployment" | jq -c '.items[].spec.template.spec.containers[] | {namespace: "", name: .name, kind: "Pod", image: .image, ports: .ports, env: .env, livenessProbe: .livenessProbe, readiness: .readinessProbe}' | jq -sc | sed 's/ -/\\\\n-/g')"
  if [[ -n "$podDetails" && "$podDetails" != "null" ]]; then
    printComponentDetails "$podDetails"
  else
    warning "Deployment doesn't contains any containers"
  fi
}

function generatePodDetailsFromSelector() {
  local selector=$1
  local podDetails
  podDetails="$(kubectl get pods -l "$selector" --all-namespaces -o json | jq -c '.items[0]')"

  local namespace
  namespace="$(echo "$podDetails" | jq .metadata.namespace | tr -d '"')"

  local name
  name="$(echo "$podDetails" | jq .metadata.name | tr -d '"')"

  local kind
  kind="$(echo "$podDetails" | jq .kind | tr -d '"')"

  local details
  details="$(echo "$podDetails" | jq -c '.spec.containers[] | {namespace: "NAMESPACE", name: "NAME", kind: "KIND", image: .image, ports: .ports, env: .env, livenessProbe: .livenessProbe, readiness: .readinessProbe}' | jq -sc | sed 's/ -/\\\\n-/g' | sed "s/NAMESPACE/$namespace/g" | sed "s/NAME/$name/g" | sed "s/KIND/$kind/g")"

  if [[ -n "$details" && "$details" != "null" ]]; then
    printComponentDetails "$details"
  else
    warning "Deployment doesn't contains any containers"
  fi
}

function generateDeployDetails() {
  local selector
  local deployment
  local deployDetails
  selector="$(echo "$1" | tr -d '\n" {}' | tr ':' '=')"
  deployment="$(kubectl get deployment -l "$selector" --all-namespaces -o json)"
  deployDetails="$(echo "$deployment" | jq -c '.items[] | {namespace: .metadata.namespace, name: .metadata.name, kind: .kind, strategy: .spec.strategy, replicas: .spec.replicas, labels: .metadata.labels}')"
  if [[ -n "$deployDetails" && "$deployDetails" != "null" ]]; then
    printComponentDetails "$deployDetails"
    generatePodDetailsFromDeployment "$deployment"
  else
    warning "Deployment by selector $selector not found"
    generatePodDetailsFromSelector "$selector"
  fi
}

function printKubernetesSvcTitle() {
  local service=$1
  printf "KubernetesSvc(%s_svc, %s, \"\") {\ncomponent %s_cmp [" "$(convertToPumlComponentName "$service")" "$service" "$(convertToPumlComponentName "$service")" >>"$OUTPUT"
}

function printKubernetesSvcFooter() {
  printf "\n]\n}\n" >>"$OUTPUT"
}

function printKubernetesIngTitle() {
  local ingress=$1
  printf "KubernetesIng(%s_ing, %s, \"\") {\ncomponent %s_cmp [\n" "$(convertToPumlComponentName "$ingress")" "$ingress" "$(convertToPumlComponentName "$ingress")" >>"$OUTPUT"
}

function printKubernetesIngFooter() {
  printf "\n]\n}\n" >>"$OUTPUT"
}

function generateServiceDetails() {
  local namespace=$1
  local service=$2
  printKubernetesSvcTitle "$service"

  local serviceDetails
  serviceDetails="$(kubectl get service "$service" -n "$namespace" -o json | jq -c '{namespace: .metadata.namespace, name: .metadata.name, kind: .kind, type: .spec.type, clusterIP: .spec.clusterIP, ports: .spec.ports, selector: .spec.selector}')"
  printComponentDetails "$serviceDetails"

  local selector
  selector="$(echo "$serviceDetails" | jq .selector)"
  if [[ -n "$selector" && "$selector" != "null" ]]; then
    generateDeployDetails "$selector"
  else
    warning "Service $service doesn't have any selectors"
  fi
  printKubernetesSvcFooter
}

function generateServiceInfo() {
  local namespace=$1
  local service
  kubectl get services -n "$namespace" -o json | jq -c .items[].metadata.name |
    while IFS= read -r service; do
      service="$(echo "$service" | tr -d '"')"
      generateServiceDetails "$namespace" "$service"
    done
}

function generateIngressInfo() {
  local namespace=$1
  local ingress
  local ingressName
  ingressIsExist=0
  kubectl get ingress -n "$namespace" -o json | jq -c '.items[] | {namespace: .metadata.namespace, name: .metadata.name, kind: .kind, labels: .metadata.labels, rules: .spec.rules}' |
    while IFS= read -r ingress; do
      ingressIsExist=1
      ingressName="$(echo "$ingress" | jq .name)"
      printKubernetesIngTitle "$ingressName"
      {
        echo "= __INGRESS__"
        echo "{{json"
        echo "$ingress" | jq -c .rules
        echo "}}"
        printf "\n"
        printKubernetesIngFooter
      } >>"$OUTPUT"
    done
  if [[ "$ingressIsExist" == "0" ]]; then
    printKubernetesIngTitle "${namespace}_ingress"
    warning "Namespace $namespace doesn't contain any ingress"
    printKubernetesIngFooter
  fi
}

function generateSchemaByNamespace() {
  local namespace=$1
  OUTPUT="$SCHEMA_DIR/$namespace$POSTFIX_OUTPUT"
  startPuml
  startPumlNamespaceBlock "$namespace"
  generateIngressInfo "$namespace"
  generateServiceInfo "$namespace"
  endPumlNamespaceBlock
  endPuml
  echo "Created: $OUTPUT"
}

function generateSchema() {
  local namespace
  kubectl get namespaces -o json | jq '.items[].metadata.name' | tr -d '"' |
    while IFS= read -r namespace; do
      generateSchemaByNamespace "$namespace"
    done
}

if [[ -n "$NAMESPACE" ]]; then
  generateSchemaByNamespace "$NAMESPACE"
else
  generateSchema
fi

echo "Done!"
