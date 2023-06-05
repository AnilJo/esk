terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.65.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.3.2"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "17.23.0"

  cluster_name    = "my-eks-cluster"
  cluster_version = "1.27"  // Make sure to use a valid EKS version

  subnets = module.vpc.private_subnets
  vpc_id  = module.vpc.vpc_id

  node_groups = {
    eks_nodes = {
      desired_capacity = 2
      max_capacity     = 10
      min_capacity     = 1

      instance_type = "t2.micro"
    }
  }
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

resource "kubernetes_deployment" "example" {
  metadata {
    name = "example-deployment"
    labels = {
      App = "example-app"
    }
  }

  spec {
    replicas = 3
    selector {
      match_labels = {
        App = "example-app"
      }
    }
    template {
      metadata {
        labels = {
          App = "example-app"
        }
      }
      spec {
        container {
          image = "public.ecr.aws/w1u8a9m1/ajose:latest" // Replace with your ECR image URL
          name  = "example"

          port {
            container_port = 5000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "example" {
  metadata {
    name = "example-service"
  }
  spec {
    selector = {
      App = "${kubernetes_deployment.example.metadata.0.labels.App}"
    }
    port {
      port        = 80
      target_port = 5000
    }

    type = "LoadBalancer"
  }
}


output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster."
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster."
  value       = module.eks.cluster_iam_role_name
}

output "cluster_certificate_authority_data" {
  description = "Nested attribute containing certificate-authority-data for your cluster."
  value       = module.eks.cluster_certificate_authority_data
}
