// Archive every report the pipeline produces (design D10, task 5.1).
//
// Loaded by path from the Jenkinsfile, so it is versioned with the pipeline.
// The patterns arrive before the stages that fill them and each one tolerates a
// missing match: a report that does not exist yet must not turn a green build
// red, and must still be archived as soon as its stage writes it.

def call() {
    junit allowEmptyResults: true, keepLongStdio: true,
          testResults: '**/target/surefire-reports/*.xml'
    archiveArtifacts artifacts: '**/target/site/jacoco/**', allowEmptyArchive: true
    archiveArtifacts artifacts: 'sbom/*.json', allowEmptyArchive: true
    archiveArtifacts artifacts: 'security/*.json', allowEmptyArchive: true
}
