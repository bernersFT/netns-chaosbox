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

                    cat semgrep-results.json |
                    docker run --rm -i python:3.13-alpine \
                    python3 -c '
        import json
        import sys

        report = json.load(sys.stdin)

        results = report.get("results", [])
        scan_errors = report.get("errors", [])

        severity_counts = {
            "ERROR": 0,
            "WARNING": 0,
            "INFO": 0,
            "UNKNOWN": 0,
        }

        affected_files = set()

        for finding in results:
            severity = (
                finding.get("extra", {})
                .get("severity", "UNKNOWN")
                .upper()
            )

            if severity not in severity_counts:
                severity = "UNKNOWN"

            severity_counts[severity] += 1

            path = finding.get("path")
            if path:
                affected_files.add(path)

        print("")
        print("===== Semgrep Summary =====")
        print(f"ERROR:          {severity_counts['ERROR']}")
        print(f"WARNING:        {severity_counts['WARNING']}")
        print(f"INFO:           {severity_counts['INFO']}")
        print(f"UNKNOWN:        {severity_counts['UNKNOWN']}")
        print(f"TOTAL:          {len(results)}")
        print(f"FILES AFFECTED: {len(affected_files)}")
        print(f"SCAN WARNINGS:  {len(scan_errors)}")
        print("")

        if affected_files:
            print("===== Affected Files =====")
            for path in sorted(affected_files):
                print(path)
            print("")

        if results:
            print("===== Findings =====")

            for index, finding in enumerate(results, start=1):
                extra = finding.get("extra", {})
                start = finding.get("start", {})

                severity = extra.get("severity", "UNKNOWN")
                path = finding.get("path", "unknown")
                line = start.get("line", "?")
                rule = finding.get("check_id", "unknown")
                message = extra.get("message", "").replace("\\n", " ")

                print(
                    f"{index}. [{severity}] "
                    f"{path}:{line} "
                    f"{rule}"
                )
                print(f"   {message}")

            print("")

        if severity_counts["ERROR"] > 0:
            print(
                "SECURITY GATE FAILED: "
                "Semgrep ERROR findings detected."
            )
            sys.exit(1)

        print("SECURITY GATE PASSED")
        '
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
