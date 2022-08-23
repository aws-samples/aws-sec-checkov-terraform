## Terraform example code to performa Checkov analysis ###
The objective is to create a pipeline to automate the security analysis and execution of infrastructure as code (terraform). The terraform code is just a sample that can be used to perform Checkov analysis.

#### Checkov
Checkov is a tool that perform security analysis on terraform code.
Using it before environment creation can bring helpfull insites

#### Teraform code for ECS/Fargate
The terraform code used to demostrate Checkov creates an ECS/Fargate cluster and all the necessary associated resources (e.g. networking, policies)

#### AWS CodePipeline
This demo is used in a pipeline that runs automaticaly every time there is a code commit in the git repository (AWS CodeCommit). The pipeline uses Checkov to analise terraform code and requests a validation of the security team to continue with environment creation/change

#### Security
See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

#### License
This library is licensed under the MIT-0 License. See the LICENSE file.