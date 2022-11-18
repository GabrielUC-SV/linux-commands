pipeline {
    options {
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '15'))
        timeout(time: 1, unit: 'HOURS')
    }
    agent { node { label 'docker' } }

    parameters {
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Boolean which indicates if the tests will be skipped')
        booleanParam(name: 'BUMP_MINOR_SNAPSHOT', defaultValue: false, description: 'Creates a new snapshot version by increases the minor value when is set to true (applies on develop only)')
    }

    environment {
        SLACK_CHANNEL                    = ''
        LAST_COMMIT_AUTHOR               = gitAuthor()
        ORIGIN_BRANCH_NAME               = "${env.BRANCH_NAME}"
    }

    stages {
        stage('Start pipeline') {
            when {
                beforeAgent true
                anyOf {
                    triggeredBy cause: 'UserIdCause'
                    expression { loadJsonEnv() { return LAST_COMMIT_AUTHOR != "${GIT_IGNORE_COMMITS_EMAIL}" } }
                }
            }
            stages {
                stage('Prepare environment') {
                    steps {
                        script {
                            if(env.CHANGE_BRANCH) {
                                ORIGIN_BRANCH_NAME = env.CHANGE_BRANCH
                            }
                        }
                    }
                }

                stage('Maven Execution') {
                    agent {
                        docker {
                            args "-v ${HOME}/.m2:${WORKSPACE}/.m2 -e MAVEN_CONFIG=${WORKSPACE}/.m2 -e MAVEN_OPTS='-Dmaven.repo.local=${WORKSPACE}/.m2/repository'"
                            image 'maven:3.6.3-jdk-11'
                            reuseNode true
                        }
                    }
                    stages {
                        stage('Bump') {
                            parallel {
                                stage('Build version') {
                                    when {
                                        allOf {
                                            branch 'develop'
                                            expression { return params.BUMP_MINOR_SNAPSHOT == false }
                                        }
                                    }
                                    steps {
                                        withMavenSettings() {
                                            mavenSemanticVersion(addGit: true)
                                        }
                                    }
                                }
                                stage('Minor version') {
                                    when {
                                        allOf {
                                            branch 'develop'
                                            expression { return params.BUMP_MINOR_SNAPSHOT == true }
                                        }
                                    }
                                    steps {
                                        withMavenSettings() {
                                            mavenSemanticVersion(addGit: true, buildType: "minor")
                                        }
                                    }
                                }
                                stage('Release version') {
                                    when { branch 'release/*' }
                                    steps {
                                        withMavenSettings() {
                                            mavenSemanticVersion(addGit: true, buildType: "build",
                                                releaseType: "release")
                                        }
                                    }
                                }
                                stage('Patch version') {
                                    when { branch 'hotfix/*' }
                                    steps {
                                        withMavenSettings() {
                                            mavenSemanticVersion(buildType: "patch",
                                                releaseType: "release", addGit: true)
                                        }
                                    }
                                }
                            }
                        }

                        stage('Maven') {
                            stages {
                                stage('Run tests') {
                                    when { expression { return params.SKIP_TESTS == false } }
                                    steps {
                                        withMavenSettings() {
                                            sh 'mvn test -U -B -P sanity'
                                        }
                                    }
                                }

                                stage('Maven Deploy') {
                                    when {
                                        anyOf {
                                            branch 'develop'
                                            branch 'hotfix/*'
                                            branch 'release/*'
                                            branch 'master'
                                        }
                                    }
                                    steps {
                                        withMavenSettings() {
                                            script {
                                                if (ORIGIN_BRANCH_NAME == "master") {
                                                    sh 'mvn package -U -B -DskipTests'
                                                } else {
                                                    sh 'mvn deploy -U -B -DskipTests'
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                stage('Docker Deploy'){
                    when {
                        anyOf {
                            branch 'develop'
                            branch 'release/*'
                            branch 'hotfix/*'
                            branch 'master'
                        }
                    }
                    steps {
                        loadJsonEnv() {
                            script {
                                VERSION_INFORMATION = mavenSemanticVersion("readOnly": true)
                                ARTIFACT_ID = VERSION_INFORMATION.artifactId
                                PROJECT_VERSION = VERSION_INFORMATION.version
                                SEMANTIC_VERSION = VERSION_INFORMATION.versionShort
                                JAR_FILE_NAME = "target/${ARTIFACT_ID}-${PROJECT_VERSION}.jar"
                                image = docker.build("${DOCKER_REGISTRY_URL}/${REPOSITORY_NAME}:${SEMANTIC_VERSION}${RELEASE_PREFIX}", "-f Dockerfile \
                                    --build-arg JAR_FILE='${JAR_FILE_NAME}' .")
                                docker.withRegistry("https://${DOCKER_REGISTRY_URL}", "${REGISTRY_CREDENTIALS_ID}") {
                                    image.push()
                                }
                            }
                        }
                    }
                }

                stage("Kubernetes Deploy") {
                    when {
                        beforeAgent true
                        anyOf {
                            branch 'develop'
                            branch 'release/*'
                            branch 'hotfix/*'
                            branch 'master'
                        }
                    }
                    environment {
                        KUBECONFIG = "/tmp/configs/kubeconfig"
                        SEMANTIC_VERSION = expression {return mavenSemanticVersion("readOnly": true).versionShort}
                    }
                    agent {
                        docker {
                            args "-v /var/run/docker.sock:/var/run/docker.sock"
                            image 'emilioforrer/ci-tools:latest'
                            reuseNode true
                        }
                    }
                    steps {
                        loadJsonEnv() {
                            withEnv(["SEMANTIC_VERSION=${SEMANTIC_VERSION}"]) {
                                dir("./tmp") {
                                    writeFile(file: "kubeconfig", text: "${KUBECONFIG_FILE}")
                                    writeFile(file: "values.yaml", text: "${VALUES_FILE}")
                                }
                                sh "mv ./tmp /tmp/configs"
                                sh "echo 'Upgrading Helm Chart'"
                                sh 'sed -i "/export REPOSITORY_NAME=/c\\export REPOSITORY_NAME=${REPOSITORY_NAME}" k8s/${REPOSITORY_NAME}/templates/NOTES.txt'
                                sh 'sed -i "/appVersion/c\\appVersion: ${SEMANTIC_VERSION}${RELEASE_PREFIX}" k8s/${REPOSITORY_NAME}/Chart.yaml'
                                sh "helm upgrade --install ${REPOSITORY_NAME} k8s/${REPOSITORY_NAME} -f /tmp/configs/values.yaml -n bancus --wait --kubeconfig /tmp/configs/kubeconfig"
                                dir("/tmp/configs") {
                                    deleteDir()
                                }
                                script {
                                    for (int i = 0; i < 10; i++) {
                                        SERVER_STATUS = sh(returnStdout: true, script: "curl -X GET '${DEPLOYMENT_BASE_URL}/${HEALTH_CHECK}' -H 'accept: */*' -s -o health -w '%{http_code}' --max-time 90").trim()
                                        echo "HTTP-${SERVER_STATUS}"
                                        if (!SERVER_STATUS.contains('200')) {
                                            echo "We can't reach out the server ${DEPLOYMENT_BASE_URL}/${HEALTH_CHECK}"
                                            sleep 5
                                        }else{
                                            break;
                                        }
                                    }
                                    if (!SERVER_STATUS.contains('200')) {
                                        error("We can't reach out the server ${DEPLOYMENT_BASE_URL}/${HEALTH_CHECK}")
                                    }
                                }
                            }
                        }
                    }
                }

                stage('Git Tag Version') {
                    when { branch 'master' }
                    steps {
                        script {
                            PROJECT_VERSION = readMavenPom().getVersion()
                        }
                        gitTagToRepo(tagName: PROJECT_VERSION, tagMessage: PROJECT_VERSION)
                    }
                }
            }
        }

        stage("Reporting") {
            failFast true
            parallel {
                stage('Git') {
                    when {
                        anyOf {
                            branch "develop"
                            branch 'release/*'
                            branch 'hotfix/*'
                            branch 'master'
                        }
                    }
                    steps {
                        loadJsonEnv() {
                            gitPushToRepo(credentialsId: GIT_CREDENTIALS)
                        }
                    }
                }

                stage('Jira') {
                    when {
                        expression {loadJsonEnv() { return "${JIRA_BUILD_SKIP}" != "true" }}
                    }
                    steps {
                        jiraUpdateIssue(transition: 'Deploy For QA')
                        jiraUpdateIssue(onlyType: 'Unit-test', fromStatus: 'Ready For QA', transition: 'Done', comment: 'You are awesome, I moved your ticket to done')
                        jiraUpdateIssue(onlySubtask: true, excludeDefect: true, fromStatus: 'Ready For QA', transition: 'Done', comment: 'You are awesome, I moved your ticket to done')
                    }
                }

                stage('Jira builds') {
                    when {
                        allOf {
                            expression {loadJsonEnv() { return "${JIRA_BUILD_SKIP}" != "true" }}
                            anyOf {
                                branch 'develop'
                                branch 'release/*'
                                branch 'hotfix/*'
                                branch 'master'
                            }
                        }
                    }
                    steps {
                        loadJsonEnv() {
                            jiraSendDeploymentInfo site: JIRA_BUILD_SITE,
                                environmentId: JIRA_ENV_ID, environmentName: JIRA_ENV_NAME, environmentType: JIRA_ENV_TYPE
                        }
                    }
                }

                stage('SonarQube') {
                    when {
                        beforeAgent true
                        allOf {
                            expression { return params.SKIP_TESTS == false }
                            anyOf {
                                branch 'develop'
                                branch 'release/*'
                                branch 'hotfix/*'
                                branch 'feature/*'
                                branch 'master'
                            }
                            anyOf {
                                triggeredBy cause: 'UserIdCause'
                                expression { loadJsonEnv() { return LAST_COMMIT_AUTHOR != "${GIT_IGNORE_COMMITS_EMAIL}" } }
                            }
                        }
                    }
                    agent {
                        docker {
                            args "-v ${HOME}/.m2:${WORKSPACE}/.m2 -e MAVEN_CONFIG=${WORKSPACE}/.m2 -e MAVEN_OPTS='-Dmaven.repo.local=${WORKSPACE}/.m2/repository'"
                            image 'maven:3.6.3-jdk-11'
                            reuseNode true
                        }
                    }
                    steps {
                        withMavenSettings() {
                            withSonarQubeEnv(env.SONARQUBE_ENV) {
                                sh 'mvn sonar:sonar -U -Dsonar.branch.name=${ORIGIN_BRANCH_NAME}'
                            }
                        }
                    }
                }
            }
        }
    }
    post {
        failure {
            slackSendBuildFailure()
        }

        success {
            slackSendBuildSuccess()
        }

        fixed {
            slackSendBuildFixed()
        }

        always {
            archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: true
            junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'

            loadJsonEnv() {
                script {
                    if ("${JIRA_BUILD_SKIP}" != "true") {
                        jiraSendBuildInfo site: JIRA_BUILD_SITE, branch: ORIGIN_BRANCH_NAME
                    }
                }
            }
        }
    }
}
