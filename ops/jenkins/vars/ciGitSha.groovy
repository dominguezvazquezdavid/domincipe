// The commit a build represents (design D3, task 5.1).
//
// The branch source checks out the pull-request head (OriginPullRequestDiscoveryTrait
// with strategyId 2, design D7), so GIT_COMMIT is the sha that task 8.1 publishes
// the status against. The git fallback covers a build whose environment lost it.

def call() {
    def sha = env.GIT_COMMIT?.trim()
    if (!sha) {
        sha = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
    }
    if (!sha) {
        error 'ciGitSha: the commit sha could not be resolved'
    }
    return sha
}
