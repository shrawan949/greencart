```groovy
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
        SONAR_PROJECT_KEY = 'greencart'
        PATH              = "/usr/bin:/usr/local/bin:${env.PATH}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -eu

                    test -f client/package.json
                    test -f client/Dockerfile
                    test -f server/package.json
                    test -f server/Dockerfile
                    test -d kubernetes

                    echo "GreenCart source files validated."
                '''
            }
        }

        stage('Build Frontend') {
            steps {
                dir('client') {
                    sh '''
                        set -eu
                        npm ci
                        npm run build
                    '''
                }
            }
        }

        stage('Check Backend') {
            steps {
                dir('server') {
                    sh '''
                        set -eu
                        npm ci

                        # Syntax-check the backend entry point.
                        if [ -f server.js ]; then
                            node --check server.js
                        elif [ -f index.js ]; then
                            node --check index.js
                        elif [ -f src/index.js ]; then
                            node --check src/index.js
                        else
                            echo "Backend entry point not found."
                            exit 1
                        fi

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
                                      -Dsonar.sources=client/src,server \
                                      -Dsonar.exclusions=**/node_modules/**,**/dist/**,**/coverage/** \
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
                      -t ${BACKEND_IMAGE}:${BUILD_NUMBER} \
                      server

                    docker build \
                      -t ${FRONTEND_IMAGE}:${BUILD_NUMBER} \
                      client

                    docker images
                '''
            }
        }

        stage('Push to Docker Hub') {
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

                        docker push ${BACKEND_IMAGE}:${BUILD_NUMBER}
                        docker push ${FRONTEND_IMAGE}:${BUILD_NUMBER}
                    '''
                }
            }
        }

        stage('Verify Kubernetes Connection') {
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

                        kubectl set image deployment/greencart-backend \
                          backend=${BACKEND_IMAGE}:${BUILD_NUMBER} \
                          -n "$K8S_NAMESPACE"

                        kubectl set image deployment/greencart-frontend \
                          frontend=${FRONTEND_IMAGE}:${BUILD_NUMBER} \
                          -n "$K8S_NAMESPACE"

                        kubectl rollout status deployment/greencart-backend \
                          -n "$K8S_NAMESPACE" --timeout=180s

                        kubectl rollout status deployment/greencart-frontend \
                          -n "$K8S_NAMESPACE" --timeout=180s

                        kubectl get deployments -n "$K8S_NAMESPACE"
                        kubectl get pods -n "$K8S_NAMESPACE" -o wide
                        kubectl get services -n "$K8S_NAMESPACE"

                        echo "GreenCart deployment completed successfully."
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: GreenCart build, SonarQube analysis, Docker push and Kubernetes deployment completed.'
        }

        failure {
            echo 'FAILED: Check Jenkins Console Output for the failing stage.'
        }

        always {
            echo "GreenCart pipeline build number: ${BUILD_NUMBER}"
        }
    }
}
```
