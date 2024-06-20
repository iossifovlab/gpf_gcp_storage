pipeline {
  agent { label 'eyoree' }
  options {
    copyArtifactPermission('/iossifovlab/*,/seqpipe/*');
    disableConcurrentBuilds()
  }
  environment {
    BUILD_SCRIPTS_BUILD_DOCKER_REGISTRY_USERNAME = credentials('jenkins-registry.seqpipe.org.user')
    BUILD_SCRIPTS_BUILD_DOCKER_REGISTRY_PASSWORD_FILE = credentials('jenkins-registry.seqpipe.org.passwd')
    SEQPIPE_GCP_STORAGE_TESTING=credentials('seqpipe-gcp-storage-testing')
    TRIGGER_ONLY_BETWEEN="02:00-07:00"
  }

  stages {
    stage('Start') {
      steps {
        zulipSend(
          message: "Started build #${env.BUILD_NUMBER} of project ${env.JOB_NAME} (${env.BUILD_URL})",
          topic: "${env.JOB_NAME}")
      }
    }
    stage('Generate stages') {
      steps {
        sh "./build.sh preset:slow build_no:${env.BUILD_NUMBER} generate_jenkins_init:yes"
        script {
          load('Jenkinsfile.generated-stages')
        }
      }
    }
  }
  post {
    always {
      script {
        try {
          resultBeforeTests = currentBuild.currentResult
          junit 'test-results/gcp-storage-junit.xml, test-results/gcp-storage-integration-junit.xml'
          sh "test ${resultBeforeTests} == ${currentBuild.currentResult}"

          cobertura coberturaReportFile: 'test-results/coverage.xml',
            enableNewApi: false, onlyStable: false, sourceEncoding: 'ASCII'

          publishHTML (target : [allowMissing: true,
            alwaysLinkToLastBuild: true,
            keepAll: true,
            reportDir: 'test-results/coverage-html',
            reportFiles: 'index.html',
            reportName: 'gpf-gcp-storage-coverage-report',
            reportTitles: 'gpf-gcp-storage-coverage-report'])

        } finally {
          zulipNotification(
            topic: "${env.JOB_NAME}"
          )
        }
      }
    }
    unstable {
      script {
        load('build-scripts/libjenkinsfile/zulip-tagged-notification.groovy').zulipTaggedNotification()
      }
    }
    failure {
      script {
        load('build-scripts/libjenkinsfile/zulip-tagged-notification.groovy').zulipTaggedNotification()
      }
    }
  }
}
