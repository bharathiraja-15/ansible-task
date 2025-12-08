pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                sh 'echo cloning repo'
                git branch: 'main', url: 'https://github.com/saivarun0509/ansible-task.git'
            }
        }

        stage('Terraform Apply') {
            steps {
                script {
                    dir("${WORKSPACE}") {
                        sh 'terraform init'
                        sh 'terraform validate'

                        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-creds']]) {
                            sh 'terraform plan'
                            sh 'terraform apply -auto-approve'
                        }
                    }
                }
            }
        }

        stage('Ansible Deployment') {
            steps {
                script {

                    // --- AMAZON LINUX (frontend) ---
                    ansiblePlaybook(
                        credentialsId: 'ec2-key',
                        disableHostKeyChecking: true,
                        installation: 'ansible',
                        inventory: 'inventory.yaml',
                        playbook: 'amazon-playbook.yml',
                        extraVars: [
                            ansible_user: "ec2-user"   // <-- Correct SSH user
                        ]
                    )

                    // --- UBUNTU (backend, only if needed) ---
                    ansiblePlaybook(
                        become: true,
                        credentialsId: 'ec2-key',
                        disableHostKeyChecking: true,
                        installation: 'ansible',
                        inventory: 'inventory.yaml',
                        playbook: 'ubuntu-playbook.yml',
                        extraVars: [
                            ansible_user: "ubuntu"     // <-- Ubuntu default user
                        ]
                    )
                }
            }
        }
    }
}
