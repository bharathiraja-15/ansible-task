pipeline {
    agent any

    environment {
        TF_VAR_key_name = 'firstserver'
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

        stage('Generate Dynamic Inventory') {
            steps {
                script {
                    env.FRONTEND_IP = sh(returnStdout: true, script: "cd terraform && terraform output -raw frontend_public_ip").trim()
                    env.BACKEND_IP  = sh(returnStdout: true, script: "cd terraform && terraform output -raw backend_public_ip").trim()
                }

                writeFile file: 'ansible/inventory.ini', text: """
[frontend]
frontend ansible_host=${env.FRONTEND_IP} ansible_user=ec2-user

[backend]
backend ansible_host=${env.BACKEND_IP} ansible_user=ubuntu
"""
                echo "Inventory generated successfully:"
                sh "cat ansible/inventory.ini"
            }
        }

        stage('Debug SSH Key') {
            steps {
                sh '''
                    echo "Listing workspace files:"
                    ls -l /var/lib/jenkins/workspace/${JOB_NAME}/ || true
                    ls -l /var/lib/jenkins/workspace/${JOB_NAME}/*.key || true
                '''
            }
        }

        stage('Run Ansible - Frontend') {
            steps {
                ansiblePlaybook(
                    playbook: 'amazon-playbook.yml',
                    inventory: 'ansible/inventory.ini',
                    credentialsId: 'firstserver',
                    disableHostKeyChecking: true,
                    become: true
                )
            }
        }

       stage('Run Ansible - Backend') {
    steps {
        ansiblePlaybook(
            playbook: 'ubuntu-playbook.yml',
            inventory: 'ansible/inventory.ini',
            credentialsId: 'firstserver-key',
            disableHostKeyChecking: true,
            become: true,
            extras: '-u ubuntu'
        )
    }
}

        stage('Post-checks') {
            steps {
                script {
                    echo "Frontend URL → http://${env.FRONTEND_IP}"
                    echo "Backend (Netdata) URL → http://${env.BACKEND_IP}:19999"

                    sh "curl -m 5 -I http://${env.FRONTEND_IP} || true"
                    sh "curl -m 5 -I http://${env.BACKEND_IP}:19999 || true"
                }
            }
        }
    }
}
