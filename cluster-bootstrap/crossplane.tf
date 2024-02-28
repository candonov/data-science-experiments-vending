# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

#---------------------------------------------------------------
# Crossplane
#---------------------------------------------------------------
module "crossplane" {
  source = "github.com/awslabs/crossplane-on-eks/bootstrap/terraform/addon/"
  enable_crossplane = true
  crossplane = {
    chart_version = "1.15.0"
    values = [yamlencode({
      args    = ["--enable-environment-configs"]
      metrics = {
        enabled = true
      }
      resourcesCrossplane = {
        limits = {
          cpu = "1"
          memory = "2Gi"
        }
        requests = {
          cpu = "100m"
          memory = "1Gi"
        }
      }
      resourcesRBACManager = {
        limits = {
          cpu = "500m"
          memory = "1Gi"
        }
        requests = {
          cpu = "100m"
          memory = "512Mi"
        }
      }
    })]
  }

  depends_on = [module.eks.eks_managed_node_groups]
}

resource "kubectl_manifest" "environmentconfig" {
  yaml_body = templatefile("${path.module}/environmentconfig.yaml", {
    awsAccountID = data.aws_caller_identity.current.account_id
    eksOIDC      = module.eks.oidc_provider
    vpcID        = module.vpc.vpc_id
  })

  depends_on = [module.crossplane]
}

#---------------------------------------------------------------
# Crossplane Providers Settings
#---------------------------------------------------------------
locals {
  crossplane_namespace = "crossplane-system"
  
  upbound_aws_provider = {
    enable               = var.enable_upbound_aws_provider # defaults to true
    version              = "v1.1.0"
    controller_config    = "upbound-aws-controller-config"
    provider_config_name = "aws-provider-config" #this is the providerConfigName used in all the examples in this repo
    families = [
      "iam",
      "s3"
    ]
  }

  aws_provider = {
    enable               = var.enable_aws_provider # defaults to false
    version              = "v0.43.1"
    name                 = "aws-provider"
    controller_config    = "aws-controller-config"
    provider_config_name = "aws-provider-config" #this is the providerConfigName used in all the examples in this repo
  }

  kubernetes_provider = {
    enable                = var.enable_kubernetes_provider # defaults to true
    version               = "v0.12.1"
    service_account       = "kubernetes-provider"
    name                  = "kubernetes-provider"
    controller_config     = "kubernetes-controller-config"
    provider_config_name  = "default"
    cluster_role          = "cluster-admin"
  }

  helm_provider = {
    enable                = var.enable_helm_provider # defaults to true
    version               = "v0.15.0"
    service_account       = "helm-provider"
    name                  = "helm-provider"
    controller_config     = "helm-controller-config"
    provider_config_name  = "default"
    cluster_role          = "cluster-admin"
  }

}

#---------------------------------------------------------------
# Crossplane Upbound AWS Provider
#---------------------------------------------------------------
module "upbound_irsa_aws" {
  count = local.upbound_aws_provider.enable == true ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name_prefix = "${local.name}-upbound-aws-"
  assume_role_condition_test = "StringLike"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AdministratorAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.crossplane_namespace}:upbound-aws-provider-*"]
    }
  }

  tags = local.tags
}

resource "kubectl_manifest" "upbound_aws_controller_config" {
  count = local.upbound_aws_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/aws-upbound/controller-config.yaml", {
    iam-role-arn          = module.upbound_irsa_aws[0].iam_role_arn
    controller-config = local.upbound_aws_provider.controller_config
  })

  depends_on = [module.crossplane]
}

resource "kubectl_manifest" "upbound_aws_provider" {
  for_each = local.upbound_aws_provider.enable ? toset(local.upbound_aws_provider.families) : toset([])
  yaml_body = templatefile("${path.module}/providers/aws-upbound/provider.yaml", {
    family            = each.key
    version           = local.upbound_aws_provider.version
    controller-config = local.upbound_aws_provider.controller_config
  })
  wait = true

  depends_on = [kubectl_manifest.upbound_aws_controller_config]
}

# Wait for the Upbound AWS Provider CRDs to be fully created before initiating upbound_aws_provider_config
resource "time_sleep" "upbound_wait_60_seconds" {
  count           = local.upbound_aws_provider.enable == true ? 1 : 0
  create_duration = "60s"

  depends_on = [kubectl_manifest.upbound_aws_provider]
}

resource "kubectl_manifest" "upbound_aws_provider_config" {
  count = local.upbound_aws_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/aws-upbound/provider-config.yaml", {
    provider-config-name = local.upbound_aws_provider.provider_config_name
  })

  depends_on = [kubectl_manifest.upbound_aws_provider, time_sleep.upbound_wait_60_seconds]
}

#---------------------------------------------------------------
# Crossplane AWS Provider
#---------------------------------------------------------------
module "irsa_aws_provider" {
  count = local.aws_provider.enable == true ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name_prefix = "${local.name}-aws-provider-"
  assume_role_condition_test = "StringLike"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AdministratorAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.crossplane_namespace}:aws-provider-*"]
    }
  }

  tags = local.tags
}

