#!/bin/bash -e

# Create the deploy/k8s files for each java version of each of the Quarkus services
# Then add on the ui-super-heroes

INPUT_DIR=src/main/kubernetes
OUTPUT_DIR=deploy/k8s

create_output_file() {
  local output_file=$1

  if [[ ! -f "$output_file" ]]; then
    echo "Creating output file: $output_file"
    touch $output_file
  fi
}

do_build() {
  local project=$1
  local deployment_type=$2
  local javaVersion=$3
  local kind=$4
  local tag="${kind}java${javaVersion}-latest"
  local git_server_url="${GITHUB_SERVER_URL:=https://github.com}"
  local git_repo="${GITHUB_REPOSITORY:=edeandrea/quarkus-super-heroes}"
  local git_ref="${GITHUB_REF_NAME:=main}"

  if [[ "$kind" == "native-" ]]; then
    local mem_limit="128Mi"
  else
    local mem_limit="768Mi"
  fi

  echo "Generating app resources for $project/$tag/$deployment_type"
  set -x
  rm -rf $project/target

  $project/mvnw -f $project/pom.xml versions:set clean package \
    -DskipTests \
    -DnewVersion=$tag \
    -Dquarkus.container-image.tag=$tag \
    -Dquarkus.kubernetes.deployment-target=$deployment_type \
    -Dquarkus.kubernetes.version=$tag \
    -Dquarkus.kubernetes.resources.limits.memory=$mem_limit \
    -Dquarkus.kubernetes.annotations.\"app.quarkus.io/vcs-url\"=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY \
    -Dquarkus.kubernetes.annotations.\"app.quarkus.io/vcs-ref\"=$GITHUB_REF_NAME \
    -Dquarkus.openshift.version=$tag \
    -Dquarkus.openshift.resources.limits.memory=$mem_limit \
    -Dquarkus.openshift.annotations.\"app.openshift.io/vcs-url\"=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY \
    -Dquarkus.openshift.annotations.\"app.openshift.io/vcs-ref\"=$GITHUB_REF_NAME

  set +x
}

process_quarkus_project() {
  local project=$1
  local deployment_type=$2
  local javaVersion=$3
  local kind=$4
  local output_filename="${kind}java${javaVersion}-${deployment_type}"
  local app_generated_input_file="$project/target/kubernetes/${deployment_type}.yml"
  local project_output_file="$project/$OUTPUT_DIR/${output_filename}.yml"
  local all_apps_output_file="$OUTPUT_DIR/${output_filename}.yml"

  # 1st do the build
  # The build will generate all the resources for the project
  do_build $project $deployment_type $javaVersion $kind

  set -x
  rm -rf $project_output_file
  set +x

  create_output_file $project_output_file
  create_output_file $all_apps_output_file

  # Now merge the generated resources to the top level (deploy/k8s)
  if [[ -f "$app_generated_input_file" ]]; then
    echo "Copying app generated input ($app_generated_input_file) to $project_output_file and $all_apps_output_file"
    set -x
    cat $app_generated_input_file >> $project_output_file
    cat $app_generated_input_file >> $all_apps_output_file
    set +x
  fi

  if [[ "$project" == "rest-fights" ]]; then
    # Create a descriptor for all of the downstream services (rest-heroes and rest-villains)
    local all_downstream_output_file="$project/$OUTPUT_DIR/${output_filename}-all-downstream.yml"
    local villains_output_file="rest-villains/$OUTPUT_DIR/${output_filename}.yml"
    local heroes_output_file="rest-heroes/$OUTPUT_DIR/${output_filename}.yml"

    set -x
    rm -rf $all_downstream_output_file
    set +x

    create_output_file $all_downstream_output_file

    echo "Copying ${app_generated_input_file}, ${villains_output_file}, and $heroes_output_file to $all_downstream_output_file"
    set -x
    cat $villains_output_file >> $all_downstream_output_file
    cat $heroes_output_file >> $all_downstream_output_file
    cat $app_generated_input_file >> $all_downstream_output_file
    set +x
  fi
}

process_ui_project() {
  local javaVersion=$1
  local deployment_type=$2
  local kind=$3
  local project="ui-super-heroes"
  local project_input_directory="$project/$INPUT_DIR"
  local app_input_file="$project_input_directory/app.yml"
  local project_route_file="$project_input_directory/route.yml"
  local project_ingress_file="$project_input_directory/ingress.yml"
  local project_output_file="$project/$OUTPUT_DIR/app-${deployment_type}.yml"
  local all_apps_output_file="$OUTPUT_DIR/${kind}java${javaVersion}-${deployment_type}.yml"

  set -x
  rm -rf $project_output_file
  set +x

  create_output_file $project_output_file

  if [[ -f "$app_input_file" ]]; then
    echo "Copying app input ($app_input_file) to $project_output_file and $all_apps_output_file"
    set -x
    cat $app_input_file >> $project_output_file
    cat $app_input_file >> $all_apps_output_file
    set +x
  fi

  if [[ "$deployment_type" == "openshift" ]]; then
    echo "Copying $project_route_file to $project_output_file and $all_apps_output_file"
    set -x
    cat $project_route_file >> $project_output_file
    cat $project_route_file >> $all_apps_output_file
    set +x
  else
    echo "Copying $project_ingress_file to $project_output_file and $all_apps_output_file"
    set -x
    cat $project_ingress_file >> $project_output_file
    cat $project_ingress_file >> $all_apps_output_file
    set +x
  fi
}

set -x
rm -rf $OUTPUT_DIR/*.yml
set +x

for javaVersion in 11 17
do
  for kind in "" "native-"
  do
    for deployment_type in "kubernetes" "minikube" "openshift"
    do
      for project in "rest-villains" "rest-heroes" "rest-fights" "event-statistics"
      do
        process_quarkus_project $project $deployment_type $javaVersion $kind
      done

      process_ui_project $javaVersion $deployment_type $kind
    done
  done
done
