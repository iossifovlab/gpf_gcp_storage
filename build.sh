#!/bin/bash

shopt -s extdebug
shopt -s inherit_errexit
set -e

. build-scripts/loader-extended.bash

loader_addpath build-scripts/

# shellcheck source=build-scripts/libmain.sh
include libmain.sh
# shellcheck source=build-scripts/libbuild.sh
include libbuild.sh
# shellcheck source=build-scripts/libdefer.sh
include libdefer.sh
# shellcheck source=build-scripts/liblog.sh
include liblog.sh
# shellcheck source=build-scripts/libopt.sh
include libopt.sh

function main() {
  local -A options
  libopt_parse options \
    stage:all preset:fast clobber:allow_if_matching_values build_no:0 \
    generate_jenkins_init:no expose_ports:no -- "$@"

  local preset="${options["preset"]}"
  local stage="${options["stage"]}"
  local clobber="${options["clobber"]}"
  local build_no="${options["build_no"]}"
  local generate_jenkins_init="${options["generate_jenkins_init"]}"
  local expose_ports="${options["expose_ports"]}"

  libmain_init iossifovlab.gpf_gcp_storage gpf_gcp_storage
  libmain_init_build_env \
    clobber:"$clobber" preset:"$preset" build_no:"$build_no" \
    generate_jenkins_init:"$generate_jenkins_init" \
    expose_ports:"$expose_ports" \
    iossifovlab.gpf

  libmain_save_build_env_on_exit
  libbuild_init stage:"$stage" registry.seqpipe.org

  defer_ret build_run_ctx_reset_all_persistent

  build_run_ctx_init "local"
  defer_ret build_run_ctx_reset

  build_stage "Cleanup"
  {

    build_run_ctx_init "container" "ubuntu:22.04"
    defer_ret build_run_ctx_reset

    build_run rm -rvf ./build-env/*.yaml
    build_run rm -rf /wd/results /wd/sources /wd/test-results /wd/data

    build_run_local mkdir -p results test-results

  }

  build_stage "Clone projects"
  {
    build_run_local mkdir -p projects

    # the quotes around 'EOF' are signifcant - it forces bash to treat the string as literal string until EOF
    build_run_local bash -e -x <<'EOF'
        project_name="iossifovlab.gpf"
        if ! [ -d "projects/$project_name.repo" ]; then
          git clone "ssh://git@github.com/${project_name/.//}" "projects/$project_name.repo"
        fi
EOF

    # the quotes around 'EOF' are signifcant - it forces bash to treat the string as literal string until EOF
    build_run_local env gpf_git_describe="$(e gpf_git_describe)" gpf_git_branch="$(e gpf_git_branch)" bash -e -x << 'EOF'

        project_name="iossifovlab.gpf"
        project_repo_dirname="iossifovlab.gpf.repo"

        cd "projects/$project_repo_dirname"
        git checkout $gpf_git_branch
        git pull --ff-only

        git checkout "$gpf_git_describe"
        cd -
EOF

  }

  # prepare gpf data
  build_stage "Prepare GPF environment"
  {
    build_run_local bash -c "mkdir -p ./cache"
    build_run_local bash -c "touch ./cache/grr_definition.yaml"
    build_run_local bash -c 'cat > ./cache/grr_definition.yaml << EOT
id: "default"
type: "url"
url: "https://grr.seqpipe.org/"
cache_dir: "/wd/cache/grrCache"
EOT
'

    build_run_local bash -c "mkdir -p ./data/data-hg19-empty"
    build_run_local bash -c "touch ./data/data-hg19-empty/gpf_instance.yaml"

    build_run_local bash -c 'cat > ./data/data-hg19-empty/gpf_instance.yaml << EOT
reference_genome:
  resource_id: "hg19/genomes/GATK_ResourceBundle_5777_b37_phiX174"

gene_models:
  resource_id: "hg19/gene_models/refGene_v20190211"

EOT
'
  }


  local gpf_gcp_storage_image="gpf-gcp-storage-dev"
  local gpf_gcp_storage_image_ref
  # create gpf docker image
  build_stage "Create gpf_gcp_storage docker image"
  {
    local gpf_dev_tag
    gpf_dev_tag="$(e docker_img_gpf_dev_tag)"
    build_docker_image_create "$gpf_gcp_storage_image" \
        "projects/iossifovlab.gpf.repo/gcp_storage" \
        "projects/iossifovlab.gpf.repo/gcp_storage/Dockerfile" \
        "$gpf_dev_tag"
    gpf_gcp_storage_image_ref="$(e docker_img_gpf_gcp_storage_dev)"
  }

#   # Tests - dae
#   build_stage "Tests - impala2_storage"
#   {
#     local project_dir
#     project_dir="/wd/projects/iossifovlab.gpf.repo"

#     build_run_ctx_init "container" "${gpf_impala2_storage_image_ref}" \
#       --network "${ctx_network["network_id"]}" \
#       --env DAE_DB_DIR="/wd/data/data-hg19-empty/" \
#       --env GRR_DEFINITION_FILE="/wd/cache/grr_definition.yaml" \
#       --env DAE_HDFS_HOST="impala" \
#       --env DAE_IMPALA_HOST="impala"

#     defer_ret build_run_ctx_reset

#     build_run_container scripts/wait-for-it.sh -h impala -p 21050 -t 300

#     for d in $project_dir/dae $project_dir/wdae $project_dir/dae_conftests $project_dir/impala2_storage; do
#       build_run_container bash -c 'cd "'"${d}"'"; /opt/conda/bin/conda run --no-capture-output -n gpf \
#         pip install -e .'
#     done

#     build_run_container bash -c '
#         project_dir="/wd/projects/iossifovlab.gpf.repo";
#         cd $project_dir/impala2_storage;
#         export PYTHONHASHSEED=0;
#         /opt/conda/bin/conda run --no-capture-output -n gpf py.test -v \
#           --durations 20 \
#           --cov-config $project_dir/coveragerc \
#           --junitxml=/wd/results/impala2-storage-junit.xml \
#           --cov impala2_storage \
#           impala2_storage/ || true'

#     build_run_container cp /wd/results/impala2-storage-junit.xml /wd/test-results/

#     build_run_container bash -c '
#         project_dir="/wd/projects/iossifovlab.gpf.repo";
#         cd $project_dir/impala2_storage;
#         export PYTHONHASHSEED=0;
#         /opt/conda/bin/conda run --no-capture-output -n gpf py.test -v \
#           --durations 20 \
#           --cov-config $project_dir/coveragerc \
#           --junitxml=/wd/results/impala2-storage-integration-junit.xml \
#           --cov-append --cov impala2_storage \
#           $project_dir/dae/tests/ --gsf $project_dir/impala2_storage/impala2_storage/tests/impala2_storage.yaml || true'

#     build_run_container cp /wd/results/impala2-storage-integration-junit.xml /wd/test-results/

#     build_run_container bash -c '
#         project_dir="/wd/projects/iossifovlab.gpf.repo";
#         cd $project_dir/impala2_storage;
#         if [ -f ".coverage" ]; then
#             coverage xml;
#             cp -f coverage.xml /wd/test-results/;
#             coverage html --title "GPF impala storage" -d /wd/test-results/coverage-html;          
#         fi'

#   }

}

main "$@"
