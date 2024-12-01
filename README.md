# tf-aws-infra

## Prerequisites
- **AWS Account and AWS CLI**

## Build and Deploy Instructions

1. **Clone the repository**:
    ```bash
    git clone <repository-url>
    ```

2. **Install dependencies**:
    ```bash
    terraform init
    ```

3. **Configure and export aws profile**:
   ```bash
   aws configure –profile=<>
   export AWS_PROFILE=<>
   ```

4. **create tfvars file**:
   ```bash
   values for variables
   region          = " "
   project_name    = " "
   vpc_count       = " "
   base_cidr_block = " "
   app_port        = " "
   custom_ami_id   = " "

   terraform plan -var-file="<>.tfvars"
   terraform apply -var-file="<>.tfvars"
   ```

5. **Terraform commands**:
    ```bash
    terraform fmt
    terraform validate
    terraform plan
    terraform apply
    terraform destroy
    ```


6. **Command used to import SSL Certificate**
   ``` aws acm import-certificate --certificate fileb:///Users/srijithmakam/Documents/Cloud/demo_srijithmakam.me/demo_srijithmakam_me.crt --private-key fileb:///Users/srijithmakam/Documents/Cloud/private.key --certificate-chain fileb:///Users/srijithmakam/Documents/Cloud/demo_srijithmakam.me/demo_srijithmakam_me.ca-bundle```