pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
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
                    echo "Branch information:"
                    git branch -a
                    echo "Repository files:"
                    find . -maxdepth 2 -type f | sort
                '''
            }
        }

        stage('Semgrep Scan') {
            steps {
                echo '===== Start Semgrep source scan ====='

                sh '''
                    set -eu

                    tar \
                      --exclude='.git' \
                      --exclude='semgrep-results.json' \
                      -czf - . |
                    docker run --rm -i semgrep/semgrep sh -c '
                      set -eu

                      mkdir -p /src
                      tar -xzf - -C /src
                      cd /src

                      echo "===== Semgrep version ====="
                      semgrep --version

                      echo "===== Scanning source code ====="
                      semgrep scan \
                        --config auto \
                        .
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
            echo '===== Pipeline finished ====='
        }
    }
}