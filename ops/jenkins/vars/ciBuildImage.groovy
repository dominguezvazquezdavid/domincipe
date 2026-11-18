// Build one image with the rootless BuildKit of the CI stack (design D3, task
// 5.1; first used by task 6.1).
//
// One buildctl call writes one OCI archive with both references, so the sha tag
// and latest cannot diverge between two outputs. No Docker daemon and no Docker
// socket are involved: buildctl talks to buildkitd over the shared Unix socket.
//
// args:
//   image      image name without the prefix (auth-service, web-frontend, ...)
//   dockerfile Dockerfile under ops/docker (java-service.Dockerfile, ...)
//   sha        commit sha; also exported as the GIT_SHA build arg
//   buildArgs  extra build-arg entries (MODULE, VITE_API_BASE_URL, ...)
//   prefix     image prefix, domincipe by default

def call(Map args) {
    def image = args.image?.trim()
    def dockerfile = args.dockerfile?.trim()
    def sha = args.sha?.trim()
    def prefix = args.prefix?.trim() ?: 'domincipe'

    [image: image, dockerfile: dockerfile, sha: sha].each { name, value ->
        if (!value) {
            error "ciBuildImage: '${name}' is required"
        }
    }

    // GIT_SHA is common to the seven images, so the caller does not repeat it.
    Map buildArgs = [GIT_SHA: sha] + (args.buildArgs ?: [:])
    def buildArgOpts = buildArgs.collect { name, value ->
        "--opt build-arg:${name}=${value}"
    }.join(' ')

    def addr = env.BUILDKIT_HOST ?: 'unix:///run/user/1000/buildkit/buildkitd.sock'

    // The name field is a CSV list inside the OCI output option, so the double
    // quotes have to survive the shell: the whole option travels single quoted.
    def output = "type=oci,dest=/out/${image}.tar," +
                 "\"name=${prefix}/${image}:${sha},${prefix}/${image}:latest\""

    sh """
        buildctl --addr '${addr}' build \\
          --frontend dockerfile.v0 \\
          --local context=. --local dockerfile=ops/docker \\
          --opt filename='${dockerfile}' ${buildArgOpts} \\
          --import-cache type=local,src=/cache \\
          --export-cache type=local,dest=/cache,mode=max \\
          --output '${output}'
    """
}

// `load` hands back the script object only because the script returns itself
// (see ciArchiveReports.groovy).
return this
