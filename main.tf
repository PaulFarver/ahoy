locals {
  name        = "ahoy"
  aws_profile = "dev"
}

terraform {
  # Use remote state to store the state of the infrastructure
  backend "s3" {
    bucket  = "ahoy-terraform-state"
    key     = "terraform.tfstate"
    region  = "eu-west-1"
    profile = "dev"
  }
}


data "aws_partition" "current" {}

provider "aws" {
  region                   = "eu-west-1"
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = local.aws_profile
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Owner     = local.name
    }
  }
}

################################################################################
# VPC
################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.4"

  name = "ahoy"
  cidr = "13.37.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets = ["13.37.1.0/24", "13.37.2.0/24", "13.37.3.0/24"]
  public_subnets  = ["13.37.101.0/24", "13.37.102.0/24", "13.37.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "owned"
    "kubernetes.io/role/elb"              = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "owned"
    "kubernetes.io/role/internal-elb"     = "1"
    "karpenter.sh/discovery"              = local.name
  }

}

################################################################################
# Kubernetes cluster
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.28.0"

  cluster_name                    = "ahoy"
  cluster_version                 = "1.23"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    // When we use the eks plugin, we do not have to manually update the aws-node role or daemon set
    vpc-cni = {
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.irsa_vpc_cni.iam_role_arn
    }
    aws-ebs-csi-driver = {
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.irsa_ebs_csi.iam_role_arn
    }
  }

  node_security_group_additional_rules = {
    ingress_karpenter_webhook_tcp = {
      description                   = "Control plane invoke Karpenter webhook"
      protocol                      = "tcp"
      from_port                     = 8443
      to_port                       = 8443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = local.name
  }

  cluster_enabled_log_types = []

  eks_managed_node_groups = {
    karpenter = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      iam_role_additional_policies = [
        # Required by Karpenter
        "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
      ]
    }
  }

  manage_aws_auth_configmap = true
  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::100465710106:user/paul.farver@uniwise.dk"
      username = "paul"
      groups   = ["system:masters"]
    }
  ]

  # tags = {
  #   "karpenter.sh/discovery" = local.name
  # }
}

module "irsa_vpc_cni" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.4.0"

  role_name = "vpc-cni"
  role_path = "/${module.eks.cluster_id}/irsa/"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}

module "irsa_ebs_csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.4.0"

  role_path = "/${module.eks.cluster_id}/irsa/"
  role_name = "ebs_csi"

  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "irsa_external_dns" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.4.0"

  role_path = "/${module.eks.cluster_id}/irsa/"
  role_name = "external-dns"

  attach_external_dns_policy = true
  # external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"] # Default value

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }
}

################################################################################
# Karpenter
################################################################################
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.4.0"

  role_path                          = "/${local.name}/irsa/"
  role_name                          = "karpenter"
  attach_karpenter_controller_policy = true

  karpenter_controller_cluster_id = module.eks.cluster_id
  karpenter_controller_ssm_parameter_arns = [
    "arn:${data.aws_partition.current.partition}:ssm:*:*:parameter/aws/service/*"
  ]
  karpenter_controller_node_iam_role_arns = [
    module.eks.eks_managed_node_groups["karpenter"].iam_role_arn
  ]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--profile", local.aws_profile, "--cluster-name", module.eks.cluster_id]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--profile", local.aws_profile, "--cluster-name", module.eks.cluster_id]
    }
  }
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${local.name}"
  role = module.eks.eks_managed_node_groups["karpenter"].iam_role_name
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "0.16.1"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter_irsa.iam_role_arn
  }

  set {
    name  = "clusterName"
    value = module.eks.cluster_id
  }

  set {
    name  = "clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

  set {
    name  = "aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter.name
  }

  wait = true
}

resource "helm_release" "external_dns" {
  namespace        = "external-dns"
  create_namespace = true

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.11.0"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa_external_dns.iam_role_arn
  }

  set {
    name  = "resources.limits.memory"
    value = "200Mi"
  }
  set {
    name  = "resources.requests.memory"
    value = "200Mi"
  }
  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "extraArgs[0]"
    value = "--annotation-filter=external-dns.alpha.kubernetes.io/exclude notin (true)"
  }
}

resource "kubernetes_annotations" "default_storage_class" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  force       = true
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  allow_volume_expansion = true
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    "type" = "gp3"
  }
}
