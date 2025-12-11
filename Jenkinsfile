pipeline {
    agent any

    environment {
        TF_VAR_key_name = 'firstserver'
        ANSIBLE_HOST_KEY_CHECKING = 'false'
        SSH_KEY_PATH = '/tmp/jenkins-aws-key.pem'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                dir('terraform') {
                    withCredentials([aws(
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY',
                        credentialsId: 'aws-access-key'
                    )]) {
                        sh '''
                            export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
                            export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

                            terraform init -input=false
                            terraform validate
                            terraform plan -out=tfplan -input=false
                            terraform apply -input=false -auto-approve
                        '''
                    }
                }
            }
        }

        stage('Prepare SSH Key') {
            steps {
                script {
                    // Extract SSH key from Jenkins credentials
                    withCredentials([sshUserPrivateKey(
                        credentialsId: 'firstserver-key',
                        keyFileVariable: 'JENKINS_SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )]) {
                        sh """
                            echo "Preparing SSH key for Ansible..."
                            # Copy the key to a known location
                            cp '$JENKINS_SSH_KEY' $SSH_KEY_PATH
                            chmod 600 $SSH_KEY_PATH
                            
                            echo "SSH key prepared at: $SSH_KEY_PATH"
                            echo "Testing key format..."
                            ssh-keygen -l -f $SSH_KEY_PATH || echo "Key format check failed, but continuing..."
                        """
                    }
                }
            }
        }

        stage('Generate Dynamic Inventory') {
            steps {
                script {
                    env.FRONTEND_IP = sh(returnStdout: true, script: "cd terraform && terraform output -raw frontend_public_ip").trim()
                    env.BACKEND_IP  = sh(returnStdout: true, script: "cd terraform && terraform output -raw backend_public_ip").trim()
                    
                    echo "Frontend IP: ${env.FRONTEND_IP}"
                    echo "Backend IP: ${env.BACKEND_IP}"
                }

                writeFile file: 'ansible/inventory.ini', text: """
[frontend]
frontend ansible_host=${env.FRONTEND_IP} ansible_user=ec2-user ansible_ssh_private_key_file=${env.SSH_KEY_PATH}

[backend]
backend ansible_host=${env.BACKEND_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${env.SSH_KEY_PATH}
"""
                echo "Inventory generated successfully:"
                sh "cat ansible/inventory.ini"
            }
        }

        stage('Test SSH Connectivity') {
            steps {
                sh """
                    echo "=== Testing SSH Connectivity ==="
                    echo "1. Testing frontend (ec2-user@${env.FRONTEND_IP})..."
                    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i $SSH_KEY_PATH ec2-user@${env.FRONTEND_IP} "echo 'Frontend SSH successful'" || echo "Frontend SSH failed"
                    
                    echo ""
                    echo "2. Testing backend (ubuntu@${env.BACKEND_IP})..."
                    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i $SSH_KEY_PATH ubuntu@${env.BACKEND_IP} "echo 'Backend SSH successful'" || echo "Backend SSH failed"
                    
                    echo ""
                    echo "3. SSH key info:"
                    ls -la $SSH_KEY_PATH
                """
            }
        }

        stage('Run Ansible - Frontend') {
            steps {
                sh """
                    echo "=== Running Ansible on Frontend ==="
                    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
                        amazon-playbook.yml \
                        -i ansible/inventory.ini \
                        --private-key=$SSH_KEY_PATH \
                        -u ec2-user \
                        -b \
                        --become-user=root \
                        --limit frontend
                """
            }
        }

        stage('Run Ansible - Backend') {
            steps {
                sh """
                    echo "=== Running Ansible on Backend ==="
                    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
                        ubuntu-playbook.yml \
                        -i ansible/inventory.ini \
                        --private-key=$SSH_KEY_PATH \
                        -u ubuntu \
                        -b \
                        --become-user=root \
                        --limit backend
                """
            }
        }

        stage('Post-checks') {
            steps {
                script {
                    echo "=== Post-deployment checks ==="
                    echo "Frontend URL → http://${env.FRONTEND_IP}"
                    echo "Backend (Netdata) URL → http://${env.BACKEND_IP}:19999"

                    sh "curl -m 5 -I http://${env.FRONTEND_IP} || echo 'Frontend curl failed'"
                    sh "sleep 5 && curl -m 5 -I http://${env.BACKEND_IP}:19999 || echo 'Backend curl failed'"
                }
            }
        }
    }

    post {
        always {
            // Clean up the SSH key
            sh "rm -f $SSH_KEY_PATH || true"
            echo "Pipeline completed"
        }
    }
}