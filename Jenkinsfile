pipeline {
    agent none

    environment {
        JFROG_URL      = 'http://20.219.37.20:8082/artifactory'
        JFROG_REPO     = 'amazon-generic-local'
        // FIXED: added FULL_IMAGE so deployment.yaml sed works
        // JFrog Docker repo must be type=Docker (or use generic tar pull below)
        IMAGE_NAME     = 'amazon-app'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        TAR_FILE       = "${IMAGE_NAME}-${IMAGE_TAG}.tar"
        FULL_IMAGE     = "20.219.37.20:8082/amazon-docker-local/${IMAGE_NAME}:${IMAGE_TAG}"
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
        // STAGE 2: Push to JFrog
        // — tar to Generic repo (audit/archive copy)
        // — also push to Docker repo (so AKS can pull it)
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
                        echo "=== Saving Docker image as tar (generic archive) ==="
                        docker save ${IMAGE_NAME}:${IMAGE_TAG} -o ${TAR_FILE}
                        ls -lh ${TAR_FILE}

                        echo "=== Uploading tar to JFrog Generic Repository ==="
                        curl -u ${JFROG_USER}:${JFROG_PASS} \
                            -X PUT \
                            "${JFROG_URL}/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}" \
                            -T ${TAR_FILE} \
                            --progress-bar \
                            -w "\\nHTTP Status: %{http_code}\\n"

                        echo "=== Verifying tar upload ==="
                        curl -u ${JFROG_USER}:${JFROG_PASS} \
                            "${JFROG_URL}/api/storage/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}" \
                            | python3 -m json.tool

                        echo "=== Pushing image to JFrog Docker Repository (for AKS pull) ==="
                        docker login 20.219.37.20:8082 \
                            -u ${JFROG_USER} -p ${JFROG_PASS}
                        docker tag  ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE}
                        docker push ${FULL_IMAGE}

                        echo "=== Cleaning up local files ==="
                        rm -f ${TAR_FILE}
                        docker rmi ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE} || true

                        echo "=== Artifact URL ==="
                        echo "${JFROG_URL}/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}"
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
                            echo "=== Substituting image in deployment.yaml ==="
                            sed -i 's|DOCKER_IMAGE_PLACEHOLDER|${FULL_IMAGE}|g' k8s/deployment.yaml

                            echo "=== Verifying substitution ==="
                            grep 'image:' k8s/deployment.yaml

                            echo "=== Applying manifests ==="
                            kubectl apply -f k8s/namespace.yaml
                            kubectl apply -f k8s/configmap.yaml  -n ${K8S_NAMESPACE}
                            kubectl apply -f k8s/deployment.yaml -n ${K8S_NAMESPACE}
                            kubectl apply -f k8s/service.yaml    -n ${K8S_NAMESPACE}
                            kubectl apply -f k8s/ingress.yaml    -n ${K8S_NAMESPACE}
                            kubectl apply -f k8s/hpa.yaml        -n ${K8S_NAMESPACE}

                            echo "=== Waiting for rollout ==="
                            kubectl rollout status deployment/amazon-deployment \
                                -n ${K8S_NAMESPACE} --timeout=180s
                        """
                    }
                }
            }
        }

        // ──────────────────────────────────────────────
        // STAGE 4: Confirm deployment then destroy k8s pod
        // (pod auto-destroys when stage ends — this just logs state)
        // ──────────────────────────────────────────────
        stage('Confirm & Cleanup') {
            agent { label 'azure-vm' }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-aks', variable: 'KUBECONFIG')]) {
                    sh """
                        echo "=== Deployed pods ==="
                        kubectl get pods -n ${K8S_NAMESPACE}
                        echo "=== Services ==="
                        kubectl get svc  -n ${K8S_NAMESPACE}
                        echo "=== Ingress ==="
                        kubectl get ingress -n ${K8S_NAMESPACE}
                        echo "=== HPA ==="
                        kubectl get hpa -n ${K8S_NAMESPACE}
                    """
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    // POST: Email notifications
    // ──────────────────────────────────────────────
    post {
        success {
            mail(
                to: 'build.chidambar@gmail.com',
                subject: "✅ [SUCCESS] Amazon App - Build #${env.BUILD_NUMBER}",
                body: """\
Build Status:  SUCCESS
Job:           ${env.JOB_NAME}
Build Number:  #${env.BUILD_NUMBER}
Branch:        ${env.GIT_BRANCH}
Image:         ${env.FULL_IMAGE}
Artifact:      ${env.JFROG_URL}/${env.JFROG_REPO}/${env.IMAGE_NAME}/${env.IMAGE_NAME}-${env.IMAGE_TAG}.tar
Duration:      ${currentBuild.durationString}

View build:    ${env.BUILD_URL}
"""
            )
        }
        failure {
            mail(
                to: 'build.chidambar@gmail.com',
                subject: "❌ [FAILED] Amazon App - Build #${env.BUILD_NUMBER}",
                body: """\
Build Status:  FAILED
Job:           ${env.JOB_NAME}
Build Number:  #${env.BUILD_NUMBER}
Branch:        ${env.GIT_BRANCH}
Failed Stage:  ${env.STAGE_NAME}

View logs:     ${env.BUILD_URL}console
"""
            )
        }
        always {
            mail(
                to: 'build.chidambar@gmail.com',
                subject: "[CI] Amazon App Build #${env.BUILD_NUMBER} - ${currentBuild.currentResult}",
                body: """\
Build #${env.BUILD_NUMBER} finished — ${currentBuild.currentResult}

Job:      ${env.JOB_NAME}
Branch:   ${env.GIT_BRANCH}
Duration: ${currentBuild.durationString}

${env.BUILD_URL}
"""
            )
        }
    }
}
