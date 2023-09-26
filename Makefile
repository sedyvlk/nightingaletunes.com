
TERRAFORM_VERSION=1.5.7

.PHONY: setup

setup:
	curl \
		--silent https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_linux_amd64.zip \
		--output /tmp/terraform.zip
	unzip -o /tmp/terraform.zip terraform -d bin/
	rm /tmp/terraform.zip

