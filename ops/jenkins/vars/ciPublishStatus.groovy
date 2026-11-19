// Publish the build result as a commit status on GitHub (design D7, task 8.1).
//
// Loaded by path from the Jenkinsfile, so it is versioned with the pipeline that
// uses it. The credential is resolved from the Jenkins store by id and consumed
// with `withCredentials`, which masks the password binding in every line the
// step prints: the PAT travels in an environment variable, never in the command
// line of a shell script the pipeline renders.
//
// The status is published on the commit the build represents, which the caller
// resolves with ciGitSha.groovy: the pull-request head, because the branch
// source discovers PRs on their head (design D7). A publication the API rejects
// is an error and not a warning: the branch protection of task 8.2 blocks on
// this context, so a build that cannot report its result is a build whose
// result nobody can trust.
//
// args:
//   sha           commit sha to publish against (required)
//   state         GitHub state: success, failure, error or pending; derived from
//                 the build result when omitted
//   description   short text of the status, 140 characters at most
//   context       check name; CI_STATUS_CONTEXT from the pipeline when omitted
//   repo          owner/repository; GITHUB_REPOSITORY from the pipeline
//   apiUrl        GitHub API root; GITHUB_API_URL from the pipeline
//   credentialsId credential of the Jenkins store; github-token by default

def call(Map args) {
    def sha = args.sha?.trim()
    if (!sha) {
        error "ciPublishStatus: 'sha' is required"
    }

    def repo = (args.repo ?: env.GITHUB_REPOSITORY)?.trim()
    if (!repo) {
        error "ciPublishStatus: 'repo' is required"
    }

    def apiUrl = (args.apiUrl ?: env.GITHUB_API_URL)?.trim() ?: 'https://api.github.com'
    while (apiUrl.endsWith('/')) {
        apiUrl = apiUrl.substring(0, apiUrl.length() - 1)
    }
    def context = (args.context ?: env.CI_STATUS_CONTEXT)?.trim() ?: 'domincipe'
    def credentialsId = args.credentialsId?.trim() ?: 'github-token'
    def state = args.state?.trim() ?: stateFor(currentBuild.currentResult)
    def description = args.description?.trim() ?: "${currentBuild.currentResult} (Jenkins build #${env.BUILD_NUMBER})"

    // target_url is what turns the check in the pull request into a link to the
    // build that produced it (README: how the CI is operated). BUILD_URL exists
    // because the controller declares its own address in casc/jenkins.yaml: an
    // unconfigured location reports `http://unconfigured-jenkins-location/...`,
    // which links nowhere.
    def payload = json([
        state      : state,
        context    : context,
        description: description,
        target_url : env.BUILD_URL,
    ])

    // The response body is kept on disk so a rejected status can name what
    // GitHub answered instead of only the code. The file lives in the workspace
    // for the length of the call and no archive pattern matches it.
    def response = '.ci-status-response.json'
    sh "rm -f '${response}'"

    def httpCode = '000'
    withCredentials([usernamePassword(credentialsId: credentialsId,
                                      usernameVariable: 'GITHUB_STATUS_USER',
                                      passwordVariable: 'GITHUB_STATUS_TOKEN')]) {
        // The token is the password of the credential (casc/jenkins.yaml) and
        // GitHub accepts it as a bearer token. The username binding is unused on
        // purpose: the fine-grained PAT identifies the caller by itself, which
        // is the form verified in task 4.3.
        httpCode = sh(script: """
            curl --silent --show-error \\
              --output '${response}' --write-out '%{http_code}' \\
              --request POST \\
              --header "Authorization: Bearer \${GITHUB_STATUS_TOKEN}" \\
              --header 'Accept: application/vnd.github+json' \\
              --header 'Content-Type: application/json' \\
              --data '${payload}' \\
              '${apiUrl}/repos/${repo}/statuses/${sha}'
        """, returnStdout: true).trim()
    }

    def body = fileExists(response) ? readFile(response).trim() : '(empty body)'
    sh "rm -f '${response}'"

    if (httpCode.length() != 3 || !httpCode.startsWith('2')) {
        error "ciPublishStatus: GitHub answered ${httpCode} for ${sha} in ${repo} (${context}=${state}): ${body}"
    }

    echo "ciPublishStatus: ${context}=${state} on ${sha} (HTTP ${httpCode}, ${env.BUILD_URL})"
}

// GitHub states are success, failure, error and pending. Everything that is not
// a green build blocks the merge of the pull request: UNSTABLE is a gate that
// did not pass, and an ABORTED build reported as `error` does not unblock it
// either (task 8.2 requires this context in develop and main).
private def stateFor(String result) {
    switch (result) {
        case 'SUCCESS':
            return 'success'
        case 'ABORTED':
            return 'error'
        default:
            return 'failure'
    }
}

// Four string fields whose values the pipeline controls — the state, the check
// name, the result and the build number — plus the build URL, so escaping the
// quotes and the backslashes of the text is enough and no JSON library is
// involved. Nothing that comes from the commit or the pull request is
// interpolated: the description is built here, not read from the API.
private def json(Map fields) {
    def body = '{'
    def separator = ''
    fields.each { name, value ->
        body += separator + '"' + name + '":"' + escapeText("${value}") + '"'
        separator = ','
    }
    return body + '}'
}

// Only the two characters that end a JSON string early, so the payload cannot
// be broken by a value the pipeline builds.
private def escapeText(String value) {
    return value.replace('\\', '\\\\').replace('"', '\\"')
}

// `load` hands back the script object only because the script returns itself
// (see ciArchiveReports.groovy).
return this
