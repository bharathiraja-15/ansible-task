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

        stage('Force Recreate Instances') {
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
                            
                            echo "=== Destroying old instances ==="
                            terraform destroy -auto-approve || true
                            
                            echo "=== Initializing Terraform ==="
                            terraform init -input=false
                            
                            echo "=== Creating new instances with correct key ==="
                            terraform apply -input=false -auto-approve
                        '''
                    }
                }
            }
        }

        stage('Prepare SSH Key') {
            steps {
                script {
                    withCredentials([sshUserPrivateKey(
                        credentialsId: 'firstserver-key',
                        keyFileVariable: 'JENKINS_SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )]) {
                        sh """
                            echo "=== Preparing SSH Key ==="
                            cp '$JENKINS_SSH_KEY' $SSH_KEY_PATH
                            chmod 600 $SSH_KEY_PATH
                            
                            echo "SSH Key Fingerprint:"
                            ssh-keygen -l -f $SSH_KEY_PATH || echo "Could not read key fingerprint"
                        """
                    }
                }
            }
        }

        stage('Get Instance IPs') {
            steps {
                script {
                    env.FRONTEND_IP = sh(returnStdout: true, script: "cd terraform && terraform output -raw frontend_public_ip 2>/dev/null || echo 'NOT_FOUND'").trim()
                    env.BACKEND_IP  = sh(returnStdout: true, script: "cd terraform && terraform output -raw backend_public_ip 2>/dev/null || echo 'NOT_FOUND'").trim()
                    
                    echo "Frontend IP: ${env.FRONTEND_IP}"
                    echo "Backend IP: ${env.BACKEND_IP}"
                    
                    if (env.FRONTEND_IP == 'NOT_FOUND' || env.BACKEND_IP == 'NOT_FOUND') {
                        error("Could not get instance IPs. Check Terraform outputs.")
                    }
                }
            }
        }

        stage('Create Inventory') {
            steps {
                writeFile file: 'ansible/inventory.ini', text: """
[frontend]
${env.FRONTEND_IP} ansible_user=ec2-user ansible_ssh_private_key_file=${env.SSH_KEY_PATH}

[backend]
${env.BACKEND_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${env.SSH_KEY_PATH}
"""
                echo "=== Inventory Created ==="
                sh "cat ansible/inventory.ini"
            }
        }

        stage('Test SSH Connections') {
            steps {
                sh """
                    echo "=== Testing SSH Connections ==="
                    
                    echo "1. Testing Frontend (ec2-user@${env.FRONTEND_IP})..."
                    timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i $SSH_KEY_PATH ec2-user@${env.FRONTEND_IP} "echo 'Frontend SSH Success - Hostname: \$(hostname)'" && echo "✓ Frontend SSH OK" || echo "✗ Frontend SSH Failed"
                    
                    echo ""
                    echo "2. Testing Backend (ubuntu@${env.BACKEND_IP})..."
                    timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i $SSH_KEY_PATH ubuntu@${env.BACKEND_IP} "echo 'Backend SSH Success - Hostname: \$(hostname)'" && echo "✓ Backend SSH OK" || echo "✗ Backend SSH Failed"
                    
                    echo ""
                    echo "3. Testing with Ansible ping..."
                    ANSIBLE_HOST_KEY_CHECKING=False ansible all -i ansible/inventory.ini -m ping --private-key=$SSH_KEY_PATH || echo "Ansible ping failed"
                """
            }
        }

        stage('Configure Frontend Server') {
            steps {
                sh """
                    echo "=== Configuring Frontend Server ==="
                    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
                        amazon-playbook.yml \
                        -i ansible/inventory.ini \
                        --private-key=$SSH_KEY_PATH \
                        -u ec2-user \
                        -b \
                        --become-user=root \
                        -v
                """
            }
        }

        stage('Configure Backend Server') {
            steps {
                sh """
                    echo "=== Configuring Backend Server ==="
                    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
                        ubuntu-playbook.yml \
                        -i ansible/inventory.ini \
                        --private-key=$SSH_KEY_PATH \
                        -u ubuntu \
                        -b \
                        --become-user=root \
                        -v
                """
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    echo "=== Verifying Deployment ==="
                    
                    echo "1. Checking Frontend Nginx..."
                    curl -s -o /dev/null -w "Frontend HTTP Status: %{http_code}\n" http://${env.FRONTEND_IP} || echo "Frontend not accessible"
                    
                    echo ""
                    echo "2. Checking Backend Netdata..."
                    curl -s -o /dev/null -w "Backend HTTP Status: %{http_code}\n" http://${env.BACKEND_IP}:19999 || echo "Backend not accessible"
                    
                    echo ""
                    echo "3. Final Status:"
                    echo "   Frontend URL: http://${env.FRONTEND_IP}"
                    echo "   Backend URL: http://${env.BACKEND_IP}:19999"
                """
            }
        }
    }

    post {
        always {
            sh """
                echo "=== Cleaning up ==="
                rm -f $SSH_KEY_PATH || true
                echo "SSH key removed"
            """
            echo "=== Pipeline Completed ==="
        }
        success {
            echo "✅ Pipeline SUCCESS!"
            sh """
                echo "=== Summary ==="
                echo "Frontend is ready at: http://${env.FRONTEND_IP}"
                echo "Backend monitoring at: http://${env.BACKEND_IP}:19999"
            """
        }
        failure {
            echo "❌ Pipeline FAILED!"
            sh """
                echo "=== Debug Information ==="
                echo "Check Terraform state:"
                cd terraform && terraform show || true
                echo ""
                echo "Last 50 lines of logs:"
                tail -50 /var/lib/jenkins/workspace/${JOB_NAME}/log || true
            """
        }
    }
}