pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(
            numToKeepStr: '30',
            artifactNumToKeepStr: '30'
        ))
    }

    stages {
        stage('Checkout') {
            steps {
                echo '===== Checkout source code ====='

                checkout scm

                sh '''
                    set -eu

                    echo "Workspace: $(pwd)"
                    echo "Commit: $(git rev-parse HEAD)"
                    echo "Latest commit:"
                    git log -1 --oneline
                '''
            }
        }

        stage('Prepare Scan') {
            steps {
                echo '===== Prepare Semgrep container ====='

                sh '''
                    set -eu

                    rm -f semgrep-container.id
                    rm -f semgrep-results.json

                    CONTAINER_ID="$(
                        docker create \
                          --interactive \
                          semgrep/semgrep \
                          sh -c 'sleep 3600'
                    )"

                    echo "${CONTAINER_ID}" > semgrep-container.id

                    echo "Semgrep container: ${CONTAINER_ID}"

                    docker start "${CONTAINER_ID}"

                    docker exec "${CONTAINER_ID}" \
                      mkdir -p /src

                    tar \
                      --exclude='.git' \
                      --exclude='semgrep-container.id' \
                      --exclude='semgrep-results.json' \
                      -czf - . |
                    docker exec -i "${CONTAINER_ID}" \
                      tar -xzf - -C /src

                    echo "===== Files copied into scanner ====="

                    docker exec "${CONTAINER_ID}" \
                      sh -c '
                        cd /src
                        find . -maxdepth 3 -type f | sort
                      '
                '''
            }
        }

        stage('Semgrep Scan') {
            steps {
                echo '===== Start Semgrep source scan ====='

                sh '''
                    set -eu

                    CONTAINER_ID="$(cat semgrep-container.id)"

                    echo "===== Semgrep version ====="

                    docker exec "${CONTAINER_ID}" \
                      semgrep --version

                    echo "===== Human-readable scan ====="

                    docker exec \
                      --workdir /src \
                      "${CONTAINER_ID}" \
                      semgrep scan \
                        --config auto \
                        .

                    echo "===== Generate JSON report ====="

                    docker exec \
                      --workdir /src \
                      "${CONTAINER_ID}" \
                      semgrep scan \
                        --config auto \
                        --json \
                        --output semgrep-results.json \
                        .

                    echo "===== Copy JSON report to Jenkins ====="

                    docker cp \
                      "${CONTAINER_ID}:/src/semgrep-results.json" \
                      "./semgrep-results.json"

                    echo "===== Report information ====="

                    ls -lh semgrep-results.json
                    test -s semgrep-results.json
                '''
            }
        }
        stage('Evaluate Findings') {
            steps {
                echo '===== Evaluate Semgrep findings ====='

                sh '''
                    set -eu

                    test -s semgrep-results.json

                    echo "===== Semgrep Summary ====="

                    TOTAL="$(
                        docker run --rm -i \
                        ghcr.io/jqlang/jq:latest \
                        '.results | length' \
                        < semgrep-results.json
                    )"

                    ERROR_COUNT="$(
                        docker run --rm -i \
                        ghcr.io/jqlang/jq:latest \
                        '[.results[] | select(.extra.severity == "ERROR")] | length' \
                        < semgrep-results.json
                    )"

                    WARNING_COUNT="$(
                        docker run --rm -i \
                        ghcr.io/jqlang/jq:latest \
                        '[.results[] | select(.extra.severity == "WARNING")] | length' \
                        < semgrep-results.json
                    )"

                    INFO_COUNT="$(
                        docker run --rm -i \
                        ghcr.io/jqlang/jq:latest \
                        '[.results[] | select(.extra.severity == "INFO")] | length' \
                        < semgrep-results.json
                    )"

                    AFFECTED_FILES="$(
                        docker run --rm -i \
                        ghcr.io/jqlang/jq:latest \
                        '[.results[].path] | unique | length' \
                        < semgrep-results.json
                    )"

                    SCAN_WARNINGS="$(
                        docker run --rm -i \
                        ghcr.io/jqlang/jq:latest \
                        '.errors | length' \
                        < semgrep-results.json
                    )"

                    echo "ERROR:          ${ERROR_COUNT}"
                    echo "WARNING:        ${WARNING_COUNT}"
                    echo "INFO:           ${INFO_COUNT}"
                    echo "TOTAL:          ${TOTAL}"
                    echo "FILES AFFECTED: ${AFFECTED_FILES}"
                    echo "SCAN WARNINGS:  ${SCAN_WARNINGS}"

                    echo ""
                    echo "===== Detailed Findings ====="

                    docker run --rm -i \
                    ghcr.io/jqlang/jq:latest \
                    -r '
                        .results[] |
                        "[\\(.extra.severity)] \\(.path):\\(.start.line)
        Rule: \\(.check_id)
        Message: \\(.extra.message)
        "
                    ' \
                    < semgrep-results.json

                    echo ""
                    echo "===== Security Gate ====="

                    if [ "${ERROR_COUNT}" -gt 0 ]; then
                        echo "SECURITY GATE FAILED"
                        echo "${ERROR_COUNT} ERROR-level finding(s) detected."
                        exit 1
                    fi

                    echo "SECURITY GATE PASSED"
                '''
            }
        }
    }

    post {
        success {
            echo '===== Pipeline completed successfully ====='
        }

        failure {
            echo '===== Pipeline failed ====='
        }

        always {
            echo '===== Archive Semgrep report ====='

            archiveArtifacts(
                artifacts: 'semgrep-results.json',
                fingerprint: true,
                allowEmptyArchive: true
            )

            echo '===== Clean temporary Semgrep container ====='

            sh '''
                if [ -f semgrep-container.id ]; then
                    CONTAINER_ID="$(cat semgrep-container.id)"

                    docker rm -f "${CONTAINER_ID}" \
                    >/dev/null 2>&1 || true

                    rm -f semgrep-container.id
                fi
            '''

            echo '===== Pipeline finished ====='
        }
    }
}