resource "kubectl_manifest" "aws_controller_config" {
  count = local.aws_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/aws/controller-config.yaml", {
    iam-role-arn          = module.irsa_aws_provider[0].iam_role_arn
    controller-config = local.aws_provider.controller_config
  })

  depends_on = [module.crossplane]
}

resource "kubectl_manifest" "aws_provider" {
  count = local.aws_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/aws/provider.yaml", {
    aws-provider-name = local.aws_provider.name
    version           = local.aws_provider.version
    controller-config = local.aws_provider.controller_config
  })
  wait = true

  depends_on = [kubectl_manifest.aws_controller_config]
}

# Wait for the Upbound AWS Provider CRDs to be fully created before initiating aws_provider_config
resource "time_sleep" "aws_wait_60_seconds" {
  count           = local.aws_provider.enable == true ? 1 : 0
  create_duration = "60s"

  depends_on = [kubectl_manifest.aws_provider]
}

resource "kubectl_manifest" "aws_provider_config" {
  count = local.aws_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/aws/provider-config.yaml", {
    provider-config-name = local.aws_provider.provider_config_name
  })

  depends_on = [kubectl_manifest.aws_provider, time_sleep.aws_wait_60_seconds]
}


#---------------------------------------------------------------
# Crossplane Kubernetes Provider
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "kubernetes_controller" {
  count = local.kubernetes_provider.enable == true ? 1 : 0
  metadata {
    name      = local.kubernetes_provider.service_account
    namespace = local.crossplane_namespace
  }

  depends_on = [module.crossplane]
}

resource "kubectl_manifest" "kubernetes_controller_clusterolebinding" {
  count = local.kubernetes_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/kubernetes/clusterrolebinding.yaml", {
    namespace      = local.crossplane_namespace
    cluster-role   = local.kubernetes_provider.cluster_role
    sa-name        = kubernetes_service_account_v1.kubernetes_controller[0].metadata[0].name
  })
  wait = true

  depends_on = [module.crossplane]
}

resource "kubectl_manifest" "kubernetes_controller_config" {
  count = local.kubernetes_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/kubernetes/controller-config.yaml", {
    sa-name           = kubernetes_service_account_v1.kubernetes_controller[0].metadata[0].name
    controller-config = local.kubernetes_provider.controller_config
  })
  wait = true

  depends_on = [module.crossplane]
}

resource "kubectl_manifest" "kubernetes_provider" {
  count = local.kubernetes_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/kubernetes/provider.yaml", {
    version                   = local.kubernetes_provider.version
    kubernetes-provider-name  = local.kubernetes_provider.name
    controller-config         = local.kubernetes_provider.controller_config
  })
  wait = true

  depends_on = [kubectl_manifest.kubernetes_controller_config]
}

# Wait for the AWS Provider CRDs to be fully created before initiating provider_config deployment
resource "time_sleep" "wait_60_seconds_kubernetes" {
  create_duration = "60s"

  depends_on = [kubectl_manifest.kubernetes_provider]
}

resource "kubectl_manifest" "kubernetes_provider_config" {
  count = local.kubernetes_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/kubernetes/provider-config.yaml", {
    provider-config-name = local.kubernetes_provider.provider_config_name
  })

  depends_on = [kubectl_manifest.kubernetes_provider, time_sleep.wait_60_seconds_kubernetes]
}

#---------------------------------------------------------------
# Crossplane Helm Provider
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "helm_controller" {
  count = local.helm_provider.enable == true ? 1 : 0
  metadata {
    name      = local.helm_provider.service_account
    namespace = local.crossplane_namespace
  }

  depends_on = [module.crossplane]
}

resource "kubectl_manifest" "helm_controller_clusterolebinding" {
  count = local.helm_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/helm/clusterrolebinding.yaml", {
    namespace      = local.crossplane_namespace
    cluster-role   = local.helm_provider.cluster_role
    sa-name        = kubernetes_service_account_v1.helm_controller[0].metadata[0].name
  })
  wait = true

  depends_on = [module.crossplane]
}

resource "kubectl_manifest" "helm_controller_config" {
  count = local.helm_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/helm/controller-config.yaml", {
    sa-name           = kubernetes_service_account_v1.helm_controller[0].metadata[0].name
    controller-config = local.helm_provider.controller_config
  })
  wait = true

  depends_on = [module.crossplane]
}

resource "kubectl_manifest" "helm_provider" {
  count = local.helm_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/helm/provider.yaml", {
    version                   = local.helm_provider.version
    helm-provider-name  = local.helm_provider.name
    controller-config         = local.helm_provider.controller_config
  })
  wait = true

  depends_on = [kubectl_manifest.helm_controller_config]
}

# Wait for the AWS Provider CRDs to be fully created before initiating provider_config deployment
resource "time_sleep" "wait_60_seconds_helm" {
  create_duration = "60s"

  depends_on = [kubectl_manifest.helm_provider]
}

resource "kubectl_manifest" "helm_provider_config" {
  count = local.helm_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/helm/provider-config.yaml", {
    provider-config-name = local.helm_provider.provider_config_name
  })

  depends_on = [kubectl_manifest.helm_provider, time_sleep.wait_60_seconds_helm]
}

