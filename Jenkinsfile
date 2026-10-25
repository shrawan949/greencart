
pipeline {
    agent any

    options {
        timestamps()
        skipDefaultCheckout(true)
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    environment {
        BACKEND_IMAGE     = 'shrawanambarte0101/greencart-backend'
        FRONTEND_IMAGE    = 'shrawanambarte0101/greencart-frontend'
        K8S_NAMESPACE     = 'greencart'
        BACKEND_DEPLOYMENT = 'greencart-backend'
        FRONTEND_DEPLOYMENT = 'greencart-frontend'
        SONAR_PROJECT_KEY = 'greencart'
        BACKEND_DIR       = 'server'
        FRONTEND_DIR      = 'client'
        PATH              = "/usr/bin:/usr/local/bin:${env.PATH}"
    }

    stages {
        stage('Checkout and Validate') {
            steps {
                checkout scm

                sh '''
                    set -eu

                    test -f "${BACKEND_DIR}/package.json"
                    test -f "${BACKEND_DIR}/Dockerfile"
                    test -f "${FRONTEND_DIR}/package.json"
                    test -f "${FRONTEND_DIR}/Dockerfile"

                    echo "GreenCart source files validated."
                '''
            }
        }

        stage('Build Frontend') {
            steps {
                dir("${FRONTEND_DIR}") {
                    sh '''
                        set -eu
                        if [ -f package-lock.json ]; then
                            npm ci
                        else
                            npm install
                        fi
                        npm run build
                    '''
                }
            }
        }

        stage('Check Backend') {
            steps {
                dir("${BACKEND_DIR}") {
                    sh '''
                        set -eu

                        if [ -f package-lock.json ]; then
                            npm ci
                        else
                            npm install
                        fi

                        node --check server.js
                        npm run test --if-present
                    '''
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                script {
                    def scannerHome = tool 'SonarQube-01'

                    withSonarQubeEnv('SonarQube') {
                        withCredentials([
                            string(
                                credentialsId: 'sonar-token',
                                variable: 'SONAR_TOKEN'
                            )
                        ]) {
                            withEnv([
                                "SONAR_SCANNER=${scannerHome}/bin/sonar-scanner"
                            ]) {
                                sh '''
                                    set -eu

                                    "$SONAR_SCANNER" \
                                      -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
                                      -Dsonar.projectName=GreenCart \
                                      -Dsonar.sources=server,client/src \
                                      -Dsonar.exclusions=**/node_modules/**,**/dist/** \
                                      -Dsonar.sourceEncoding=UTF-8 \
                                      -Dsonar.token="$SONAR_TOKEN"
                                '''
                            }
                        }
                    }
                }
            }
        }

        stage('Build Docker Images') {
            steps {
                sh '''
                    set -eu

                    docker build \
                      -t "${BACKEND_IMAGE}:${BUILD_NUMBER}" \
                      "${BACKEND_DIR}"

                    docker build \
                      -t "${FRONTEND_IMAGE}:${BUILD_NUMBER}" \
                      "${FRONTEND_DIR}"

                    docker images
                '''
            }
        }

        stage('Push Images to Docker Hub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    sh '''
                        set -eu
                        trap 'docker logout >/dev/null 2>&1 || true' EXIT

                        echo "$DOCKER_PASSWORD" | docker login \
                          --username "$DOCKER_USER" \
                          --password-stdin

                        docker push "${BACKEND_IMAGE}:${BUILD_NUMBER}"
                        docker push "${FRONTEND_IMAGE}:${BUILD_NUMBER}"
                    '''
                }
            }
        }

        stage('Verify Kubernetes') {
            steps {
                withCredentials([
                    file(
                        credentialsId: 'kubeconfig-admin',
                        variable: 'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -eu
                        export KUBECONFIG="$KUBECONFIG_FILE"

                        kubectl get nodes
                        kubectl get namespace "$K8S_NAMESPACE"
                        kubectl get deployments -n "$K8S_NAMESPACE"
                        kubectl get pods -n "$K8S_NAMESPACE"
                        kubectl get services -n "$K8S_NAMESPACE"
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([
                    file(
                        credentialsId: 'kubeconfig-admin',
                        variable: 'KUBECONFIG_FILE'
                    )
                ]) {
                    sh '''
                        set -eu
                        export KUBECONFIG="$KUBECONFIG_FILE"

                        kubectl set image \
                          deployment/"$BACKEND_DEPLOYMENT" \
                          backend="${BACKEND_IMAGE}:${BUILD_NUMBER}" \
                          -n "$K8S_NAMESPACE"

                        kubectl set image \
                          deployment/"$FRONTEND_DEPLOYMENT" \
                          frontend="${FRONTEND_IMAGE}:${BUILD_NUMBER}" \
                          -n "$K8S_NAMESPACE"

                        kubectl rollout status \
                          deployment/"$BACKEND_DEPLOYMENT" \
                          -n "$K8S_NAMESPACE" --timeout=180s

                        kubectl rollout status \
                          deployment/"$FRONTEND_DEPLOYMENT" \
                          -n "$K8S_NAMESPACE" --timeout=180s

                        kubectl get deployments -n "$K8S_NAMESPACE"
                        kubectl get pods -n "$K8S_NAMESPACE" -o wide
                        kubectl get services -n "$K8S_NAMESPACE"

                        echo "GreenCart deployment completed."
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: GreenCart built, scanned, pushed and deployed.'
        }

        failure {
            echo 'FAILED: Check Jenkins Console Output for the failing stage.'
        }

        always {
            echo "GreenCart pipeline build: ${BUILD_NUMBER}"
        }
    }
}

