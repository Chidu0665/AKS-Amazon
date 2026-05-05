pipeline {
    agent none

    environment {
        JFROG_URL      = 'http://20.219.37.20:8082/artifactory'
        JFROG_REPO     = 'amazon-generic-local'
        IMAGE_NAME     = 'amazon-app'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        TAR_FILE       = "${IMAGE_NAME}-${IMAGE_TAG}.tar"
        K8S_NAMESPACE  = 'amazon'
    }

    stages {

        // ──────────────────────────────────────────────
        // STAGE 1: Build Docker image on macOS Docker slave
        // ──────────────────────────────────────────────
        stage('Build Docker Image') {
            agent { label 'macos-docker' }
            steps {
                checkout scm
                script {
                    docker.build("${IMAGE_NAME}:${IMAGE_TAG}", '-f Dockerfile .')
                }
            }
        }

        // ──────────────────────────────────────────────
        // STAGE 2: Push to JFrog Generic Repository as tar
        // ──────────────────────────────────────────────
        stage('Push to JFrog') {
            agent { label 'macos-docker' }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'jfrog-creds',
                    usernameVariable: 'JFROG_USER',
                    passwordVariable: 'JFROG_PASS'
                )]) {
                    sh """
                        echo "=== Saving Docker image as tar ==="
                        docker save ${IMAGE_NAME}:${IMAGE_TAG} -o ${TAR_FILE}

                        echo "=== Verifying tar file ==="
                        ls -lh ${TAR_FILE}

                        echo "=== Uploading to JFrog Generic Repository ==="
                        curl -u ${JFROG_USER}:${JFROG_PASS} \
                            -X PUT \
                            "${JFROG_URL}/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}" \
                            -T ${TAR_FILE} \
                            --progress-bar \
                            -w "\\nHTTP Status: %{http_code}\\n"

                        echo "=== Verifying upload in JFrog ==="
                        curl -u ${JFROG_USER}:${JFROG_PASS} \
                            -X GET \
                            "${JFROG_URL}/api/storage/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}" \
                            | python3 -m json.tool

                        echo "=== Cleaning up local tar file ==="
                        rm -f ${TAR_FILE}

                        echo "=== Upload complete ==="
                        echo "Artifact URL: ${JFROG_URL}/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}"
                    """
                }
            }
        }

        // ──────────────────────────────────────────────
        // STAGE 3: Deploy to AKS via Kubernetes plugin pod
        // ──────────────────────────────────────────────
        stage('Deploy to AKS') {
            agent {
                kubernetes {
                    label 'k8s-deploy-pod'
                    yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: kubectl
    image: bitnami/kubectl:latest
    command: ['cat']
    tty: true
"""
                }
            }
            steps {
                container('kubectl') {
                    withCredentials([file(credentialsId: 'kubeconfig-aks', variable: 'KUBECONFIG')]) {
                        sh """
                            kubectl apply -f k8s/namespace.yaml
                            kubectl apply -f k8s/configmap.yaml
                            kubectl apply -f k8s/deployment.yaml -n ${K8S_NAMESPACE}
                            kubectl apply -f k8s/service.yaml    -n ${K8S_NAMESPACE}
                            kubectl apply -f k8s/ingress.yaml    -n ${K8S_NAMESPACE}
                            kubectl apply -f k8s/hpa.yaml        -n ${K8S_NAMESPACE}

                            kubectl rollout status deployment/amazon-deployment \
                                -n ${K8S_NAMESPACE} --timeout=120s
                        """
                    }
                }
            }
        }

        // ──────────────────────────────────────────────
        // STAGE 4: Confirm deployment
        // ──────────────────────────────────────────────
        stage('Confirm & Cleanup') {
            agent { label 'azure-vm kubectl' }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-aks', variable: 'KUBECONFIG')]) {
                    sh """
                        echo "=== Deployed pods ==="
                        kubectl get pods -n ${K8S_NAMESPACE}
                        echo "=== Services ==="
                        kubectl get svc  -n ${K8S_NAMESPACE}
                        echo "=== Ingress ==="
                        kubectl get ingress -n ${K8S_NAMESPACE}
                    """
                }
            }
        }
    }

    post {
        success {
            mail(
                to: 'build.chidambar@gmail.com',
                subject: "✅ [SUCCESS] Amazon App - Build #${env.BUILD_NUMBER}",
                body: """
Build Status:  SUCCESS
Job:           ${env.JOB_NAME}
Build Number:  #${env.BUILD_NUMBER}
Branch:        ${env.GIT_BRANCH}
Artifact:      ${env.JFROG_URL}/${env.JFROG_REPO}/${env.IMAGE_NAME}/${env.IMAGE_NAME}-${env.IMAGE_TAG}.tar
Duration:      ${currentBuild.durationString}

View build: ${env.BUILD_URL}
"""
            )
        }
        failure {
            mail(
                to: 'build.chidambar@gmail.com',
                subject: "❌ [FAILED] Amazon App - Build #${env.BUILD_NUMBER}",
                body: """
Build Status:  FAILED
Job:           ${env.JOB_NAME}
Build Number:  #${env.BUILD_NUMBER}
Branch:        ${env.GIT_BRANCH}
Failed Stage:  ${env.STAGE_NAME}

View logs: ${env.BUILD_URL}console
"""
            )
        }
        always {
            mail(
                to: 'build.chidambar@gmail.com',
                subject: "[CI] Amazon App Build #${env.BUILD_NUMBER} - ${currentBuild.currentResult}",
                body: """
Build #${env.BUILD_NUMBER} completed with status: ${currentBuild.currentResult}

Job:      ${env.JOB_NAME}
Branch:   ${env.GIT_BRANCH}
Duration: ${currentBuild.durationString}

${env.BUILD_URL}
"""
            )
        }
    }
}
