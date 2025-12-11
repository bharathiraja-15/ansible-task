pipeline {
    agent any

    environment {
        TF_VAR_key_name = 'firstserver'
    }

    tools {
        terraform 'terraform'   // Jenkins → Global Tool Config → Terraform
        ansible 'ansible'       // Jenkins → Global Tool Config → Ansible
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
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-access-key']]) {
                        sh '''
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
frontend ansible_host=${FRONTEND_IP} ansible_user=ec2-user

[backend]
backend ansible_host=${BACKEND_IP} ansible_user=ubuntu
"""
                echo "Inventory file created:"
                sh "cat ansible/inventory.ini"
            }
        }

        stage('Run Ansible - Frontend') {
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/frontend.yml',
                    inventory: 'ansible/inventory.ini',
                    credentialsId: 'jenkins-key',
                    disableHostKeyChecking: true,
                    installation: 'ansible',
                    become: true
                )
            }
        }

        stage('Run Ansible - Backend') {
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/backend.yml',
                    inventory: 'ansible/inventory.ini',
                    credentialsId: 'jenkins-key',
                    disableHostKeyChecking: true,
                    installation: 'ansible',
                    become: true
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
