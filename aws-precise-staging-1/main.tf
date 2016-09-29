variable "aws_heroku_org" {}
variable "cyclist_auth_tokens" {}
variable "env" { default = "precise-staging" }
variable "env_short" { default = "staging" }
variable "index" { default = 1 }
variable "syslog_address" {}
variable "worker_ami" { default = "ami-c6710cd1" }

provider "aws" {}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config {
    bucket = "travis-terraform-state"
    key = "terraform-config/aws-shared-1.tfstate"
    region = "us-east-1"
  }
}

module "aws_az_1b" {
  source = "../modules/aws_workers_az"
  az = "1b"
  bastion_security_group_id = "${data.terraform_remote_state.vpc.bastion_security_group_1b_id}"
  env = "${var.env}"
  index = "${var.index}"
  vpc_id = "${data.terraform_remote_state.vpc.vpc_id}"
}

module "aws_az_1e" {
  source = "../modules/aws_workers_az"
  az = "1e"
  bastion_security_group_id = "${data.terraform_remote_state.vpc.bastion_security_group_1e_id}"
  env = "${var.env}"
  index = "${var.index}"
  vpc_id = "${data.terraform_remote_state.vpc.vpc_id}"
}

module "aws_asg_org" {
  source = "../modules/aws_asg"
  cyclist_auth_tokens = "${var.cyclist_auth_tokens}"
  cyclist_debug = "true"
  cyclist_scale = "web=1:Hobby"
  cyclist_version = "v0.1.0"
  env = "${var.env}"
  env_short = "${var.env_short}"
  heroku_org = "${var.aws_heroku_org}"
  index = "${var.index}"
  security_groups = "${module.aws_az_1b.workers_org_security_group_id},${module.aws_az_1e.workers_org_security_group_id}"
  site = "org"
  syslog_address = "${var.syslog_address}"
  worker_ami = "${var.worker_ami}"
  worker_asg_max_size = 3
  worker_asg_min_size = 0
  worker_asg_namespace = "Travis/org-staging"
  worker_asg_scale_in_threshold = 16
  worker_asg_scale_out_threshold = 8
  worker_config = "${file("${path.module}/config/worker-env-org")}"
  worker_docker_image_android = "quay.io/travisci/ci-android:packer-1473395968"
  worker_docker_image_default = "quay.io/travisci/ci-ruby:packer-1473395984"
  worker_docker_image_erlang = "quay.io/travisci/ci-erlang:packer-1473395969"
  worker_docker_image_go = "quay.io/travisci/ci-go:packer-1473386112"
  worker_docker_image_haskell = "quay.io/travisci/ci-haskell:packer-1473395984"
  worker_docker_image_jvm = "quay.io/travisci/ci-jvm:packer-1473395987"
  worker_docker_image_node_js = "quay.io/travisci/ci-nodejs:packer-1473395973"
  worker_docker_image_perl = "quay.io/travisci/ci-perl:packer-1473395981"
  worker_docker_image_php = "quay.io/travisci/ci-php:packer-1472315712"
  worker_docker_image_python = "quay.io/travisci/ci-python:packer-1473396001"
  worker_docker_image_ruby = "quay.io/travisci/ci-ruby:packer-1473395984"
  worker_docker_self_image = "quay.io/travisci/worker:v2.4.0-23-g396d039"
  worker_queue = "docker"
  worker_subnets = "${data.terraform_remote_state.vpc.workers_org_subnet_1b_id},${data.terraform_remote_state.vpc.workers_org_subnet_1e_id}"
}

module "aws_asg_com" {
  source = "../modules/aws_asg"
  cyclist_auth_tokens = "${var.cyclist_auth_tokens}"
  cyclist_debug = "true"
  cyclist_scale = "web=1:Hobby"
  cyclist_version = "v0.1.0"
  env = "${var.env}"
  env_short = "${var.env_short}"
  heroku_org = "${var.aws_heroku_org}"
  index = "${var.index}"
  security_groups = "${module.aws_az_1b.workers_com_security_group_id},${module.aws_az_1e.workers_com_security_group_id}"
  site = "com"
  syslog_address = "${var.syslog_address}"
  worker_ami = "${var.worker_ami}"
  worker_asg_max_size = 1
  worker_asg_min_size = 0
  worker_asg_namespace = "Travis/com-staging"
  worker_asg_scale_in_threshold = 16
  worker_asg_scale_out_threshold = 8
  worker_config = "${file("${path.module}/config/worker-env-com")}"
  worker_docker_image_android = "quay.io/travisci/ci-android:packer-1473395968"
  worker_docker_image_default = "quay.io/travisci/ci-ruby:packer-1473395984"
  worker_docker_image_erlang = "quay.io/travisci/ci-erlang:packer-1473395969"
  worker_docker_image_go = "quay.io/travisci/ci-go:packer-1473386112"
  worker_docker_image_haskell = "quay.io/travisci/ci-haskell:packer-1473395984"
  worker_docker_image_jvm = "quay.io/travisci/ci-jvm:packer-1473395987"
  worker_docker_image_node_js = "quay.io/travisci/ci-nodejs:packer-1473395973"
  worker_docker_image_perl = "quay.io/travisci/ci-perl:packer-1473395981"
  worker_docker_image_php = "quay.io/travisci/ci-php:packer-1472315712"
  worker_docker_image_python = "quay.io/travisci/ci-python:packer-1473396001"
  worker_docker_image_ruby = "quay.io/travisci/ci-ruby:packer-1473395984"
  worker_docker_self_image = "quay.io/travisci/worker:v2.4.0-23-g396d039"
  worker_queue = "docker"
  worker_subnets = "${data.terraform_remote_state.vpc.workers_com_subnet_1b_id},${data.terraform_remote_state.vpc.workers_com_subnet_1e_id}"
}