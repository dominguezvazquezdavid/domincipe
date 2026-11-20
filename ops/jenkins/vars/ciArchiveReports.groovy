// Archive every report the pipeline produces (design D10, task 5.1).
//
// Loaded by path from the Jenkinsfile, so it is versioned with the pipeline.
// The patterns arrive before the stages that fill them and each one tolerates a
// missing match: a report that does not exist yet must not turn a green build
// red, and must still be archived as soon as its stage writes it.

def call() {
    // Unit and slice, then integration (change ci-integration, design D9). Both sets are
    // separate files in separate directories, so a red integration run cannot hide behind a
    // green unit run: the report lists them as two groups and the build still fails.
    junit allowEmptyResults: true, keepLongStdio: true,
          testResults: '**/target/surefire-reports/*.xml, **/target/failsafe-reports/*.xml'
    // The gate measures jacoco/, not jacoco-it/: the second one is archived as evidence, not as
    // a threshold (design D6).
    archiveArtifacts artifacts: '**/target/site/jacoco/**', allowEmptyArchive: true
    archiveArtifacts artifacts: '**/target/site/jacoco-it/**', allowEmptyArchive: true
    archiveArtifacts artifacts: 'sbom/*.json', allowEmptyArchive: true
    archiveArtifacts artifacts: 'security/*.json', allowEmptyArchive: true
    // The e2e stage writes the junit report of Playwright, its traces (only on failure) and the
    // logs of the environment it ran against, so a red smoke explains itself after the project
    // has been torn down (design D9).
    archiveArtifacts artifacts: 'e2e-artifacts/**', allowEmptyArchive: true
}

// `load` returns the result of running the script, not the script object, so
// the file hands itself back and the Jenkinsfile can call its methods. Without
// this line `load(...).call()` is a call on null (reproduced in build #1).
return this
